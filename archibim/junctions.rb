# frozen_string_literal: true
# Pure Ruby wall reference-line math. No SketchUp dependency, all values in millimetres.
module SSDigitalLab
  module ArchiBIM
    module Junctions
      EPS = 0.000001
      ENDPOINT_TOLERANCE = 8.0
      MIN_ANGLE_SIN = 0.15
      MITER_LIMIT_MULTIPLIER = 4.0
      module_function

      def side_offsets(thickness, alignment)
        thickness = Float(thickness)
        case alignment.to_s
        when 'right' then [-thickness, 0.0]
        when 'center', 'middle' then [-thickness / 2.0, thickness / 2.0]
        else [0.0, thickness] # legacy walls retain their original reference face
        end
      end

      def add(a, b); [a[0] + b[0], a[1] + b[1]]; end
      def sub(a, b); [a[0] - b[0], a[1] - b[1]]; end
      def mult(a, k); [a[0] * k, a[1] * k]; end
      def dot(a, b); a[0] * b[0] + a[1] * b[1]; end
      def cross(a, b); a[0] * b[1] - a[1] * b[0]; end
      def mag(a); Math.hypot(*a); end
      def dist(a, b); mag(sub(a, b)); end
      def unit(a)
        m = mag(a)
        raise ArgumentError, 'Wall reference line is too short' if m < EPS
        mult(a, 1.0 / m)
      end
      def normal(dir); [-dir[1], dir[0]]; end

      # Each descriptor: {id:, level_id:, start:[x,y], end:[x,y], thickness:, alignment:}
      # Output {id => {'start'=>[left_x_shift,right_x_shift], 'end'=>[...]}}.
      # Miter cuts are applied to two walls with coincident ends; a branch ending on
      # another wall's interior receives a flat butt cut at the nearest face.
      def calculate(walls, allow_join: nil)
        result = {}
        walls.each { |w| result[w[:id]] = { 'start' => [0.0, 0.0], 'end' => [0.0, 0.0] } }
        walls.each do |w|
          dir = unit(sub(w[:end], w[:start])); norm = normal(dir)
          wall_length = dist(w[:start], w[:end])
          %w[start end].each do |at|
            p = w[at.to_sym]
            candidates = walls.reject { |v| v[:id] == w[:id] || v[:level_id] != w[:level_id] }
            # Prefer an exact endpoint pair before checking interior tee junctions.
            endpoint_candidates = candidates.filter_map do |v|
              mate_at = %w[start end].find do |which|
                dist(v[which.to_sym], p) <= ENDPOINT_TOLERANCE &&
                  (!allow_join || allow_join.call(w, at, v, which))
              end
              mate_at && [v, mate_at]
            end
            if endpoint_candidates.size == 1
              mate, mate_at = endpoint_candidates.first
              c = miter_cap(w, at, mate, mate_at)
              result[w[:id]][at] = c if c
              next
            end
            next unless endpoint_candidates.empty?
            candidates.each do |host|
              next if allow_join && !allow_join.call(w, at, host, nil)
              c = tee_cap(w, at, host)
              if c
                result[w[:id]][at] = c
                break
              end
            end
          end
        end
        result
      end

      def miter_cap(w, at, mate, mate_at)
        d1 = unit(sub(w[:end], w[:start])); n1 = normal(d1)
        d2 = unit(sub(mate[:end], mate[:start])); n2 = normal(d2)
        determinant = cross(d1, d2)
        return nil if determinant.abs < MIN_ANGLE_SIN
        a_offsets = side_offsets(w[:thickness], w[:alignment]); b_offsets = side_offsets(mate[:thickness], mate[:alignment])
        # When both baselines run into (or out of) the corner, opposite faces pair.
        swap_sides = (at == mate_at)
        end_pt = w[at.to_sym]
        a_offsets.each_with_index.map do |offset, i|
          other_offset = b_offsets[swap_sides ? (1 - i) : i]
          pa = add(end_pt, mult(n1, offset))
          pb = add(mate[mate_at.to_sym], mult(n2, other_offset))
          t = cross(sub(pb, pa), d2) / determinant
          # Don't create extreme spikes or caps that reverse the complete segment.
          return nil if t.abs > MITER_LIMIT_MULTIPLIER * [w[:thickness].to_f, mate[:thickness].to_f].max
          return nil if t.abs >= dist(w[:start], w[:end]) * 0.45
          t
        end
      end

      def tee_cap(w, at, host)
        p = w[at.to_sym]
        dh = unit(sub(host[:end], host[:start])); nh = normal(dh)
        dw = unit(sub(w[:end], w[:start]))
        parallel = dot(dw, nh)
        return nil if parallel.abs < MIN_ANGLE_SIN
        along = dot(sub(p, host[:start]), dh)
        host_length = dist(host[:start], host[:end])
        return nil unless along > host[:thickness].to_f && along < host_length - host[:thickness].to_f
        signed_distance = dot(sub(p, host[:start]), nh)
        # The endpoint must actually touch the host's body or centre reference line.
        low, high = side_offsets(host[:thickness], host[:alignment])
        return nil if signed_distance < low - ENDPOINT_TOLERANCE || signed_distance > high + ENDPOINT_TOLERANCE
        hits = [low, high].map { |side| (side - signed_distance) / parallel }
        hit = at == 'end' ? hits.min : hits.max
        return nil if hit.abs > host[:thickness].to_f * 2.0
        [hit, hit]
      end
    end
  end
end
