# frozen_string_literal: true
# Pure Ruby persistent wall relationship graph, in millimetres.
# Geometry belongs to the SketchUp adapter, never to this class.
require 'json'
require 'securerandom'

module SSDigitalLab
  module ArchiBIM
    class WallGraph
      SCHEMA = 1
      DEFAULT_TOLERANCE = 10.0
      MIN_LENGTH = 50.0
      MODES = %w[linked join_only unlinked].freeze
      ENDS = %w[start end].freeze
      attr_reader :records, :disabled_walls

      def initialize(raw = nil)
        raw = JSON.parse(raw) if raw.is_a?(String)
        raw = {} unless raw.is_a?(Hash)
        raise ArgumentError, 'Unsupported wall graph schema' if raw.fetch('schema', SCHEMA).to_i != SCHEMA
        @records = deep_copy(raw.fetch('connections', []))
        @disabled_walls = deep_copy(raw.fetch('disabled_walls', []))
        raise ArgumentError, 'Connections must be an array' unless @records.is_a?(Array)
        @records.each { |record| validate_record!(record) }
      end

      def to_h
        { 'schema' => SCHEMA, 'connections' => deep_copy(@records),
          'disabled_walls' => @disabled_walls.dup }
      end

      def serialize
        JSON.generate(to_h)
      end

      def connections_for(id)
        @records.select { |r| r['a'] == id || r['b'] == id }
      end

      def find(id)
        @records.find { |r| r['id'] == id }
      end

      def set_mode(id, mode, walls)
        raise ArgumentError, 'Invalid wall connection mode' unless MODES.include?(mode)
        record = find(id)
        raise ArgumentError, 'Wall connection not found' unless record
        if mode != 'unlinked'
          raise ArgumentError, 'Walls no longer touch; move them together before reconnecting' unless touching?(record, walls)
        end
        record['mode'] = mode
      end

      def unlink_wall(id)
        @disabled_walls << id unless @disabled_walls.include?(id)
        @records.each { |r| r['mode'] = 'unlinked' if r['a'] == id || r['b'] == id }
      end

      def remove_missing(walls)
        ids = walls.keys
        @records.reject! { |r| !ids.include?(r['a']) || !ids.include?(r['b']) }
        @disabled_walls &= ids
      end

      # How far a branch endpoint is from the real body of a host wall.
      # A face-aligned end is valid even when the host baseline is offset
      # by 75 mm or 150 mm. No automatic join across storeys or parallel walls.
      def tee_contact(branch, at, host, tolerance: DEFAULT_TOLERANCE)
        p = endpoint(branch, at)
        dbranch = unit(sub(branch['end'], branch['start']))
        dh = unit(sub(host['end'], host['start']))
        return nil if cross(dbranch, dh).abs < 0.15
        station, = projection(p, host['start'], host['end'])
        setback = [host['thickness'].to_f * 0.25, 25.0].min
        return nil if station <= setback || station >= length(host) - setback
        normal = [-dh[1], dh[0]]
        signed = dot(sub(p, host['start']), normal)
        low, high = face_offsets(host)
        gap = [low - signed, signed - high, 0.0].max
        return nil if gap > tolerance
        { 'station_mm' => station, 'signed_offset_mm' => signed,
          'face_low_mm' => low, 'face_high_mm' => high, 'gap_mm' => gap }
      end

      def face_offsets(wall)
        t = wall['thickness'].to_f
        case wall.fetch('alignment', 'center').to_s
        when 'right' then [-t, 0.0]
        when 'left' then [0.0, t]
        else [-t / 2.0, t / 2.0]
        end
      end

      # Detect only unambiguous endpoint/corner and branch-end T candidates.
      # Unlinked records remain as tombstones so edits cannot silently rejoin them.
      # No implicit snapping/translation or cross-level joins.
      def detect(walls, tolerance: DEFAULT_TOLERANCE, default_corner: 'linked', default_tee: 'linked')
        raise ArgumentError, 'Invalid tolerance' unless tolerance.to_f.between?(0.1, 100.0)
        remove_missing(walls)
        proposals = []
        walls.each do |id, wall|
          next if @disabled_walls.include?(id)
          ENDS.each do |at|
            next if endpoint_is_occupied?(id, at)
            p = endpoint(wall, at)
            candidates = []
            walls.each do |other_id, other|
              next if other_id == id || other['level_id'] != wall['level_id'] || @disabled_walls.include?(other_id)
              ENDS.each do |other_at|
                next if endpoint_is_occupied?(other_id, other_at)
                next if pair_excluded?(id, at, other_id, other_at)
                separation = dist(p, endpoint(other, other_at))
                if separation <= tolerance
                  angle = cross(unit(sub(wall['end'], wall['start'])), unit(sub(other['end'], other['start']))).abs
                  next if angle < 0.15 # no ambiguous collinear merging yet
                  candidates << [separation, 'corner', other_id, other_at, nil, nil]
                end
              end
              next if pair_excluded?(id, at, other_id, nil)
              contact = tee_contact(wall, at, other, tolerance: tolerance)
              if contact
                # A real T contact includes either host face, not only its
                # centre reference line. Never silently move the partition to
                # the centre: the reference point must keep its intended face.
                candidates << [contact['gap_mm'], 'tee', other_id, nil,
                               contact['station_mm'], contact['signed_offset_mm']]
              end
            end
            candidates.sort_by!(&:first)
            next if candidates.empty?
            # A near-equal second candidate needs explicit disambiguation.
            next if candidates[1] && (candidates[1][0] - candidates[0][0]).abs < 0.5
            separation, type, other_id, other_at, station, face_offset = candidates.first
            next if type == 'corner' && ([id, at] <=> [other_id, other_at]) == 1
            proposals << { 'id' => SecureRandom.uuid, 'type' => type,
                           'mode' => type == 'corner' ? default_corner : default_tee,
                           'a' => id, 'a_end' => at, 'b' => other_id,
                           'b_end' => other_at, 'station' => station,
                           'face_offset' => face_offset }
          end
        end
        added = []
        proposals.sort_by { |r| [r['type'], r['a'], r['a_end']] }.each do |record|
          next if endpoint_is_occupied?(record['a'], record['a_end'])
          next if record['type'] == 'corner' && endpoint_is_occupied?(record['b'], record['b_end'])
          next if pair_excluded?(record['a'], record['a_end'], record['b'], record['b_end'])
          # Deduplicate proposals from both directions and ambiguous multi-host arrangements.
          next if added.any? { |a| same_pair?(a, record) }
          validate_record!(record)
          @records << record
          added << record
        end
        added
      end

      # Explicit user action: reconnect a selected wall and promote its
      # touching legacy T junctions to movement-linked. An explicit unlinked
      # tombstone is only re-enabled when this action is selected.
      def reconnect_nearby(walls, wall_id)
        raise ArgumentError, 'Selected wall not found' unless walls.key?(wall_id)
        @disabled_walls.delete(wall_id)
        restored = []
        upgraded = []
        @records.each do |r|
          next unless r['a'] == wall_id || r['b'] == wall_id
          if r['mode'] == 'unlinked' && touching?(r, walls)
            r['mode'] = 'linked'
            restored << r['id']
          elsif r['type'] == 'tee' && r['mode'] == 'join_only' && touching?(r, walls)
            r['mode'] = 'linked'
            upgraded << r['id']
          end
        end
        added = detect(walls)
        { 'added' => added, 'restored' => restored, 'upgraded' => upgraded }
      end

      # Read-only junction audit for UI feedback and exported testing logs.
      def audit(walls, tolerance: DEFAULT_TOLERANCE)
        items = @records.map do |r|
          a = walls[r['a']]; b = walls[r['b']]
          details = { 'id' => r['id'], 'type' => r['type'], 'mode' => r['mode'],
                      'a' => r['a'], 'a_end' => r['a_end'], 'b' => r['b'],
                      'b_end' => r['b_end'], 'touching' => touching?(r, walls, tolerance: tolerance) }
          if a && b && r['type'] == 'tee'
            contact = tee_contact(a, r['a_end'], b, tolerance: tolerance)
            details['contact'] = contact
            details['stored_station_mm'] = r['station']
            details['stored_face_offset_mm'] = r['face_offset']
          elsif a && b && r['type'] == 'corner'
            details['endpoint_distance_mm'] = dist(endpoint(a, r['a_end']), endpoint(b, r['b_end']))
          end
          details
        end
        unmatched = []
        walls.each do |id, w|
          ENDS.each do |at|
            next if endpoint_is_occupied?(id, at)
            nearest = walls.filter_map do |other_id, host|
              next if id == other_id || host['level_id'] != w['level_id']
              contact = tee_contact(w, at, host, tolerance: [tolerance * 20, 250.0].max)
              contact && { 'host_id' => other_id, 'gap_mm' => contact['gap_mm'],
                           'station_mm' => contact['station_mm'],
                           'status' => contact['gap_mm'] <= tolerance ? 'touching_unlinked' : 'gap_too_large' }
            end.min_by { |entry| entry['gap_mm'] }
            unmatched << { 'wall_id' => id, 'end' => at,
                           'disabled' => @disabled_walls.include?(id),
                           'nearest_tee' => nearest } if nearest
          end
        end
        { 'wall_count' => walls.length, 'connection_count' => items.length,
          'linked_count' => items.count { |r| r['mode'] == 'linked' },
          'join_only_count' => items.count { |r| r['mode'] == 'join_only' },
          'broken_count' => items.count { |r| r['mode'] == 'linked' && !r['touching'] },
          'disabled_walls' => @disabled_walls.dup,
          'connections' => items, 'nearby_unconnected' => unmatched.first(120) }
      end

      # Do not convert graph edges to mesh joins unless permission is active.
      def allows_geometry?(id, at, other_id, other_at)
        @records.any? do |r|
          next false if r['mode'] == 'unlinked'
          if r['type'] == 'corner'
            (r['a'] == id && r['a_end'] == at && r['b'] == other_id && r['b_end'] == other_at) ||
              (r['b'] == id && r['b_end'] == at && r['a'] == other_id && r['a_end'] == other_at)
          else
            r['a'] == id && r['a_end'] == at && r['b'] == other_id
          end
        end
      end

      # Side effect-free preview/constraint solution. Moving the chosen wall
      # rigidly moves both its endpoints; only directly linked neighbors change
      # their touching endpoint. No recursive propagation around a room cycle.
      # Returns {'walls'=>full proposed set, 'changed'=>ids}.
      def move_plan(walls, id, dx:, dy:)
        connections_for(id).each do |link|
          next unless link['mode'] == 'linked'
          unless touching?(link, walls)
            raise ArgumentError, 'A previously linked wall junction is no longer touching. Reconnect or Unlink it before moving.'
          end
        end
        before = deep_copy(walls)
        updated = deep_copy(walls)
        selected = updated.fetch(id)
        delta = [Float(dx), Float(dy)]
        raise ArgumentError, 'Invalid displacement' unless delta.all?(&:finite?)
        %w[start end].each { |at| selected[at] = add(selected[at], delta) }
        changed = [id]
        connections_for(id).each do |r|
          next unless r['mode'] == 'linked'
          other_id = r['a'] == id ? r['b'] : r['a']
          other_at = r['a'] == id ? r['b_end'] : r['a_end']
          mover_at = r['a'] == id ? r['a_end'] : r['b_end']
          if r['type'] == 'tee'
            if r['a'] == id
              # A branch may slide along its host, but may not move away
              # from that host surface or beyond the host endpoints.
              next if touching?(r, updated)
              raise ArgumentError, 'Branch would leave its T-junction host; unlink before moving away'
            end
            other_at = r['a_end']
            mover_at = nil
            target = add(endpoint(before.fetch(other_id), other_at), delta)
          else
            target = endpoint(selected, mover_at)
          end
          # Both ends of a wall might be constrained; detect contradictions.
          neighbor = updated.fetch(other_id)
          neighbor[other_at] = target
          changed << other_id
        end
        changed.uniq.each do |wid|
          old = before.fetch(wid)
          wall = updated.fetch(wid)
          raise ArgumentError, "Wall #{wid} would become shorter than #{MIN_LENGTH} mm" if length(wall) < MIN_LENGTH
          wall['length'] = length(wall)
          wall['openings'] = reanchor_openings(old, wall) unless wid == id
        end
        { 'walls' => updated, 'changed' => changed.uniq }
      end

      def reanchor_openings(old, newer)
        old_length = length(old)
        new_length = length(newer)
        dnew = unit(sub(newer['end'], newer['start']))
        dold = unit(sub(old['end'], old['start']))
        deep_copy(old.fetch('openings', [])).each do |opening|
          off = Float(opening.fetch('offset'))
          width = Float(opening.fetch('width'))
          policy = opening.fetch('anchor', 'world')
          new_off = case policy
                    when 'start' then off
                    when 'end' then new_length - (old_length - off - width)
                    when 'proportional' then (off + width / 2.0) * new_length / old_length - width / 2.0
                    else
                      previous_center = add(old['start'], mult(dold, off + width / 2.0))
                      dot(sub(previous_center, newer['start']), dnew) - width / 2.0
                    end
          if new_off < -0.01 || new_off + width > new_length + 0.01
            raise ArgumentError, 'A hosted door/window would fall outside the shortened wall. Move or re-anchor the opening first.'
          end
          opening['offset'] = [[new_off, 0].max, new_length - width].min
        end
      end

      def touching?(r, walls, tolerance: DEFAULT_TOLERANCE)
        a, b = walls[r['a']], walls[r['b']]
        return false unless a && b && a['level_id'] == b['level_id']
        if r['type'] == 'corner'
          dist(endpoint(a, r['a_end']), endpoint(b, r['b_end'])) <= tolerance
        else
          !!tee_contact(a, r['a_end'], b, tolerance: tolerance)
        end
      end

      def self.wall(start_point, end_point, level_id: 'GF', thickness: 150.0, height: 3000.0, openings: [], alignment: 'center')
        { 'start' => start_point.map(&:to_f), 'end' => end_point.map(&:to_f),
          'level_id' => level_id, 'thickness' => thickness.to_f,
          'height' => height.to_f, 'alignment' => alignment, 'openings' => deep_copy(openings) }
      end

      def self.deep_copy(value); JSON.parse(JSON.generate(value)); end
      def deep_copy(value); self.class.deep_copy(value); end
      def add(a, b); [a[0] + b[0], a[1] + b[1]]; end
      def sub(a, b); [a[0] - b[0], a[1] - b[1]]; end
      def mult(a, k); [a[0] * k, a[1] * k]; end
      def dot(a, b); a[0] * b[0] + a[1] * b[1]; end
      def cross(a, b); a[0] * b[1] - a[1] * b[0]; end
      def length(w); dist(w['start'], w['end']); end
      def dist(a, b); Math.hypot(a[0] - b[0], a[1] - b[1]); end
      def unit(a); m = Math.hypot(*a); raise ArgumentError, 'Zero-length reference line' if m < 0.0001; [a[0] / m, a[1] / m]; end
      def endpoint(w, at); w.fetch(at); end
      def projection(p, a, b)
        axis = sub(b, a)
        m = Math.hypot(*axis)
        return [0.0, Float::INFINITY] if m < 0.0001
        d = unit(axis)
        station = dot(sub(p, a), d)
        [station, dist(p, add(a, mult(d, station)))]
      end

      def endpoint_is_occupied?(id, at)
        @records.any? { |r| (r['a'] == id && r['a_end'] == at) ||
                            (r['type'] == 'corner' && r['b'] == id && r['b_end'] == at) }
      end
      def pair_excluded?(id, at, other_id, other_at)
        @records.any? do |r|
          next false unless r['mode'] == 'unlinked'
          (r['a'] == id && r['a_end'] == at && r['b'] == other_id && (other_at.nil? || r['b_end'] == other_at)) ||
            (r['b'] == id && r['b_end'] == at && r['a'] == other_id)
        end
      end
      def same_pair?(a, b)
        a['a'] == b['a'] && a['a_end'] == b['a_end'] && a['b'] == b['b'] && a['b_end'] == b['b_end'] ||
          a['type'] == 'corner' && b['type'] == 'corner' && a['a'] == b['b'] && a['a_end'] == b['b_end'] && a['b'] == b['a'] && a['b_end'] == b['a_end']
      end
      def validate_record!(r)
        raise ArgumentError, 'Invalid join mode' unless MODES.include?(r['mode'])
        raise ArgumentError, 'Invalid join type' unless %w[corner tee].include?(r['type'])
        raise ArgumentError, 'Invalid first endpoint' unless ENDS.include?(r['a_end'])
        raise ArgumentError, 'Invalid wall ID' if r['a'].to_s.empty? || r['b'].to_s.empty? || r['a'] == r['b']
        raise ArgumentError, 'Invalid connection ID' if r['id'].to_s.empty?
        raise ArgumentError, 'Invalid second endpoint' if r['type'] == 'corner' && !ENDS.include?(r['b_end'])
      end
    end
  end
end
