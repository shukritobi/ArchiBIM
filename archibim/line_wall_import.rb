# frozen_string_literal: true
# Pure Ruby 2D graph preparation for native SketchUp edges. Distances are mm.
# The SketchUp adapter owns entity selection, transactions and BIM creation.
module SSDigitalLab
  module ArchiBIM
    module LineWallImport
      extend self
      MIN_WALL = 50.0
      PLANE_TOLERANCE = 1.0
      SNAP_TOLERANCE = 1.0
      EPS = 1.0e-7
      MAX_EDGES = 500

      def build(edges, plane_tolerance: PLANE_TOLERANCE, snap_tolerance: SNAP_TOLERANCE)
        raise ArgumentError, 'Select one or more native SketchUp lines first' if edges.empty?
        raise ArgumentError, "Too many connected lines (maximum #{MAX_EDGES}); select a smaller network" if edges.size > MAX_EDGES
        raise ArgumentError, 'Invalid tolerance' unless plane_tolerance > 0 && snap_tolerance > 0
        points = edges.flat_map { |e| [e.fetch(:a), e.fetch(:b)] }
        raise ArgumentError, 'Each line endpoint must contain finite x, y, z coordinates in mm' unless points.all? { |p| p.size == 3 && p.all? { |v| v.is_a?(Numeric) && v.finite? } }
        zs = points.map(&:last)
        raise ArgumentError, "Lines must lie on ONE horizontal plane (Z spread #{(zs.max - zs.min).round(2)} mm)" if zs.max - zs.min > plane_tolerance
        nodes = []
        segments = []
        edges.each do |e|
          a = snapped_node(e[:a].first(2), nodes, snap_tolerance)
          b = snapped_node(e[:b].first(2), nodes, snap_tolerance)
          raise ArgumentError, 'A selected edge collapses to a point after snapping' if distance(a, b) < EPS
          segments << { a: a, b: b, sources: [e[:id].to_s] }
        end
        segments = unique_segments(segments)
        reject_overlaps!(segments, snap_tolerance)
        segments = merge_straights(segments, snap_tolerance)
        segments = split_crossings(segments, snap_tolerance)
        reject_overlaps!(segments, snap_tolerance)
        raise ArgumentError, 'A resulting wall segment is shorter than 50 mm; clean up the linework' if segments.any? { |s| distance(s[:a], s[:b]) < MIN_WALL - EPS }
        junctions = find_junctions(segments, snap_tolerance)
        { plane_z_mm: zs.sum / zs.size.to_f,
          segments: segments, junctions: junctions,
          counts: { 'corners' => junctions.count { |j| j[:type] == 'corner' },
                    'tees' => junctions.count { |j| j[:type] == 'tee' },
                    'crossings' => junctions.count { |j| j[:type] == 'cross' },
                    'multiway' => junctions.count { |j| j[:type] == 'multiway' },
                    'straights' => junctions.count { |j| j[:type] == 'straight' } } }
      end

      def snapped_node(point, nodes, tolerance)
        prior = nodes.find { |p| distance(p, point) <= tolerance }
        return prior if prior
        result = point.map(&:to_f).freeze
        nodes << result
        result
      end

      def distance(a, b)
        Math.hypot(a[0] - b[0], a[1] - b[1])
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1]]
      end

      def cross(a, b)
        a[0] * b[1] - a[1] * b[0]
      end

      def dot(a, b)
        a[0] * b[0] + a[1] * b[1]
      end

      def unique_segments(segments)
        seen = {}
        segments.each_with_object([]) do |s, out|
          key = [s[:a], s[:b]].map { |p| p.map { |v| v.round(5) } }.sort
          if seen.key?(key)
            seen[key][:sources].concat(s[:sources]).uniq!
          else
            seen[key] = s
            out << s
          end
        end
      end

      def reject_overlaps!(segments, tolerance)
        segments.each_with_index do |a, i|
          segments[(i + 1)..].each do |b|
            v = sub(a[:b], a[:a]); w = sub(b[:b], b[:a])
            next if cross(v, w).abs > EPS * distance(a[:a], a[:b]) * distance(b[:a], b[:b])
            next if cross(v, sub(b[:a], a[:a])).abs / distance(a[:a], a[:b]) > tolerance
            axis = [v[0] / distance(a[:a], a[:b]), v[1] / distance(a[:a], a[:b])]
            projections = [dot(sub(b[:a], a[:a]), axis), dot(sub(b[:b], a[:a]), axis)].minmax
            overlap = [projections[1], distance(a[:a], a[:b])].min - [projections[0], 0.0].max
            raise ArgumentError, 'Overlapping collinear lines detected; remove overlapping segments' if overlap > tolerance
          end
        end
      end

      def merge_straights(segments, tolerance)
        loop do
          changed = false
          segments.each_with_index do |s, i|
            segments.each_with_index do |t, j|
              next if j <= i
              pairs = [[s[:a], s[:b]], [s[:b], s[:a]]]
              pair_t = [[t[:a], t[:b]], [t[:b], t[:a]]]
              pairs.each do |shared, far|
                pair_t.each do |other_shared, other_far|
                  next if distance(shared, other_shared) > tolerance
                  u = sub(far, shared); v = sub(other_far, shared)
                  next if dot(u, v) >= 0
                  next if cross(u, v).abs > EPS * distance(far, shared) * distance(other_far, shared)
                  merged = { a: far, b: other_far, sources: (s[:sources] + t[:sources]).uniq }
                  segments = segments.each_with_index.filter_map { |item, k| item unless k == i || k == j }
                  segments << merged
                  changed = true
                  break
                end
                break if changed
              end
              break if changed
            end
            break if changed
          end
          break unless changed
        end
        unique_segments(segments)
      end

      def intersection(s, t)
        p = s[:a]; r = sub(s[:b], p)
        q = t[:a]; v = sub(t[:b], q)
        denominator = cross(r, v)
        return nil if denominator.abs <= EPS * distance(s[:a], s[:b]) * distance(t[:a], t[:b])
        delta = sub(q, p)
        f = cross(delta, v) / denominator
        g = cross(delta, r) / denominator
        return nil unless f.between?(-EPS, 1 + EPS) && g.between?(-EPS, 1 + EPS)
        [[p[0] + f * r[0], p[1] + f * r[1]], f, g]
      end

      def split_crossings(segments, tolerance)
        # Keep one entire host through an X, splitting only the other line.
        # Existing WallGraph then registers TWO ordinary T junctions.
        loop do
          split = false
          segments.each_with_index do |s, i|
            segments.each_with_index do |t, j|
              next if j <= i
              hit = intersection(s, t)
              next unless hit
              p, f, g = hit
              next unless f > EPS && f < 1 - EPS && g > EPS && g < 1 - EPS
              # Prefer the longer wall as the host. The shorter line becomes branches.
              index = distance(s[:a], s[:b]) >= distance(t[:a], t[:b]) ? j : i
              line = segments[index]
              raise ArgumentError, 'Crossing is too close to an endpoint for a 50 mm wall' if [distance(line[:a], p), distance(p, line[:b])].min < MIN_WALL
              segments = segments.each_with_index.filter_map { |item, k| item unless k == index }
              segments << { a: line[:a], b: p, sources: line[:sources].dup }
              segments << { a: p, b: line[:b], sources: line[:sources].dup }
              split = true
              break
            end
            break if split
          end
          break unless split
        end
        segments
      end

      def find_junctions(segments, tolerance)
        positions = segments.flat_map { |s| [s[:a], s[:b]] }
        segments.each do |s|
          segments.each do |host|
            next if s.equal?(host)
            [s[:a], s[:b]].each do |p|
              len = distance(host[:a], host[:b]); v = sub(host[:b], host[:a])
              f = dot(sub(p, host[:a]), v) / (len * len)
              if f > EPS && f < 1 - EPS && cross(sub(p, host[:a]), v).abs / len <= tolerance
                positions << p
              end
            end
          end
        end
        unique = []
        positions.each { |p| unique << p unless unique.any? { |q| distance(q, p) <= tolerance } }
        unique.filter_map do |p|
          endpoint_count = segments.count { |s| distance(s[:a], p) <= tolerance || distance(s[:b], p) <= tolerance }
          interior_count = segments.count do |s|
            len = distance(s[:a], s[:b]); v = sub(s[:b], s[:a]); f = dot(sub(p, s[:a]), v) / (len * len)
            f > EPS && f < 1 - EPS && cross(sub(p, s[:a]), v).abs / len <= tolerance
          end
          type = if interior_count == 1 && endpoint_count >= 2 then 'cross'
                 elsif interior_count == 1 && endpoint_count == 1 then 'tee'
                 elsif endpoint_count >= 3 then 'multiway'
                 elsif endpoint_count == 2 then 'corner'
                 else nil end
          type && { type: type, point: p, wall_count: endpoint_count + interior_count }
        end
      end
    end
  end
end
