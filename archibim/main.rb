# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'csv'
require 'securerandom'
require_relative 'core'
require_relative 'geometry'
require_relative 'tools'

module SSDigitalLab
  module ArchiBIM
    extend self
    VERSION = '0.2.0'
    DICT = 'SSDigitalLab_ArchiBIM'
    TITLE = 'ArchiBIM'

    class SelectionWatcher < Sketchup::SelectionObserver
      def onSelectionBulkChange(_selection); ArchiBIM.refresh_panel; end
      def onSelectionAdded(_selection, _entity); ArchiBIM.refresh_panel; end
      def onSelectionRemoved(_selection, _entity); ArchiBIM.refresh_panel; end
      def onSelectionCleared(_selection); ArchiBIM.refresh_panel; end
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

    def save_settings(new_values)
      validated = Core.settings(settings.merge(new_values))
      Sketchup.active_model.set_attribute(DICT, 'settings', JSON.generate(validated))
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
      refresh_panel
    end

    def add_level(name, elevation)
      name = name.to_s.strip
      raise 'Enter a level name' if name.empty?
      raise 'A level with that name already exists' if levels.any? { |l| l['name'].casecmp?(name) }
      elev = Core.number(elevation, 'elevation', min: -1_000_000,
                         max: 1_000_000, allow_zero: true)
      list = levels
      id = "LVL_#{SecureRandom.hex(4).upcase}"
      list << { 'id' => id, 'name' => name[0, 80], 'elevation' => elev }
      set_levels(list.sort_by { |l| l['elevation'] })
      set_active_level(id)
    end

    def move_level(id, name, elevation)
      list = levels
      item = list.find { |l| l['id'] == id }
      raise 'Level not found' unless item
      name = name.to_s.strip
      raise 'Enter a level name' if name.empty?
      elev = Core.number(elevation, 'elevation', min: -1_000_000,
                         max: 1_000_000, allow_zero: true)
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
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def delete_level(id)
      raise 'Cannot remove the final level' if levels.size < 2
      raise 'Level still contains BIM objects. Reassign or remove them first.' if elements.any? { |_, d| d['level_id'] == id }
      list = levels.reject { |x| x['id'] == id }
      raise 'Level not found' if list.length == levels.length
      set_levels(list)
      set_active_level(list.first['id'])
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
                      'height' => s['wall_height'], 'thickness' => s['wall_thickness'], 'openings' => [])
        when 'beam'
          data.merge!('name' => 'Beam', 'length' => length,
                      'width' => s['beam_width'], 'depth' => s['beam_depth'],
                      'offset' => s['beam_offset'])
        when 'stair'
          data.merge!('name' => 'Stair', 'run' => length,
                      'width' => s['stair_width'], 'rise' => s['stair_rise'],
                      'steps' => s['stair_steps'])
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
        data['thickness'] = s['slab_thickness'] if kind == 'slab'
        data['thickness'] = s['footing_thickness'] if kind == 'footing'
        if kind == 'roof'
          data['thickness'] = s['roof_thickness']
          data['pitch'] = s['roof_pitch']
          data['overhang'] = s['roof_overhang']
          data['eave_offset'] = s['roof_eave_offset']
        end
      elsif kind == 'column'
        transform = Geom::Transformation.new(Geom::Point3d.new(p1.x, p1.y, level['elevation'].mm))
        data.merge!('name' => 'Column', 'width' => s['column_width'],
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
      group.layer = model.layers[tag_for(data)] || model.layers.add(tag_for(data))
      group
    end

    def create_from_tool(kind, p1, p2)
      model = Sketchup.active_model
      data, transform = entity_payload(kind, p1, p2)
      validate_data(data)
      model.start_operation("ArchiBIM: Create #{kind}", true)
      begin
        group = create_element(data, transform)
        model.commit_operation
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
      if kind == 'roof'
        raise 'Roof pitch must be less than 80 degrees' if data['pitch'].to_f >= 80
        Core.number(data['overhang'], 'overhang', min: 0, allow_zero: true)
        Core.number(data['eave_offset'], 'eave_offset', min: 0, allow_zero: true)
      end
      if kind == 'stair'
        data['steps'] = data['steps'].to_i
        raise 'Stairs must have 1 to 100 steps' unless (1..100).cover?(data['steps'])
      end
      if kind == 'wall'
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
      allowed = %w[name code notes length height thickness width depth run rise steps offset level_id pitch overhang eave_offset]
      data = JSON.parse(JSON.generate(old))
      changes.each do |key, value|
        next unless allowed.include?(key)
        if %w[name code notes level_id].include?(key)
          data[key] = value.to_s[0, 250]
        elsif key == 'steps'
          data[key] = Core.number(value, 'steps', min: 0, max: 100).to_i
        else
          data[key] = Core.number(value, key, min: 0, allow_zero: %w[offset overhang eave_offset].include?(key))
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
        Geometry.build(group, data, model)
        group.layer = model.layers[tag_for(data)] || model.layers.add(tag_for(data))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
    end

    def place_opening(group, kind, click_x, fields = {})
      raise 'Only doors and windows are supported' unless %w[door window].include?(kind)
      original = data_for(group)
      raise 'Openings must be hosted in an ArchiBIM wall' unless original && original['kind'] == 'wall'
      s = settings
      width = Core.number(fields.fetch('width', s["#{kind}_width"]), 'opening width')
      height = Core.number(fields.fetch('height', s["#{kind}_height"]), 'opening height')
      sill = Core.number(fields.fetch('sill', kind == 'door' ? 0 : s['window_sill']),
                         'opening sill', min: 0, allow_zero: true)
      max_offset = original['length'].to_f - width
      raise 'Opening is wider than wall' if max_offset < 0
      offset = [[click_x.to_f - width / 2.0, 0.0].max, max_offset].min
      if fields.key?('offset')
        offset = Core.number(fields['offset'], 'opening offset', min: 0, allow_zero: true)
      end
      opening = { 'id' => SecureRandom.uuid, 'kind' => kind, 'offset' => offset,
                  'width' => width, 'height' => height, 'sill' => sill }
      Core.opening_valid?(opening, original['length'], original['height'], original.fetch('openings', []))
      data = JSON.parse(JSON.generate(original))
      data['openings'] << opening
      model = Sketchup.active_model
      model.start_operation("ArchiBIM: Add #{kind}", true)
      begin
        Geometry.build(group, data, model)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
      opening
    end

    def patch_opening(id, patch)
      group = selected
      old = data_for(group)
      raise 'Select a wall first' unless old && old['kind'] == 'wall'
      data = JSON.parse(JSON.generate(old))
      open = data['openings'].find { |o| o['id'] == id }
      raise 'Opening not found' unless open
      %w[offset width height sill].each do |key|
        next unless patch.key?(key)
        open[key] = Core.number(patch[key], key, min: 0, allow_zero: %w[offset sill].include?(key))
      end
      Core.wall_cells(data['length'], data['height'], data['openings'])
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Edit opening', true)
      begin
        Geometry.build(group, data, model)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      refresh_panel
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
        Geometry.build(group, data, model)
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
      { 'version' => VERSION, 'settings' => settings, 'levels' => levels,
        'active_level' => current_level['id'], 'selected' => current ? data_for(current) : nil,
        'report' => totals_report, 'model_title' => Sketchup.active_model.title.to_s }
    end

    def refresh_panel
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.ArchiBIM.receive(#{JSON.generate(panel_payload)});")
    rescue StandardError => e
      puts "ArchiBIM UI refresh: #{e.message}"
    end

    def callback_safe
      yield
    rescue StandardError => e
      UI.messagebox("ArchiBIM error:\n#{e.message}")
      puts "ArchiBIM error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    ensure
      refresh_panel
    end

    def bind_callbacks(dialog)
      dialog.add_action_callback('ready') { |_ctx| callback_safe { watch_selection(Sketchup.active_model); refresh_panel } }
      dialog.add_action_callback('tool') do |_ctx, type|
        callback_safe do
          if type == 'column'
            create_column_at_origin
          elsif %w[door window].include?(type)
            Sketchup.active_model.select_tool(OpeningTool.new(type))
          elsif %w[wall slab beam stair room roof footing].include?(type)
            Sketchup.active_model.select_tool(DrawTool.new(type))
          else
            raise 'Unknown drawing tool'
          end
        end
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
      dialog.add_action_callback('demo') { |_ctx| callback_safe { create_demo } }
      dialog.add_action_callback('refresh') { |_ctx| callback_safe { refresh_panel } }
    end

    def watch_selection(model)
      @watched ||= {}
      key = model.object_id
      return if @watched[key]
      observer = SelectionWatcher.new
      model.selection.add_observer(observer)
      @watched[key] = observer
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
      tools.add_item('Draw wall') { Sketchup.active_model.select_tool(DrawTool.new('wall')) }
      tools.add_item('Insert door') { Sketchup.active_model.select_tool(OpeningTool.new('door')) }
      tools.add_item('Insert window') { Sketchup.active_model.select_tool(OpeningTool.new('window')) }
      tools.add_item('Draw slab') { Sketchup.active_model.select_tool(DrawTool.new('slab')) }
      tools.add_separator
      tools.add_item('Export schedule to CSV') { callback_safe { export_csv } }
      tools.add_item('Export IFC') { callback_safe { export_ifc } }
      toolbar = UI::Toolbar.new('ArchiBIM')
      toolbar.add_item(panel)
      toolbar.show
      @model_watcher = ModelWatcher.new
      Sketchup.add_observer(@model_watcher)
      watch_selection(Sketchup.active_model)
      @installed = true
    end

    install_commands
  end
end
