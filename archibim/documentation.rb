# frozen_string_literal: true
# Model-backed views intended for SketchUp Scenes and LayOut viewports.
# These are *not* flattened CAD entities or substitute ceiling fixtures.
module SSDigitalLab
  module ArchiBIM
    module Documentation
      extend self

      DRAWING_CODES = {
        'ground' => 'A-101', 'first' => 'A-102', 'roof' => 'A-103',
        'north' => 'A-201', 'south' => 'A-202',
        'east' => 'A-203', 'west' => 'A-204',
        'section_a' => 'A-301', 'section_b' => 'A-302',
        'rcp_ground' => 'A-401', 'rcp_first' => 'A-402'
      }.freeze

      def section_plane(model, key, origin, normal)
        existing = model.entities.grep(Sketchup::SectionPlane).find do |item|
          item.get_attribute(ArchiBIM::DICT, 'drawing_key') == key
        end
        plane = existing || model.entities.add_section_plane(origin, normal)
        raise 'Unable to create drawing cut plane' unless plane
        plane.set_plane([origin, normal]) if existing
        plane.name = "AB | #{key} | section"
        plane.set_attribute(ArchiBIM::DICT, 'drawing_key', key)
        plane
      end

      def save_view(model, key, name, eye, target, up, plane = nil)
        model.entities.active_section_plane = nil
        plane.activate if plane
        model.rendering_options['DisplaySectionCuts'] = !plane.nil?
        model.rendering_options['DisplaySectionPlanes'] = false
        camera = model.active_view.camera
        camera.set(eye, target, up)
        camera.perspective = false
        page = model.pages.find { |p| p.name == "AB | #{DRAWING_CODES.fetch(key)} | #{name}" }
        page ||= model.pages.add("AB | #{DRAWING_CODES.fetch(key)} | #{name}")
        page.use_camera = true
        page.use_section_planes = true
        page.use_rendering_options = true
        flags = PAGE_USE_CAMERA | PAGE_USE_SECTION_PLANES | PAGE_USE_RENDERING_OPTIONS
        page.update(flags)
        page.set_attribute(ArchiBIM::DICT, 'drawing_key', key)
        page.set_attribute(ArchiBIM::DICT, 'drawing_kind', name)
        page
      end

      def plan(model, key, label, elevation, center, span, cut: true, up: Y_AXIS)
        z = elevation.to_f
        plane = if cut
                  section_plane(model, key,
                                Geom::Point3d.new(center.x, center.y, (z + 1200).mm),
                                Geom::Vector3d.new(0, 0, -1))
                end
        eye = Geom::Point3d.new(center.x, center.y, (z + span).mm)
        target = Geom::Point3d.new(center.x, center.y, z.mm)
        save_view(model, key, label, eye, target, up, plane)
      end

      def make_set
        model = Sketchup.active_model
        levels = ArchiBIM.levels.sort_by { |level| level.fetch('elevation').to_f }
        raise 'At least one ArchiBIM level is needed' if levels.empty?
        bounds = model.bounds
        raise 'Model is empty. Add BIM elements before generating drawings.' if bounds.empty?
        c = bounds.center
        span = [bounds.width.to_mm, bounds.height.to_mm, bounds.depth.to_mm, 6000.0].max * 2.0
        first = levels.first
        second = levels[1]
        prev_page = model.pages.selected_page
        names = []
        model.start_operation('ArchiBIM: Generate drawing scenes', true)
        begin
          page = plan(model, 'ground', "#{first['name']} Floor Plan",
                      first['elevation'], c, span)
          page.set_attribute(ArchiBIM::DICT, 'level_id', first['id'])
          names << page.name
          if second
            page = plan(model, 'first', "#{second['name']} Floor Plan",
                        second['elevation'], c, span)
            page.set_attribute(ArchiBIM::DICT, 'level_id', second['id'])
            names << page.name
          end
          page = plan(model, 'roof', 'Roof Plan', bounds.max.z.to_mm + 100.0, c, span, cut: false)
          names << page.name

          west, east = bounds.min.x, bounds.max.x
          south, north = bounds.min.y, bounds.max.y
          # Elevations are orthographic, and intentionally do not use section cuts.
          {
            'north' => [Geom::Point3d.new(c.x, north + span.mm, c.z), Z_AXIS],
            'south' => [Geom::Point3d.new(c.x, south - span.mm, c.z), Z_AXIS],
            'east'  => [Geom::Point3d.new(east + span.mm, c.y, c.z), Z_AXIS],
            'west'  => [Geom::Point3d.new(west - span.mm, c.y, c.z), Z_AXIS]
          }.each do |key, (eye, up)|
            page = save_view(model, key, "#{key.capitalize} Elevation", eye, c, up)
            names << page.name
          end

          # Perpendicular mid-building sections, intended for user adjustment.
          a_cut = section_plane(model, 'section_a', c, Geom::Vector3d.new(0, -1, 0))
          b_cut = section_plane(model, 'section_b', c, Geom::Vector3d.new(-1, 0, 0))
          page = save_view(model, 'section_a', 'Section A-A (central provisional cut)',
                           Geom::Point3d.new(c.x, north + span.mm, c.z), c, Z_AXIS, a_cut)
          names << page.name
          page = save_view(model, 'section_b', 'Section B-B (central provisional cut)',
                           Geom::Point3d.new(east + span.mm, c.y, c.z), c, Z_AXIS, b_cut)
          names << page.name

          # RCP preview looks up at the underside; ceiling objects/light fixtures
          # are NOT inferred or fabricated if they do not exist in the model.
          [['rcp_ground', first], ['rcp_first', second]].each do |key, level|
            next unless level
            z = level['elevation'].to_f + 1200.0
            plane = section_plane(model, key,
                                  Geom::Point3d.new(c.x, c.y, z.mm),
                                  Geom::Vector3d.new(0, 0, 1))
            page = save_view(model, key, "#{level['name']} Reflected Ceiling PREVIEW",
                             Geom::Point3d.new(c.x, c.y, (z - 10).mm),
                             Geom::Point3d.new(c.x, c.y, (z + span).mm),
                             Y_AXIS, plane)
            page.set_attribute(ArchiBIM::DICT, 'level_id', level['id'])
            names << page.name
          end
          model.entities.active_section_plane = nil
          model.rendering_options['DisplaySectionCuts'] = false
          model.pages.selected_page = prev_page if prev_page
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        ArchiBIM::Diagnostics.log('drawing_set_generated',
                                  { count: names.size, scene_names: names })
        names
      end

      # AI snapshot is explicitly exported by the user. No listener, network
      # service, filesystem watcher or remote AI connection is started.
      def ai_snapshot
        model = Sketchup.active_model
        result = {
          'schema_version' => '1.0',
          'application' => 'ArchiBIM',
          'version' => ArchiBIM::VERSION,
          'units' => 'mm',
          'model_title' => model.title.to_s,
          'levels' => ArchiBIM.levels,
          'elements' => ArchiBIM.elements.map do |group, data|
            data.merge('world_origin_mm' => [
              group.transformation.origin.x.to_mm,
              group.transformation.origin.y.to_mm,
              group.transformation.origin.z.to_mm
            ])
          end,
          'drawings' => model.pages.filter_map do |page|
            code = page.get_attribute(ArchiBIM::DICT, 'drawing_key')
            { 'key' => code, 'name' => page.name,
              'level_id' => page.get_attribute(ArchiBIM::DICT, 'level_id') } if code
          end,
          'warnings' => ['Scene views are not automatically annotated CAD drawings.',
                         'RCP is preliminary until native ceiling objects exist.']
        }
        result
      end

      def export_ai_snapshot
        path = UI.savepanel('Save AI-readable ArchiBIM snapshot', nil, 'ArchiBIM_AI.json')
        return unless path
        path += '.json' unless path.downcase.end_with?('.json')
        File.write(path, JSON.pretty_generate(ai_snapshot))
        ArchiBIM::Diagnostics.log('ai_snapshot_export', { elements: ArchiBIM.elements.size })
        UI.messagebox("Saved read-only model snapshot to:\n#{path}\nNo data was transmitted.")
      end
    end
  end
end
