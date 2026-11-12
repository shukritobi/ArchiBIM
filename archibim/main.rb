# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'csv'
require 'securerandom'
require_relative 'core'
require_relative 'junctions'
require_relative 'wall_graph'
require_relative 'geometry'
require_relative 'repair'
require_relative 'diagnostics'
require_relative 'tools'
require_relative 'connected_move'
require_relative 'documentation'

module SSDigitalLab
  module ArchiBIM
    extend self
    VERSION = '0.8.0'
    DICT = 'SSDigitalLab_ArchiBIM'
    TITLE = 'ArchiBIM'

    class SelectionWatcher < Sketchup::SelectionObserver
      def onSelectionBulkChange(_selection); ArchiBIM.selection_changed; end
      def onSelectionAdded(_selection, _entity); ArchiBIM.selection_changed; end
      def onSelectionRemoved(_selection, _entity); ArchiBIM.selection_changed; end
      alias onSelectedRemoved onSelectionRemoved
      def onSelectionCleared(_selection); ArchiBIM.selection_changed; end
    end

    # Logs undo/redo, with no model mutation inside transaction callbacks.
    class TransactionWatcher < Sketchup::ModelObserver
      def onTransactionCommit(model)
        Diagnostics.log('sketchup_commit')
        ArchiBIM.queue_scale_repair(model)
      end
      def onTransactionAbort(_model); Diagnostics.log('sketchup_abort'); end
      def onTransactionUndo(_model); Diagnostics.log('sketchup_undo'); end
      def onTransactionRedo(_model); Diagnostics.log('sketchup_redo'); end
    end

    class ModelWatcher < Sketchup::AppObserver
      def onNewModel(model); ArchiBIM.watch_selection(model); ArchiBIM.refresh_panel; end
      def onOpenModel(model); ArchiBIM.watch_selection(model); ArchiBIM.refresh_panel; end
      def onActivateModel(model); ArchiBIM.watch_selection(model); ArchiBIM.refresh_panel; end
    end

    def safe_json(s, default)
      return default if s.nil?
      JSON.parse(s)
    rescue JSON::ParserError, TypeError
      default
    end

    def levels
      model = Sketchup.active_model
      h = safe_json(model.get_attribute(DICT, 'levels'), nil)
      if h.nil? || !h.is_a?(Array) || h.empty?
        h = Core.default_levels
        model.set_attribute(DICT, 'levels', JSON.generate(h))
      end
      h
    end

    def settings
      Core.settings(safe_json(Sketchup.active_model.get_attribute(DICT, 'settings'), {}))
    end

    # Native model-length parser (current SketchUp model units, e.g. 20', 70', 150mm).
    def mm_from_user(value, label = 'length')
      return Core.number(value, label, min: -1_000_000, max: 1_000_000, allow_zero: true) if value.is_a?(Numeric)
      parsed = Sketchup.parse_length(value.to_s.strip)
      raise ArgumentError, "Invalid #{label}. Try 150mm, 2.4m or 8'" unless parsed
      parsed.to_l.to_mm
    end

    def fmt_mm(mm)
      Sketchup.format_length(mm.to_f.mm)
    end

    def length_field?(key)
      !%w[stair_steps roof_pitch window_panels sliding_door_panels auto_repair_scale auto_wall_join wall_alignment beam_alignment column_alignment wall_exterior_side door_mount window_mount sliding_door_mount sliding_door_direction room_add_zone roof_type roof_infill gutter_enabled downpipe_enabled truss_enabled awning_posts truss_style stair_style stair_structure stair_handrail stair_cut_slab].include?(key)
    end

    def save_settings(new_values)
      patch = new_values.dup
      patch.each do |key, value|
        next if %w[rates wall_alignment beam_alignment column_alignment wall_exterior_side door_mount window_mount sliding_door_mount sliding_door_direction sliding_door_panels room_add_zone roof_type roof_infill gutter_enabled downpipe_enabled truss_enabled awning_posts truss_style stair_style stair_structure stair_handrail auto_repair_scale auto_wall_join stair_cut_slab].include?(key)
        patch[key] = mm_from_user(value, key) if length_field?(key)
      end
      validated = Core.settings(settings.merge(patch))
      Sketchup.active_model.set_attribute(DICT, 'settings', JSON.generate(validated))
      Diagnostics.log('settings_updated', { keys: patch.keys })
      Sketchup.active_model.active_view.invalidate
      refresh_panel
    end

    def ensure_tag(name, dashed: false)
      model = Sketchup.active_model
      tag = model.layers[name]
      return tag if tag # Never overwrite the user's line style or visibility.
      tag = model.layers.add(name)
      begin
        root = name.include?('2D') ? 'ArchiBIM | 2D Graphics' : 'ArchiBIM | Building Elements'
        folder = model.layers.folders.find { |f| f.name == root } || model.layers.add_folder(root)
        tag.folder = folder
      rescue StandardError
        # Tag folders are optional for older SketchUp builds.
      end
      if dashed
        style = model.line_styles.to_a.find { |s| s.name.match?(/dash/i) } rescue nil
        tag.line_style = style if style
      end
      tag
    end

    def tags_payload
      Sketchup.active_model.layers.select { |layer| layer.name.start_with?('AB | ') }.map do |layer|
        { 'name' => layer.name, 'visible' => layer.visible?,
          'style' => (layer.line_style ? layer.line_style.name : '') }
      end.sort_by { |x| x['name'] }
    end

    def set_tag(name, visible, style = nil)
      layer = Sketchup.active_model.layers[name]
      raise 'ArchiBIM Tag not found' unless layer && layer.name.start_with?('AB | ')
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Tag display', true)
      begin
        layer.visible = !!visible
        unless style.nil?
          line_style = style.empty? ? nil : model.line_styles[style]
          raise 'Line style is not available in SketchUp' if !style.empty? && !line_style
          layer.line_style = line_style
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def set_levels(ls)
      Sketchup.active_model.set_attribute(DICT, 'levels', JSON.generate(ls))
    end

    def current_level
      list = levels
      selected_id = Sketchup.active_model.get_attribute(DICT, 'active_level', 'GF')
      list.find { |x| x['id'] == selected_id } || list.first
    end

    def set_active_level(id)
      raise 'Level not found' unless levels.any? { |x| x['id'] == id }
      Sketchup.active_model.set_attribute(DICT, 'active_level', id)
      Diagnostics.log('level_selected', { id: id })
      refresh_panel
    end

    def add_level(name, elevation)
      name = name.to_s.strip
      raise 'Enter a level name' if name.empty?
      raise 'A level with that name already exists' if levels.any? { |l| l['name'].casecmp?(name) }
      elev = mm_from_user(elevation, 'elevation')
      list = levels
      id = "LVL_#{SecureRandom.hex(4).upcase}"
      list << { 'id' => id, 'name' => name[0, 80], 'elevation' => elev }
      set_levels(list.sort_by { |l| l['elevation'] })
      Diagnostics.log('level_created', { id: id, name: name, elevation_mm: elev })
      set_active_level(id)
    end

    def move_level(id, name, elevation)
      list = levels
      item = list.find { |l| l['id'] == id }
      raise 'Level not found' unless item
      name = name.to_s.strip
      raise 'Enter a level name' if name.empty?
      elev = mm_from_user(elevation, 'elevation')
      raise 'Duplicate level name' if list.any? { |l| l['id'] != id && l['name'].casecmp?(name) }
      diff = elev - item['elevation'].to_f
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Update level', true)
      begin
        if diff.abs > 0.00001
          elements.each do |g, d|
            next unless d['level_id'] == id
            g.transformation = Geom::Transformation.translation([0, 0, diff.mm]) * g.transformation
          end
        end
        model.entities.grep(Sketchup::SectionPlane).each do |plane|
          next unless plane.get_attribute(DICT, 'level_id') == id
          # The cut remains 1200 mm above the moved level.
          plane.set_plane([Geom::Point3d.new(0, 0, (elev + 1200.0).mm),
                           Geom::Vector3d.new(0, 0, -1)])
        end
        item['name'] = name[0, 80]
        item['elevation'] = elev
        set_levels(list.sort_by { |l| l['elevation'] })
        elements.each do |g, d|
          next unless d['level_id'] == id
          g.layer = model.layers[tag_for(d)] || model.layers.add(tag_for(d))
        end
        sync_stair_slab_openings
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      Diagnostics.log('level_updated', { id: id, elevation_mm: elev })
      refresh_panel
    end

    def delete_level(id)
      raise 'Cannot remove the final level' if levels.size < 2
      raise 'Level still contains BIM objects. Reassign or remove them first.' if elements.any? { |_, d| d['level_id'] == id }
      list = levels.reject { |x| x['id'] == id }
      raise 'Level not found' if list.length == levels.length
      set_levels(list)
      set_active_level(list.first['id'])
      Diagnostics.log('level_deleted', { id: id })
    end

    def data_for(entity)
      return nil unless entity && entity.valid? && entity.is_a?(Sketchup::Group)
      raw = entity.get_attribute(DICT, 'data')
      return nil unless raw
      result = safe_json(raw, nil)
      result.is_a?(Hash) && Core::ALLOWED_KINDS.include?(result['kind']) ? result : nil
    end

    def selected
      Sketchup.active_model.selection.find { |e| data_for(e) }
    end

    def elements
      found = []
      walk = lambda do |collection, nesting|
        return if nesting > 25
        collection.each do |entity|
          next unless entity.valid?
          if entity.is_a?(Sketchup::Group)
            data = data_for(entity)
            if data
              found << [entity, data]
            elsif entity.get_attribute(DICT, 'hosted') != true
              walk.call(entity.entities, nesting + 1)
            end
          elsif entity.is_a?(Sketchup::ComponentInstance)
            walk.call(entity.definition.entities, nesting + 1)
          end
        end
      end
      walk.call(Sketchup.active_model.entities, 0)
      found
    end

    def vector_length_and_axes(p1, p2)
      dx = p2.x - p1.x
      dy = p2.y - p1.y
      length = Math.hypot(dx.to_mm, dy.to_mm)
      raise 'Two points need to be at least 50 mm apart' if length < 50.0
      x_axis = Geom::Vector3d.new(dx, dy, 0)
      x_axis.normalize!
      y_axis = Z_AXIS.cross(x_axis)
      [length, x_axis, y_axis]
    end

    def entity_payload(kind, p1, p2)
      s = settings
      level = current_level
      data = { 'id' => SecureRandom.uuid, 'kind' => kind,
               'level_id' => level['id'], 'code' => '', 'notes' => '' }
      if %w[wall beam stair].include?(kind)
        length, xaxis, yaxis = vector_length_and_axes(p1, p2)
        origin = Geom::Point3d.new(p1.x, p1.y, level['elevation'].mm)
        transform = Geom::Transformation.axes(origin, xaxis, yaxis, Z_AXIS)
        case kind
        when 'wall'
          data.merge!('name' => 'Wall', 'length' => length,
                      'height' => s['wall_height'], 'thickness' => s['wall_thickness'],
                      'alignment' => s['wall_alignment'], 'exterior_side' => s['wall_exterior_side'], 'openings' => [])
        when 'beam'
          data.merge!('name' => 'Beam', 'length' => length,
                      'width' => s['beam_width'], 'depth' => s['beam_depth'],
                      'alignment' => s['beam_alignment'],
                      'offset' => s['beam_offset'])
        when 'stair'
          data.merge!('name' => 'Stair', 'run' => length,
                      'width' => s['stair_width'], 'rise' => s['stair_rise'],
                      'steps' => s['stair_steps'], 'style' => s['stair_style'],
                      'landing' => s['stair_landing'], 'gap' => s['stair_gap'],
                      'structure' => s['stair_structure'], 'waist' => s['stair_waist'],
                      'handrail' => s['stair_handrail'], 'rail_height' => s['stair_rail_height'],
                      'rail_diameter' => s['stair_rail_diameter'], 'post_spacing' => s['stair_post_spacing'],
                      'max_riser' => s['stair_max_riser'], 'min_tread' => s['stair_min_tread'],
                      'cut_slab' => s['stair_cut_slab'], 'hole_clearance' => s['stair_hole_clearance'])
        end
      elsif %w[slab room roof footing].include?(kind)
        x0, x1 = [p1.x, p2.x].minmax
        y0, y1 = [p1.y, p2.y].minmax
        width = (x1 - x0).to_mm
        depth = (y1 - y0).to_mm
        raise 'Rectangle must be at least 50 × 50 mm' if width < 50 || depth < 50
        transform = Geom::Transformation.new(Geom::Point3d.new(x0, y0, level['elevation'].mm))
        data.merge!('name' => (kind == 'room' ? "Room #{elements.count { |_, d| d['kind'] == 'room' } + 1}" : 'Slab'),
                    'width' => width, 'depth' => depth)
        if kind == 'slab'
          data['thickness'] = s['slab_thickness']
          data['cutouts'] = []
        end
        data['thickness'] = s['footing_thickness'] if kind == 'footing'
        if kind == 'roof'
          data['thickness'] = s['roof_thickness']
          data['pitch'] = s['roof_pitch']
          data['overhang'] = s['roof_overhang']
          data['eave_offset'] = s['roof_eave_offset']
          data['roof_type'] = s['roof_type']
          data['infill'] = s['roof_infill']
          data['infill_thickness'] = s['roof_infill_thickness']
          %w[gutter_enabled downpipe_enabled gutter_width gutter_depth downpipe_diameter downpipe_drop truss_enabled truss_style truss_spacing truss_member awning_posts].each do |key|
            data[key] = s[key]
          end
        end
      elsif kind == 'column'
        transform = Geom::Transformation.new(Geom::Point3d.new(p1.x, p1.y, level['elevation'].mm))
        data.merge!('name' => 'Column', 'alignment' => s['column_alignment'],
                    'width' => s['column_width'],
                    'depth' => s['column_depth'], 'height' => s['column_height'])
      else
        raise "Unsupported element #{kind}"
      end
      [data, transform]
    end

    def tag_for(data)
      level = levels.find { |l| l['id'] == data['level_id'] }
      label = level ? level['name'] : 'Unknown'
      "AB | #{data['kind'].capitalize}s | #{label}"
    end

    def create_element(data, transform)
      model = Sketchup.active_model
      group = model.entities.add_group
      group.transformation = transform
      Geometry.build(group, data, model)
      group.layer = ensure_tag(tag_for(data))
      group
    end

    def wall_descriptor(group, data)
      t = group.transformation
      start = ORIGIN.transform(t)
      finish = Geom::Point3d.new(data['length'].to_f.mm, 0, 0).transform(t)
      { id: data['id'], level_id: data['level_id'],
        start: [start.x.to_mm, start.y.to_mm],
        end: [finish.x.to_mm, finish.y.to_mm],
        thickness: data['thickness'].to_f, alignment: data.fetch('alignment', 'left') }
    end

    # The graph is stored on the SKP model, not on transient entity IDs.
    # JSON persistence is undoable as part of the caller's model operation.
    def stored_wall_graph
      WallGraph.new(safe_json(Sketchup.active_model.get_attribute(DICT, 'wall_graph_v1'), {}))
    end

    def wall_inventory
      result = {}
      elements.each do |group, data|
        next unless data['kind'] == 'wall'
        id = data.fetch('id')
        raise "Duplicate BIM wall ID #{id[0, 8]}. Make wall IDs unique before connecting." if result.key?(id)
        desc = wall_descriptor(group, data)
        result[id] = WallGraph.wall(desc[:start], desc[:end],
                                    level_id: data['level_id'],
                                    thickness: data['thickness'],
                                    height: data['height'],
                                    alignment: data.fetch('alignment', 'left'),
                                    openings: data.fetch('openings', []))
      end
      result
    end

    def graph_feedback(message, report = nil)
      @graph_feedback = { 'message' => message.to_s, 'report' => report,
                          'at' => Time.now.strftime('%H:%M:%S') }
      Sketchup.status_text = "ArchiBIM: #{message}"
      Diagnostics.log('graph_ui_feedback', @graph_feedback)
    end

    def save_wall_graph(graph)
      data = graph.serialize
      current = Sketchup.active_model.get_attribute(DICT, 'wall_graph_v1')
      Sketchup.active_model.set_attribute(DICT, 'wall_graph_v1', data) if current != data
    end

    def reconcile_wall_graph(walls = nil)
      walls ||= wall_inventory
      graph = stored_wall_graph
      added = settings.fetch('auto_wall_join', true) ? graph.detect(walls) : []
      graph.remove_missing(walls)
      save_wall_graph(graph)
      added.each do |link|
        Diagnostics.log('graph_link_created', { id: link['id'], type: link['type'],
              mode: link['mode'], a: link['a'], a_end: link['a_end'],
              b: link['b'], b_end: link['b_end'],
              face_offset_mm: link['face_offset'], station_mm: link['station'] })
      end
      audit = graph.audit(walls)
      Diagnostics.log('graph_auto_scan', { added: added.length, walls: walls.length,
          total_links: graph.records.length, linked: audit['linked_count'],
          join_only: audit['join_only_count'], broken: audit['broken_count'],
          near_unconnected: audit['nearby_unconnected'].first(10) })
      graph
    end

    def wall_connections_payload(wall_id)
      graph = stored_wall_graph
      items = elements.each_with_object({}) { |(_, d), h| h[d['id']] = d }
      inventory = wall_inventory
      graph.connections_for(wall_id).map do |r|
        on_a = r['a'] == wall_id
        mate = on_a ? r['b'] : r['a']
        my_at = on_a ? r['a_end'] : (r['b_end'] || 'interior')
        { 'id' => r['id'], 'mode' => r['mode'], 'type' => r['type'],
          'at' => my_at || 'interior', 'other_id' => mate,
          'other_name' => items.fetch(mate, {}).fetch('name', mate[0, 8]),
          'touching' => graph.touching?(r, inventory),
          'station_mm' => r['station'], 'face_offset_mm' => r['face_offset'] }
      end
    end

    def edit_wall_connection(join_id, mode)
      model = Sketchup.active_model
      graph = stored_wall_graph
      inv = wall_inventory
      model.start_operation('ArchiBIM: Change wall connection', true)
      begin
        graph.set_mode(join_id.to_s, mode.to_s, inv)
        save_wall_graph(graph)
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
        Diagnostics.log('graph_connection_mode', { id: join_id, mode: mode })
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def unlink_entire_wall
      wall = selected
      data = data_for(wall)
      raise 'Select a wall first' unless data && data['kind'] == 'wall'
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Unlink entire wall', true)
      begin
        graph = stored_wall_graph
        graph.unlink_wall(data['id'])
        save_wall_graph(graph)
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
        Diagnostics.log('graph_unlink_wall', { id: data['id'] })
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def reconnect_wall
      group = selected
      data = data_for(group)
      raise 'Select a wall first' unless data && data['kind'] == 'wall'
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Reconnect nearby walls', true)
      begin
        graph = stored_wall_graph
        walls = wall_inventory
        before = graph.connections_for(data['id']).length
        result = graph.reconnect_nearby(walls, data['id'])
        report = graph.audit(walls)
        save_wall_graph(graph)
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
        detail = { wall_id: data['id'], before: before,
                   added: result['added'].map { |r| r['id'] },
                   upgraded: result['upgraded'], restored: result['restored'],
                   wall_connections: graph.connections_for(data['id']).size,
                   broken_links: report['broken_count'], scan: report }
        Diagnostics.log('graph_manual_scan', detail)
        if result.values.all?(&:empty?)
          graph_feedback("No new links. This wall has #{graph.connections_for(data['id']).size} recorded junction(s). See Diagnostics for nearby candidates.",
                         { 'added' => 0, 'upgraded' => 0, 'restored' => 0,
                           'junctions' => graph.connections_for(data['id']).length,
                           'broken' => report['broken_count'] })
        else
          graph_feedback("#{result['added'].length} new, #{result['upgraded'].length} T-junction(s) linked, #{result['restored'].length} reconnected.",
                         { 'added' => result['added'].length,
                           'upgraded' => result['upgraded'].length,
                           'restored' => result['restored'].length })
        end
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    # Global scan reports actual outcomes rather than silently doing nothing.
    # Promoting legacy Join Only tees must be an explicit user action.
    def scan_wall_connections(promote_tees: false)
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Scan wall connections', true)
      begin
        graph = stored_wall_graph
        walls = wall_inventory
        previous = graph.records.length
        promoted = []
        if promote_tees
          graph.records.each do |r|
            next unless r['type'] == 'tee' && r['mode'] == 'join_only'
            next unless graph.touching?(r, walls)
            r['mode'] = 'linked'
            promoted << r['id']
          end
        end
        added = graph.detect(walls)
        report = graph.audit(walls)
        save_wall_graph(graph)
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
        Diagnostics.log('graph_full_scan', { previously_recorded: previous,
           added: added, upgraded: promoted, audit: report })
        graph_feedback("Scanned #{walls.length} walls: #{added.length} new junction(s), #{promoted.length} T-junction(s) upgraded, #{report['broken_count']} broken link(s).",
                       { 'new' => added.length, 'upgraded' => promoted.length,
                         'linked' => report['linked_count'],
                         'join_only' => report['join_only_count'],
                         'broken' => report['broken_count'],
                         'nearby_unconnected' => report['nearby_unconnected'].length })
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def rebuild_wall_junctions(reconcile: true)
      walls = elements.select { |_, data| data['kind'] == 'wall' }
      graph = reconcile ? reconcile_wall_graph : stored_wall_graph
      caps = Junctions.calculate(walls.map { |g, data| wall_descriptor(g, data) },
                                 allow_join: lambda do |w, at, v, mate_at|
                                   graph.allows_geometry?(w[:id], at, v[:id], mate_at)
                                 end)
      model = Sketchup.active_model
      walls.each do |g, data|
        new_joins = caps.fetch(data['id'], {})
        next if data.fetch('joins', {}) == new_joins
        updated = data.merge('joins' => new_joins)
        Geometry.build(g, updated, model)
      end
    end

    # Preview calculation never mutates the model (or any BIM attributes).
    def connected_wall_preview(wall_id, dx, dy)
      graph = stored_wall_graph
      graph.move_plan(wall_inventory, wall_id, dx: dx, dy: dy)
    end

    def move_connected_wall(wall_id, dx, dy)
      inv = wall_inventory
      graph = stored_wall_graph
      plan = graph.move_plan(inv, wall_id, dx: dx, dy: dy)
      groups = elements.select { |_, data| data['kind'] == 'wall' }.to_h do |g, d|
        [d['id'], [g, d]]
      end
      operations = plan.fetch('changed').map do |id|
        group, old = groups.fetch(id)
        if Repair.changed_scale?(group.transformation)
          raise 'Wall has a scaled transform. Use Repair after Scale before connected Move.'
        end
        new_wall = plan.fetch('walls').fetch(id)
        updated = JSON.parse(JSON.generate(old))
        updated['length'] = new_wall['length']
        updated['openings'] = new_wall.fetch('openings', old.fetch('openings', []))
        updated.delete('joins')
        validate_data(updated)
        a = new_wall['start']; b = new_wall['end']
        direction = Geom::Vector3d.new((b[0]-a[0]).mm, (b[1]-a[1]).mm, 0)
        direction.normalize!
        perpendicular = Z_AXIS.cross(direction)
        z = group.transformation.origin.z
        tr = Geom::Transformation.axes(Geom::Point3d.new(a[0].mm, a[1].mm, z),
                                       direction, perpendicular, Z_AXIS)
        [group, updated, tr]
      end
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Move connected walls', true)
      begin
        operations.each do |group, data, transformation|
          group.transformation = transformation
          Geometry.build(group, data, model)
        end
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
        Diagnostics.log('connected_move_commit', { id: wall_id, dx_mm: dx, dy_mm: dy,
                                                   walls_changed: plan.fetch('changed') })
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
      plan.fetch('changed')
    end

    # Nearby reference-line snapping, not just surface corner inference.
    # Use the current story plane even in an empty file with no pickable faces.
    def workplane_pick(view, x, y)
      ray = view.pickray(x, y)
      return nil if ray[1].z.abs < 0.000001
      z = current_level['elevation'].mm
      t = (z - ray[0].z) / ray[1].z
      ray[0].offset(ray[1], t)
    end

    def snap_wall_point(point, view, x, y)
      wanted_z = current_level['elevation'].mm
      candidates = []
      elements.each do |group, data|
        next unless data['kind'] == 'wall' && data['level_id'] == current_level['id']
        transform = group.transformation
        a = ORIGIN.transform(transform)
        b = Geom::Point3d.new(data['length'].to_f.mm, 0, 0).transform(transform)
        [a, b].each { |p| candidates << p }
        dx = b.x - a.x; dy = b.y - a.y
        denom = dx * dx + dy * dy
        if denom > 0.0
          t = [[((point.x - a.x) * dx + (point.y - a.y) * dy) / denom, 0].max, 1].min
          candidates << Geom::Point3d.new(a.x + dx * t, a.y + dy * t, wanted_z)
        end
      end
      best = candidates.min_by do |p|
        screen = view.screen_coords(p)
        Math.hypot(screen.x - x, screen.y - y)
      end
      return point unless best
      projected = view.screen_coords(best)
      Math.hypot(projected.x - x, projected.y - y) <= 13.0 ? best : point
    end

    # Four independent native BIM wall objects plus an optional room area zone.
    # The drawn rectangle defines OUTER wall faces (CCW perimeter, interior to left).
    def create_room_walls(p1, p2)
      x0,x1=[p1.x,p2.x].minmax; y0,y1=[p1.y,p2.y].minmax
      w=(x1-x0).to_mm; d=(y1-y0).to_mm
      t=settings['wall_thickness'].to_f
      raise 'Room must be larger than twice wall thickness' if [w,d].min <= 2*t+50
      z=current_level['elevation'].mm
      points=[[x0,y0],[x1,y0],[x1,y1],[x0,y1]].map { |x,y| Geom::Point3d.new(x,y,z) }
      shell_id=SecureRandom.uuid
      model=Sketchup.active_model
      model.start_operation('ArchiBIM: Draw four room walls', true)
      created=[]
      begin
        %w[South East North West].each_with_index do |label,i|
          data,transform=entity_payload('wall',points[i],points[(i+1)%4])
          data.merge!('name'=>"Room #{label} wall",'alignment'=>'left',
                      'exterior_side'=>'right','room_group_id'=>shell_id)
          validate_data(data)
          created << create_element(data,transform)
        end
        if settings.fetch('room_add_zone',true)
          a=Geom::Point3d.new(x0+t.mm,y0+t.mm,z)
          b=Geom::Point3d.new(x1-t.mm,y1-t.mm,z)
          data,transform=entity_payload('room',a,b)
          data['room_group_id']=shell_id
          data['name']="Room #{elements.count { |_,e| e['kind']=='room' }+1}"
          created << create_element(data,transform)
        end
        rebuild_wall_junctions
        model.commit_operation
        Diagnostics.log('create_room_walls',{id:shell_id, walls:4, width:w, depth:d})
        model.selection.clear
        model.selection.add(created.first)
        refresh_panel
        created
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    # Recompute associations from the actual stair and slab transforms, not
    # from view pixels or the currently selected level. Maintains slab holes
    # when either the stair or the upper-floor slab is edited or added later.
    def sync_stair_slab_openings
      entries=elements
      stairs=entries.select { |_,d| d['kind']=='stair' && d.fetch('cut_slab',true) }
      slabs=entries.select { |_,d| d['kind']=='slab' }
      slabs.each do |slab,old|
        inv=slab.transformation.inverse
        slab_z=slab.transformation.origin.z
        managed=[]
        stairs.each do |stair,data|
          top=stair.transformation.origin.z+data['rise'].to_f.mm
          next if (top-slab_z).abs > 150.mm
          margin=data.fetch('hole_clearance',50.0).to_f
          run=data['run'].to_f; width=data['width'].to_f
          width=2.0*width+data.fetch('gap',150.0).to_f if data.fetch('style','straight')=='u'
          corners=[[-margin,-margin],[run+margin,-margin],
                   [run+margin,width+margin],[-margin,width+margin]].map do |x,y|
            Geom::Point3d.new(x.mm,y.mm,0).transform(stair.transformation).transform(inv)
          end
          xs=corners.map { |v| v.x.to_mm }; ys=corners.map { |v| v.y.to_mm }
          x0,x1=xs.minmax; y0,y1=ys.minmax
          next if x1 <= 0 || x0 >= old['width'].to_f || y1 <= 0 || y0 >= old['depth'].to_f
          # Holes may intersect the slab edge, in which case the edge is open.
          managed << {'id'=>"stair:#{data['id']}",'source_stair_id'=>data['id'],
                      'x0'=>x0,'x1'=>x1,'y0'=>y0,'y1'=>y1}
        end
        retained=old.fetch('cutouts',[]).reject { |h| h.key?('source_stair_id') }
        updated=retained+managed.sort_by { |h| h['source_stair_id'] }
        next if old.fetch('cutouts',[]) == updated
        data=old.merge('cutouts'=>updated)
        Geometry.build(slab,data,Sketchup.active_model)
        Diagnostics.log('stair_slab_opening_sync',{slab_id:data['id'],count:managed.length})
      end
    end

    def reset_perspective_camera
      model=Sketchup.active_model
      view=model.active_view
      groups=elements.map(&:first).select(&:valid?)
      bounds=Geom::BoundingBox.new
      groups.each { |g| bounds.add(g.bounds) }
      bounds.add(model.bounds) if bounds.empty?
      target=bounds.center
      diameter=[bounds.diagonal,1.m].max
      eye=Geom::Point3d.new(target.x-diameter,target.y-diameter,target.z+diameter*0.75)
      camera=Sketchup::Camera.new(eye,target,Z_AXIS)
      camera.perspective=true
      camera.fov=35.0
      view.camera=camera
      # A cut plan scene may still have an active section plane. Hide its cut
      # so perspective reset actually displays the complete building.
      model.rendering_options['DisplaySectionCuts']=false
      model.rendering_options['DisplaySectionPlanes']=false
      groups.empty? ? view.zoom_extents : view.zoom(groups)
      view.invalidate
      Diagnostics.log('camera_reset',{perspective:true})
    end

    def create_from_tool(kind, p1, p2)
      return create_room_walls(p1, p2) if kind == 'room_walls'
      model = Sketchup.active_model
      data, transform = entity_payload(kind, p1, p2)
      validate_data(data)
      model.start_operation("ArchiBIM: Create #{kind}", true)
      begin
        group = create_element(data, transform)
        rebuild_wall_junctions if kind == 'wall'
        sync_stair_slab_openings if %w[slab stair].include?(kind)
        model.commit_operation
        Diagnostics.log('create_element', { kind: kind, id: data['id'], dimensions: data.slice('length', 'width', 'depth', 'height') })
        model.selection.clear
        model.selection.add(group)
        refresh_panel
        group
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def create_column_at_origin
      level = current_level
      pos = Sketchup.active_model.active_view.camera.target
      z = level['elevation'].mm
      p1 = Geom::Point3d.new(pos.x, pos.y, z)
      data, transform = entity_payload('column', p1, p1)
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Create column', true)
      begin
        group = create_element(data, transform)
        model.commit_operation
        model.selection.clear
        model.selection.add(group)
        refresh_panel
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def validate_data(data)
      kind = data.fetch('kind')
      raise 'Unsupported element type' unless Core::ALLOWED_KINDS.include?(kind)
      basic_fields = case kind
                     when 'wall' then %w[length height thickness]
                     when 'slab', 'footing' then %w[width depth thickness]
                     when 'roof' then %w[width depth thickness pitch]
                     when 'column' then %w[width depth height]
                     when 'beam' then %w[length width depth]
                     when 'stair' then %w[run width rise steps]
                     when 'room' then %w[width depth]
                     end
      basic_fields.each { |key| Core.number(data[key], key, min: 0, max: 1_000_000) }
      Core.number(data['offset'], 'offset', min: 0, allow_zero: true) if kind == 'beam'
      if %w[wall beam column].include?(kind)
        raise 'Alignment must be left, center, or right' unless %w[left center right].include?(data.fetch('alignment', 'center'))
      end
      if kind == 'roof'
        raise 'Roof pitch must be less than 80 degrees' if data['pitch'].to_f >= 80
        Core.number(data['overhang'], 'overhang', min: 0, allow_zero: true)
        Core.number(data['eave_offset'], 'eave_offset', min: 0, allow_zero: true)
        raise 'Unknown roof type' unless %w[gable hip shed awning flat butterfly saltbox].include?(data.fetch('roof_type', 'gable'))
        raise 'Invalid truss type' unless %w[king_post fink].include?(data.fetch('truss_style', 'king_post'))
        %w[gutter_width gutter_depth downpipe_diameter downpipe_drop truss_spacing truss_member].each do |field|
          Core.number(data[field], field) if data.key?(field)
        end
        Core.number(data.fetch('infill_thickness', 150.0), 'infill thickness', min: 0)
      end
      if kind == 'stair'
        data['steps'] = data['steps'].to_i
        raise 'Stairs must have 1 to 100 steps' unless (1..100).cover?(data['steps'])
        raise 'Stair must be straight or U-return' unless %w[straight u].include?(data.fetch('style', 'straight'))
        if data.fetch('structure', 'waist') == 'waist'
          Core.number(data.fetch('waist', 150.0), 'waist thickness')
          raise 'Stair waist must be thinner than stair total rise' if data.fetch('waist', 150.0).to_f >= data['rise'].to_f
        end
        raise 'Stair structure must be waist or open' unless %w[waist open].include?(data.fetch('structure', 'waist'))
        Core.number(data.fetch('hole_clearance',50.0), 'stair hole clearance', min: 0, allow_zero: true)
        raise 'Stair rail side must be none, left, right or both' unless %w[none left right both].include?(data.fetch('handrail', 'both'))
        %w[rail_height rail_diameter post_spacing max_riser min_tread].each { |field| Core.number(data[field], field) if data.key?(field) }
        if data.fetch('style', 'straight') == 'u'
          raise 'U stair requires at least four steps' if data['steps'] < 4
          raise 'Landing must be shorter than total run' if data.fetch('landing', data['width']).to_f >= data['run'].to_f
        end
      end
      if kind == 'wall'
        raise 'Invalid exterior face' unless %w[left right].include?(data.fetch('exterior_side','right'))
        raise 'Wall alignment must be left, center or right' unless %w[left center right].include?(data.fetch('alignment', 'left'))
        raise 'Too many hosted openings (maximum 100)' if data.fetch('openings', []).size > 100
        Core.wall_cells(data['length'], data['height'], data.fetch('openings', []))
      end
      raise 'Level no longer exists' unless levels.any? { |l| l['id'] == data['level_id'] }
      true
    end

    def update_element(group, changes)
      old = data_for(group)
      raise 'Select an ArchiBIM element first' unless old
      raise 'Changes must be an object' unless changes.is_a?(Hash)
      allowed = %w[name code notes length height thickness width depth run rise steps offset level_id pitch overhang eave_offset alignment exterior_side roof_type infill infill_thickness gutter_enabled downpipe_enabled gutter_width gutter_depth downpipe_diameter downpipe_drop truss_enabled truss_style truss_spacing truss_member awning_posts style landing gap structure waist handrail rail_height rail_diameter post_spacing max_riser min_tread cut_slab hole_clearance]
      data = JSON.parse(JSON.generate(old))
      changes.each do |key, value|
        next unless allowed.include?(key)
        if %w[name code notes level_id alignment exterior_side roof_type truss_style style structure handrail].include?(key)
          data[key] = value.to_s[0, 250]
        elsif %w[infill cut_slab gutter_enabled downpipe_enabled truss_enabled awning_posts].include?(key)
          data[key] = !!value
        elsif key == 'steps'
          data[key] = Core.number(value, 'steps', min: 0, max: 100).to_i
        else
          data[key] = key == 'pitch' ? Core.number(value, key) : mm_from_user(value, key)
        end
      end
      data['name'] = data['kind'].capitalize if data['name'].to_s.strip.empty?
      validate_data(data)
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Edit element', true)
      begin
        if data['level_id'] != old['level_id']
          prior = levels.find { |l| l['id'] == old['level_id'] }
          after = levels.find { |l| l['id'] == data['level_id'] }
          delta = after['elevation'].to_f - (prior ? prior['elevation'].to_f : 0)
          group.transformation = Geom::Transformation.translation([0, 0, delta.mm]) * group.transformation
        end
        # Rebuild from local BIM dimensions, not the group's possibly scaled axes.
        group.transformation = Repair.normalized_transform(group.transformation)
        Geometry.build(group, data, model)
        group.layer = ensure_tag(tag_for(data))
        rebuild_wall_junctions if data['kind'] == 'wall'
        sync_stair_slab_openings if %w[slab stair].include?(data['kind']) || data['level_id'] != old['level_id']
        Diagnostics.log('update_element', { id: data['id'], kind: data['kind'], fields: changes.keys })
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def place_opening(group, kind, click_x, fields = {})
      raise 'Only hosted doors and windows are supported' unless %w[door window sliding_door].include?(kind)
      original = data_for(group)
      raise 'Openings must be hosted in an ArchiBIM wall' unless original && original['kind'] == 'wall'
      s = settings
      width = mm_from_user(fields.fetch('width', s["#{kind}_width"]), 'opening width')
      height = mm_from_user(fields.fetch('height', s["#{kind}_height"]), 'opening height')
      sill = mm_from_user(fields.fetch('sill', kind == 'window' ? s['window_sill'] : 0), 'opening sill')
      max_offset = original['length'].to_f - width
      raise 'Opening is wider than wall' if max_offset < 0
      offset = Core.clamp_opening_offset(click_x, width, original['length'])
      if fields.key?('offset')
        offset = mm_from_user(fields['offset'], 'opening offset')
      end
      opening = { 'id' => SecureRandom.uuid, 'kind' => kind, 'offset' => offset,
                  'width' => width, 'height' => height, 'sill' => sill,
                  'hinge' => fields.fetch('hinge', 'left'), 'swing' => fields.fetch('swing', 'in'),
                  'marker' => fields.fetch('marker', 'hinge'),
                  'mount' => fields.fetch('mount', s.fetch("#{kind}_mount", 'center')) }
      if kind == 'sliding_door'
        opening['panels']=s['sliding_door_panels']
        opening['slide_direction']=fields.fetch('slide_direction',s['sliding_door_direction'])
        opening['outer_frame']=45.0
        opening['inner_frame']=30.0
        opening['glass_thickness']=6.0
      elsif kind == 'window'
        opening['panels'] = s['window_panels']
        opening['outer_frame'] = s['window_outer_frame']
        opening['inner_frame'] = s['window_inner_frame']
        opening['glass_thickness'] = s['window_glass_thickness']
      end
      raise 'Invalid mounting' unless %w[center exterior interior].include?(opening['mount'])
      raise 'Invalid hinge' unless %w[left right].include?(opening['hinge'])
      raise 'Invalid swing direction' unless %w[in out].include?(opening['swing'])
      Core.opening_valid?(opening, original['length'], original['height'], original.fetch('openings', []))
      data = JSON.parse(JSON.generate(original))
      data['openings'] << opening
      model = Sketchup.active_model
      model.start_operation("ArchiBIM: Add #{kind}", true)
      begin
        group.transformation = Repair.normalized_transform(group.transformation)
        Geometry.build(group, data, model)
        Diagnostics.log('place_opening', { kind: kind, wall_id: data['id'], offset: offset, width: width })
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
      opening
    end

    def patch_opening(id, patch, wall = nil)
      group = wall || selected
      old = data_for(group)
      raise 'Select a wall first' unless old && old['kind'] == 'wall'
      data = JSON.parse(JSON.generate(old))
      open = data['openings'].find { |o| o['id'] == id }
      raise 'Opening not found' unless open
      %w[offset width height sill].each do |key|
        next unless patch.key?(key)
        open[key] = mm_from_user(patch[key], key)
      end
      %w[hinge swing marker mount slide_direction].each { |k| open[k] = patch[k] if patch.key?(k) }
      %w[outer_frame inner_frame glass_thickness].each do |k|
        open[k] = mm_from_user(patch[k], k) if patch.key?(k) && %w[window sliding_door].include?(open['kind'])
      end
      if patch.key?('panels') && %w[window sliding_door].include?(open['kind'])
        open['panels'] = Core.number(patch['panels'], 'panels', min: open['kind']=='sliding_door' ? 2 : 1, max: 4, allow_zero: true).to_i
      end
      raise 'Invalid mounting' unless %w[center exterior interior].include?(open.fetch('mount','center'))
      raise 'Invalid sliding direction' unless %w[left right].include?(open.fetch('slide_direction','left'))
      raise 'Marker must be hinge or handle' unless %w[hinge handle].include?(open.fetch('marker', 'hinge'))
      raise 'Invalid hinge' unless %w[left right].include?(open.fetch('hinge', 'left'))
      raise 'Invalid swing direction' unless %w[in out].include?(open.fetch('swing', 'in'))
      Core.wall_cells(data['length'], data['height'], data['openings'])
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Edit opening', true)
      begin
        group.transformation = Repair.normalized_transform(group.transformation)
        Geometry.build(group, data, model)
        Diagnostics.log('edit_opening', { opening_id: id, fields: patch.keys })
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def move_opening_on_wall(wall, id, center_mm)
      data=data_for(wall)
      raise 'Select a host wall' unless data && data['kind']=='wall'
      opening=data.fetch('openings',[]).find { |o| o['id']==id }
      raise 'Opening no longer exists' unless opening
      x=Core.clamp_opening_offset(center_mm,opening['width'],data['length'])
      patch_opening(id,{'offset'=>x},wall)
      Diagnostics.log('opening_drag',{id:id,wall_id:data['id'],offset_mm:x})
      x
    end

    def remove_opening(id)
      group = selected
      data = data_for(group)
      raise 'Select a wall first' unless data && data['kind'] == 'wall'
      data = JSON.parse(JSON.generate(data))
      before = data['openings'].length
      data['openings'].reject! { |o| o['id'] == id }
      raise 'Opening not found' if data['openings'].length == before
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Remove opening', true)
      begin
        group.transformation = Repair.normalized_transform(group.transformation)
        Geometry.build(group, data, model)
        Diagnostics.log('remove_opening', { opening_id: id })
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    # SketchUp native Scale alters the whole group (including thickness and height).
    # After its transaction finishes, reparameterize horizontal dimensions and
    # regenerate the BIM solid in a separate undoable operation. Never edit inside
    # ModelObserver#onTransactionCommit (SketchUp's documented restriction).
    def queue_scale_repair(model)
      return if @repairing_scale || @scale_repair_queued
      return unless model == Sketchup.active_model
      return unless settings.fetch('auto_repair_scale', true)
      @scale_repair_queued = true
      UI.start_timer(0, false) do
        @scale_repair_queued = false
        auto_repair_scales(model) if model == Sketchup.active_model
      end
    rescue StandardError => e
      Diagnostics.error('scale_repair_schedule', e)
    end

    def auto_repair_scales(model)
      return if @repairing_scale
      targets = elements.select { |group, _| Repair.changed_scale?(group.transformation) }
      return if targets.empty?
      plans = targets.map do |group, original|
        scale_x, scale_y, scale_z = Repair.scale_factors(group.transformation)
        next if scale_x < 0.01 || scale_y < 0.01 || scale_z < 0.01
        updated = Repair.scaled_data(original, scale_x, scale_y)
        validate_data(updated)
        [group, updated, Repair.normalized_transform(group.transformation), [scale_x, scale_y, scale_z]]
      rescue StandardError => error
        Diagnostics.error('auto_scale_unsupported', error)
        nil
      end.compact
      return if plans.empty?
      @repairing_scale = true
      model.start_operation('ArchiBIM: Preserve BIM dimensions after Scale', true)
      begin
        plans.each do |group, data, transformation, factors|
          group.transformation = transformation
          Geometry.build(group, data, model)
          Diagnostics.log('auto_scale_repair', { id: data['id'], factors: factors })
        end
        rebuild_wall_junctions if plans.any? { |_, d, _, _| d['kind'] == 'wall' }
        sync_stair_slab_openings if plans.any? { |_,d,_,_| %w[slab stair].include?(d['kind']) }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        Diagnostics.error('auto_scale_repair', e)
      ensure
        @repairing_scale = false
      end
      refresh_panel
    end

    # Explicit rebuilding is undoable. 'Adopt Scale' consumes SketchUp's group
    # horizontal Scale and restores unit axes; 'saved' ignores native scaling.
    def rebuild_bim(scope = 'selected', mode = 'saved')
      model = Sketchup.active_model
      targets = scope == 'all' ? elements : [[selected, data_for(selected)]].reject { |g, d| g.nil? || d.nil? }
      raise 'Select an ArchiBIM element first' if targets.empty?
      raise 'Invalid rebuild mode' unless %w[saved adopt_scale].include?(mode)
      plans = targets.map do |group, old|
        original = group.transformation
        scales = Repair.scale_factors(original)
        updated = mode == 'adopt_scale' ? Repair.scaled_data(old, scales[0], scales[1]) : Marshal.load(Marshal.dump(old))
        validate_data(updated)
        [group, updated, Repair.normalized_transform(original), scales]
      end
      model.start_operation("ArchiBIM: Rebuild #{scope} (#{mode})", true)
      begin
        plans.each do |group, data, clean, scales|
          group.transformation = clean
          Geometry.build(group, data, model)
          Diagnostics.log('rebuild', { id: data['id'], kind: data['kind'], mode: mode, previous_scale: scales })
        end
        rebuild_wall_junctions if plans.any? { |_, d, _, _| d['kind'] == 'wall' }
        sync_stair_slab_openings if plans.any? { |_,d,_,_| %w[slab stair].include?(d['kind']) }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
      plans.length
    end

    def export_diagnostics
      path = Diagnostics.export(Sketchup.active_model, elements)
      UI.messagebox("Testing log saved:\n#{path}") if path
    end

    # Parametric footprint scaling without scaling thickness, height or openings.
    # Deliberately separate from native Scale to avoid mirrored/non-uniform matrices.
    def resize_footprint(factor)
      factor = Core.number(factor, 'footprint scale', min: 0.05, max: 5.0)
      model = Sketchup.active_model
      items = elements
      raise 'No BIM elements to resize' if items.empty?
      centers = items.map { |g, _| g.transformation.origin }
      pivot_x = centers.sum(&:x) / centers.length
      pivot_y = centers.sum(&:y) / centers.length
      plans = items.map do |group, old|
        data = JSON.parse(JSON.generate(old))
        case data['kind']
        when 'wall'
          data['length'] *= factor
          (data['openings'] || []).each do |opening|
            center = (opening['offset'] + opening['width'] / 2.0) * factor
            opening['offset'] = center - opening['width'] / 2.0
          end
          data.delete('joins')
        when 'slab', 'roof', 'room', 'footing'
          %w[width depth].each { |k| data[k] *= factor }
        when 'beam', 'stair'
          key = data['kind'] == 'beam' ? 'length' : 'run'
          data[key] *= factor
        end
        validate_data(data)
        t = group.transformation
        pos = t.origin
        shift = Geom::Vector3d.new((pos.x - pivot_x) * (factor - 1.0),
                                   (pos.y - pivot_y) * (factor - 1.0), 0)
        [group, data, Geom::Transformation.translation(shift) * t]
      end
      model.start_operation('ArchiBIM: Resize footprint without scaling thickness', true)
      begin
        plans.each do |group, data, transformation|
          group.transformation = transformation
          Geometry.build(group, data, model)
        end
        rebuild_wall_junctions
        sync_stair_slab_openings
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def totals_report
      report = { 'elements' => [], 'summary' => {}, 'openings' => [], 'cost' => 0.0 }
      rates = settings['rates']
      elements.each do |_entity, data|
        q = Core.quantities(data)
        c = Core.cost(data, rates)
        level = levels.find { |l| l['id'] == data['level_id'] }
        row = { 'id' => data['id'], 'name' => data['name'], 'code' => data['code'],
                'level' => level ? level['name'] : 'Unknown', 'kind' => data['kind'],
                'quantities' => q, 'cost' => c }
        report['elements'] << row
        summary = (report['summary'][data['kind']] ||= { 'count' => 0,
                       'length_m' => 0.0, 'area_m2' => 0.0,
                       'volume_m3' => 0.0, 'cost' => 0.0 })
        summary['count'] += 1
        %w[length_m area_m2 volume_m3].each { |key| summary[key] += q[key] }
        summary['cost'] += c
        report['cost'] += c
        if data['kind'] == 'wall'
          data.fetch('openings', []).each do |o|
            report['openings'] << { 'host' => data['name'], 'level' => row['level'],
                                    'kind' => o['kind'], 'width' => o['width'],
                                    'height' => o['height'], 'sill' => o['sill'] }
          end
        end
      end
      report
    end

    def export_csv
      file = UI.savepanel('Export ArchiBIM schedule (CSV)', nil, 'ArchiBIM_Schedule.csv')
      return if file.nil?
      rows = totals_report
      CSV.open(file, 'w:UTF-8', write_headers: true,
               headers: %w[level kind code name count length_m net_area_m2 gross_area_m2 volume_m3 rate_basis_est_cost]) do |csv|
        rows['elements'].each do |item|
          q = item['quantities']
          csv << [item['level'], item['kind'], item['code'], item['name'], q['count'],
                  q['length_m'].round(4), q['net_area_m2'].round(4), q['gross_area_m2'].round(4),
                  q['volume_m3'].round(5), item['cost'].round(2)]
        end
        rows['openings'].each do |o|
          csv << [o['level'], "hosted_#{o['kind']}", '', "#{o['host']} opening #{o['width']}x#{o['height']}",
                  1, 0, (o['width'] * o['height'] / 1_000_000.0).round(4), 0, 0, 0]
        end
      end
      UI.messagebox("ArchiBIM schedule exported:\n#{file}")
    end

    def export_json
      file = UI.savepanel('Export ArchiBIM data (JSON)', nil, 'ArchiBIM_Data.json')
      return if file.nil?
      payload = { 'version' => VERSION, 'levels' => levels, 'settings' => settings,
                  'report' => totals_report, 'elements' => elements.map(&:last) }
      File.write(file, JSON.pretty_generate(payload))
      UI.messagebox("ArchiBIM data exported:\n#{file}")
    end

    def export_ifc
      model = Sketchup.active_model
      file = UI.savepanel('Export IFC 4 model', nil, 'ArchiBIM_Model.ifc')
      return unless file
      unless file.downcase.end_with?('.ifc')
        file += '.ifc'
      end
      version = Sketchup.version.to_i
      options = if version >= 2026
                  { :ifc_version => 'IFC 4', :standard_ifc_hierarchy => true,
                    :selectionset_only => false, :hidden_geometry => false,
                    :tessellated_geometry => false, :show_summary => true }
                else
                  { :show_summary => true }
                end
      if model.export(file, options)
        UI.messagebox("IFC exported. Verify its classes, geometry and hierarchy in an IFC viewer.\n#{file}")
      else
        UI.messagebox('SketchUp could not export IFC. Check your SketchUp edition/license and IFC configuration.')
      end
    rescue StandardError => e
      UI.messagebox("IFC export failed: #{e.message}. SketchUp Pro is required for native IFC export.")
    end

    def make_plan_scene
      model = Sketchup.active_model
      level = current_level
      bounds = model.bounds
      center = bounds.empty? ? ORIGIN : bounds.center
      elev = level['elevation'].mm
      cut_z = elev + 1200.mm
      eye = Geom::Point3d.new(center.x, center.y, elev + 15_000.mm)
      target = Geom::Point3d.new(center.x, center.y, elev)
      model.start_operation('ArchiBIM: Create cut plan scene', true)
      begin
        # Negative Z normal discards geometry above the 1200 mm cut, leaving
        # the storey below visible to a top-down parallel camera.
        plane = model.entities.grep(Sketchup::SectionPlane).find do |p|
          p.get_attribute(DICT, 'level_id') == level['id']
        end
        unless plane
          plane = model.entities.add_section_plane(
            Geom::Point3d.new(center.x, center.y, cut_z),
            Geom::Vector3d.new(0, 0, -1)
          )
          raise 'Could not create the SketchUp section plane' unless plane
          plane.name = "AB | #{level['name']} | +1200 mm cut"
          plane.set_attribute(DICT, 'level_id', level['id'])
        end
        plane.activate
        model.rendering_options['DisplaySectionCuts'] = true
        model.rendering_options['DisplaySectionPlanes'] = false
        camera = model.active_view.camera
        camera.set(eye, target, Y_AXIS)
        camera.perspective = false
        name = "AB | #{level['name']} | Cut plan"
        page = model.pages.add(name)
        page.use_section_planes = true
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      UI.messagebox("Created cut plan scene at level +1200 mm:\n#{name}\nAdjust scene style and add dimensions in SketchUp/LayOut as required.")
      refresh_panel
    end

    def create_demo
      model = Sketchup.active_model
      base = current_level['elevation'].mm
      wall_points = [
        [[0, 0], [8000, 0], 'South Wall'],
        [[8000, 0], [8000, 6000], 'East Wall'],
        [[8000, 6000], [0, 6000], 'North Wall'],
        [[0, 6000], [0, 0], 'West Wall']
      ]
      model.start_operation('ArchiBIM: Create demo shell', true)
      begin
        created = []
        wall_points.each_with_index do |(pa, pb, name), i|
          p1 = Geom::Point3d.new(pa[0].mm, pa[1].mm, base)
          p2 = Geom::Point3d.new(pb[0].mm, pb[1].mm, base)
          data, transform = entity_payload('wall', p1, p2)
          data['name'] = name
          data['openings'] = if i == 0
                               [{ 'id' => SecureRandom.uuid, 'kind' => 'door',
                                  'offset' => 1300.0, 'width' => 900.0,
                                  'height' => 2100.0, 'sill' => 0.0 }]
                             elsif i == 2
                               [{ 'id' => SecureRandom.uuid, 'kind' => 'window',
                                  'offset' => 2500.0, 'width' => 1600.0,
                                  'height' => 1200.0, 'sill' => 900.0 }]
                             else
                               []
                             end
          validate_data(data)
          created << create_element(data, transform)
        end
        a = Geom::Point3d.new(0, 0, base)
        b = Geom::Point3d.new(8000.mm, 6000.mm, base)
        data, trans = entity_payload('slab', a, b)
        data['name'] = 'Ground Floor Slab'
        created << create_element(data, trans)
        rebuild_wall_junctions
        model.commit_operation
        model.selection.clear
        model.selection.add(created.first)
        model.active_view.zoom_extents
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def panel_payload
      current = selected
      data = current ? data_for(current) : nil
      dimensions = Core.numeric_dimensions(settings.values)
      dimensions += levels.map { |l| l['elevation'] }
      if data
        %w[length width height thickness depth run rise offset overhang eave_offset].each do |k|
          dimensions << data[k] if data[k].is_a?(Numeric)
        end
        (data['openings'] || []).each { |o| %w[offset width height sill].each { |k| dimensions << o[k] } }
        dimensions << data['length'].to_f / 2.0 if data['kind'] == 'wall'
      end
      length_labels = dimensions.compact.grep(Numeric).to_h do |v|
        [format('%.4f', v.to_f), fmt_mm(v)]
      end
      area = if data && %w[slab room footing].include?(data['kind'])
               Sketchup.format_area(data['width'].to_f.mm * data['depth'].to_f.mm)
             end
      { 'version' => VERSION, 'settings' => settings, 'levels' => levels,
        'active_level' => current_level['id'], 'selected' => data,
        'report' => totals_report, 'model_title' => Sketchup.active_model.title.to_s,
        'length_labels' => length_labels, 'selected_area' => area,
        'wall_connections' => (data && data['kind'] == 'wall' ? wall_connections_payload(data['id']) : []),
        'graph_feedback' => @graph_feedback,
        'tags' => tags_payload,
        'line_styles' => Sketchup.active_model.line_styles.names }

    end

    def selection_changed
      id = data_for(selected)&.fetch('id', nil)
      focus = !id.nil? && id != @last_selection_id
      if id != @last_selection_id
        Diagnostics.log('selection', { id: id })
        @last_selection_id = id
      end
      refresh_panel(focus)
    end

    def refresh_panel(focus_properties = false)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.ArchiBIM.receive(#{JSON.generate(panel_payload)}, #{focus_properties ? 'true' : 'false'});")
    rescue StandardError => e
      Diagnostics.error('panel_refresh', e)
      puts "ArchiBIM UI refresh: #{e.message}"
    end

    def callback_safe
      yield
    rescue StandardError => e
      Diagnostics.error('callback', e)
      UI.messagebox("ArchiBIM error:\n#{e.message}")
      puts "ArchiBIM error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    ensure
      refresh_panel
    end

    def bind_callbacks(dialog)
      dialog.add_action_callback('ready') { |_ctx| callback_safe { watch_selection(Sketchup.active_model); refresh_panel(!selected.nil?) } }
      dialog.add_action_callback('tool') do |_ctx, type|
        callback_safe do
          Diagnostics.log('tool_started', { kind: type })
          if type == 'column'
            Sketchup.active_model.select_tool(ColumnTool.new)
          elsif %w[door window sliding_door].include?(type)
            Sketchup.active_model.select_tool(OpeningTool.new(type))
          elsif %w[wall slab beam stair room room_walls roof footing].include?(type)
            Sketchup.active_model.select_tool(DrawTool.new(type))
          else
            raise 'Unknown drawing tool'
          end
        end
      end
      dialog.add_action_callback('connected_move_tool') do |_ctx|
        callback_safe do
          wall = selected
          data = data_for(wall)
          raise 'Select an ArchiBIM wall before using Connected Move' unless data && data['kind'] == 'wall'
          # Existing v0.6 models get links inferred explicitly on activation.
          model = Sketchup.active_model
          model.start_operation('ArchiBIM: Initialize wall connections', true)
          begin
            reconcile_wall_graph
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
          Sketchup.active_model.select_tool(ConnectedMoveTool.new(data['id']))
        end
      end
      dialog.add_action_callback('connection_mode') { |_ctx, id, mode| callback_safe { edit_wall_connection(id, mode) } }
      dialog.add_action_callback('unlink_entire_wall') { |_ctx| callback_safe { unlink_entire_wall } }
      dialog.add_action_callback('reconnect_wall') { |_ctx| callback_safe { reconnect_wall } }
      dialog.add_action_callback('scan_wall_connections') { |_ctx| callback_safe { scan_wall_connections } }
      dialog.add_action_callback('link_existing_tees') { |_ctx| callback_safe { scan_wall_connections(promote_tees: true) } }
      dialog.add_action_callback('move_opening_tool') { |_ctx, id| callback_safe { Sketchup.active_model.select_tool(OpeningMoveTool.new(id.to_s)) } }
      dialog.add_action_callback('reset_camera') { |_ctx| callback_safe { reset_perspective_camera } }
      dialog.add_action_callback('sync_stair_holes') { |_ctx| callback_safe { m=Sketchup.active_model; m.start_operation('ArchiBIM: Sync stair openings',true); begin; sync_stair_slab_openings; m.commit_operation; rescue StandardError; m.abort_operation; raise; end } }
      dialog.add_action_callback('set_tag') { |_ctx, name, visible, style| callback_safe { set_tag(name, visible, style) } }
      dialog.add_action_callback('rebuild') { |_ctx, scope, mode| callback_safe { rebuild_bim(scope, mode) } }
      dialog.add_action_callback('diagnostics') { |_ctx| callback_safe { export_diagnostics } }
      dialog.add_action_callback('resize_footprint') do |_ctx, percentage|
        callback_safe { resize_footprint(Float(percentage) / 100.0) }
      end
      dialog.add_action_callback('settings') { |_ctx, data| callback_safe { save_settings(data) } }
      dialog.add_action_callback('active_level') { |_ctx, id| callback_safe { set_active_level(id) } }
      dialog.add_action_callback('add_level') { |_ctx, name, z| callback_safe { add_level(name, z) } }
      dialog.add_action_callback('edit_level') { |_ctx, id, name, z| callback_safe { move_level(id, name, z) } }
      dialog.add_action_callback('delete_level') { |_ctx, id| callback_safe { delete_level(id) } }
      dialog.add_action_callback('update_element') do |_ctx, data|
        callback_safe { update_element(selected, data) }
      end
      dialog.add_action_callback('add_opening') do |_ctx, kind, params|
        callback_safe do
          wall = selected
          d = data_for(wall)
          raise 'Select a wall first' unless d && d['kind'] == 'wall'
          place_opening(wall, kind, d['length'].to_f / 2.0, params)
        end
      end
      dialog.add_action_callback('edit_opening') { |_ctx, id, patch| callback_safe { patch_opening(id, patch) } }
      dialog.add_action_callback('delete_opening') { |_ctx, id| callback_safe { remove_opening(id) } }
      dialog.add_action_callback('csv') { |_ctx| callback_safe { export_csv } }
      dialog.add_action_callback('json') { |_ctx| callback_safe { export_json } }
      dialog.add_action_callback('ifc') { |_ctx| callback_safe { export_ifc } }
      dialog.add_action_callback('scene') { |_ctx| callback_safe { make_plan_scene } }
      dialog.add_action_callback('drawing_set') do |_ctx|
        callback_safe do
          names = Documentation.make_set
          UI.messagebox("ArchiBIM drawing scenes ready (#{names.size}):\n" + names.join("\n") + "\n\nOpen these scenes in LayOut. RCPs are previews pending ceiling objects.")
        end
      end
      dialog.add_action_callback('ai_snapshot') { |_ctx| callback_safe { Documentation.export_ai_snapshot } }
      dialog.add_action_callback('demo') { |_ctx| callback_safe { create_demo } }
      dialog.add_action_callback('refresh') { |_ctx| callback_safe { refresh_panel } }
    end

    def watch_selection(model)
      @watched ||= {}
      key = model.object_id
      return if @watched[key]
      observer = SelectionWatcher.new
      model.selection.add_observer(observer)
      transactions = TransactionWatcher.new
      model.add_observer(transactions)
      @watched[key] = [observer, transactions]
    end

    def show_panel
      unless @dialog
        @dialog = UI::HtmlDialog.new(
          :dialog_title => 'ArchiBIM | Architectural BIM',
          :preferences_key => 'ssdigitallab.archibim.panel',
          :scrollable => true, :resizable => true,
          :width => 455, :height => 830,
          :min_width => 360, :min_height => 540,
          :style => UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(__dir__, 'ui', 'panel.html'))
        bind_callbacks(@dialog)
        @dialog.set_on_closed { @dialog = nil }
      end
      @dialog.show
      watch_selection(Sketchup.active_model)
      # Waiting until DOM load to request data via `ready` callback.
    end

    def install_commands
      return if @installed
      panel = UI::Command.new('ArchiBIM BIM Manager') { show_panel }
      panel.tooltip = 'Open ArchiBIM parametric architecture / BIM manager'
      panel.status_bar_text = 'Walls, hosted doors/windows, slabs, schedules and levels.'
      panel.small_icon = File.join(__dir__, 'ui', 'toolbar_24.png')
      panel.large_icon = File.join(__dir__, 'ui', 'toolbar_48.png')
      tools = UI.menu('Extensions').add_submenu('ArchiBIM')
      tools.add_item(panel)
      tools.add_item('Move connected wall') do
        callback_safe do
          g=selected; d=data_for(g)
          raise 'Select an ArchiBIM wall first' unless d && d['kind']=='wall'
          m=Sketchup.active_model
          m.start_operation('ArchiBIM: Initialize wall connections', true)
          begin; reconcile_wall_graph; m.commit_operation; rescue StandardError; m.abort_operation; raise; end
          m.select_tool(ConnectedMoveTool.new(d['id']))
        end
      end
      tools.add_item('Draw wall') { Sketchup.active_model.select_tool(DrawTool.new('wall')) }
      tools.add_item('Insert door') { Sketchup.active_model.select_tool(OpeningTool.new('door')) }
      tools.add_item('Insert sliding door') { Sketchup.active_model.select_tool(OpeningTool.new('sliding_door')) }
      tools.add_item('Move hosted opening') { Sketchup.active_model.select_tool(OpeningMoveTool.new) }
      tools.add_item('Draw four room walls') { Sketchup.active_model.select_tool(DrawTool.new('room_walls')) }
      tools.add_item('Fit house in perspective') { reset_perspective_camera }
      tools.add_item('Insert window') { Sketchup.active_model.select_tool(OpeningTool.new('window')) }
      tools.add_item('Draw slab') { Sketchup.active_model.select_tool(DrawTool.new('slab')) }
      tools.add_item('Place column') { Sketchup.active_model.select_tool(ColumnTool.new) }
      tools.add_item('Place beam') { Sketchup.active_model.select_tool(DrawTool.new('beam')) }
      tools.add_item('Rebuild selected from saved dimensions') { callback_safe { rebuild_bim('selected', 'saved') } }
      tools.add_item('Repair selected after native Scale') { callback_safe { rebuild_bim('selected', 'adopt_scale') } }
      tools.add_item('Export testing diagnostics') { callback_safe { export_diagnostics } }
      tools.add_item('Recalculate stair-to-slab cutouts') { callback_safe { m=Sketchup.active_model; m.start_operation('ArchiBIM: Reconcile stair openings',true); begin; sync_stair_slab_openings; m.commit_operation; rescue StandardError; m.abort_operation; raise; end } }
      tools.add_item('Scan wall connections (with feedback)') { callback_safe { scan_wall_connections } }
      tools.add_item('Link existing interior T-junctions') { callback_safe { scan_wall_connections(promote_tees: true) } }
      tools.add_item('Recalculate wall junctions') { callback_safe { Sketchup.active_model.start_operation('ArchiBIM: Rejoin walls', true); rebuild_wall_junctions; Sketchup.active_model.commit_operation } }
      tools.add_separator
      tools.add_item('Generate architectural drawing set') { callback_safe { Documentation.make_set } }
      tools.add_item('Export AI-readable model snapshot') { callback_safe { Documentation.export_ai_snapshot } }
      tools.add_item('Export schedule to CSV') { callback_safe { export_csv } }
      tools.add_item('Export IFC') { callback_safe { export_ifc } }
      toolbar = UI::Toolbar.new('ArchiBIM')
      toolbar.add_item(panel)
      toolbar.show
      @model_watcher = ModelWatcher.new
      Sketchup.add_observer(@model_watcher)
      watch_selection(Sketchup.active_model)
      Diagnostics.log('extension_loaded', { sketchup: Sketchup.version })
      @installed = true
    end

    install_commands
  end
end
