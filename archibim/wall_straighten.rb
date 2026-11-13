# frozen_string_literal: true
# Correct plan angles for selected RoomPlan wall groups or parametric BIM walls.
require_relative 'wall_angle_math'

module SSDigitalLab
  module ArchiBIM
    module WallStraighten
      extend self
      RAW_WALL_NAME = /\AWall-rp-\d+\z/i
      MAX_SCAN_EDGES = 1600
      MIN_EDGE_MM = 100.0
      HORIZONTAL_Z_TOL_MM = 2.0

      def eligible?(group)
        return false unless group.is_a?(Sketchup::Group) && group.valid?
        data = ArchiBIM.data_for(group)
        (data && data['kind'] == 'wall') || RAW_WALL_NAME.match?(group.name.to_s)
      end

      def selected_groups(model)
        available = model.active_entities.grep(Sketchup::Group)
        model.selection.grep(Sketchup::Group).select { |g| available.include?(g) && eligible?(g) }.uniq
      end

      def scan_direction(group, world)
        longest = nil
        seen = 0
        group.entities.each do |edge|
          next unless edge.is_a?(Sketchup::Edge) && edge.valid?
          seen += 1
          break if seen > MAX_SCAN_EDGES
          a = edge.start.position.transform(world)
          b = edge.end.position.transform(world)
          next if (a.z - b.z).abs.to_mm > HORIZONTAL_Z_TOL_MM
          dx, dy = b.x - a.x, b.y - a.y
          length_mm = Math.hypot(dx.to_mm, dy.to_mm)
          next if length_mm < MIN_EDGE_MM
          longest = [Math.atan2(dy, dx) * 180.0 / Math::PI, length_mm] if !longest || length_mm > longest[1]
        end
        raise 'No reliable horizontal edge in the selected scanned wall' unless longest
        longest
      end

      def describe(group, context)
        world = context * group.transformation
        data = ArchiBIM.data_for(group)
        if data
          raise 'Only BIM walls can be straightened' unless data['kind'] == 'wall'
          raise 'Scaled BIM wall; repair after Scale first' if Repair.changed_scale?(group.transformation)
          axis = world.xaxis
          angle = Math.atan2(axis.y, axis.x) * 180.0 / Math::PI
          length_mm = data['length'].to_f
          pivot = Geom::Point3d.new((length_mm / 2.0).mm, 0, (data['height'].to_f / 2.0).mm).transform(world)
          type = 'ArchiBIM wall'
        else
          raise 'Select an individual RoomPlan Wall-rp-* group' unless RAW_WALL_NAME.match?(group.name.to_s)
          angle, length_mm = scan_direction(group, world)
          pivot = group.bounds.center.transform(context)
          type = 'RoomPlan scan wall'
        end
        { group: group, name: group.name.to_s, angle: angle, length_mm: length_mm,
          pivot: pivot, type: type, id: group.persistent_id }
      end

      def set_reference
        model = Sketchup.active_model
        groups = selected_groups(model)
        raise 'Select exactly one RoomPlan or ArchiBIM wall as reference' unless groups.length == 1
        item = describe(groups.first, model.edit_transform)
        @reference = { model_id: model.object_id, angle: item[:angle],
                       id: item[:id], name: item[:name] }
        Diagnostics.log('wall_straighten_reference', @reference)
        Sketchup.status_text = "ArchiBIM reference: #{item[:name]} at #{item[:angle].round(3)}°"
        UI.messagebox("Reference stored: #{item[:name]} (#{item[:angle].round(2)}°). Select other walls and set mode to 'Relative to reference'.")
        @reference
      end

      def reference_angle(model)
        return @reference[:angle] if @reference && @reference[:model_id] == model.object_id
        raise 'Set a reference first: select one wall and click Set reference wall.'
      end

      def plan(mode: 'orthogonal', tolerance: 5.0)
        model = Sketchup.active_model
        groups = selected_groups(model)
        raise 'Select RoomPlan Wall-rp-* or ArchiBIM walls in the current editing context' if groups.empty?
        mode = mode.to_s
        step, reference = case mode
                          when 'orthogonal' then [90.0, 0.0]
                          when 'architectural' then [15.0, 0.0]
                          when 'reference' then [90.0, reference_angle(model)]
                          else raise ArgumentError, 'Unknown correction mode'
                          end
        context = model.edit_transform
        items = groups.map do |group|
          begin
            item = describe(group, context)
            solve = WallAngleMath.correction(item[:angle], step: step,
                                              tolerance: tolerance, reference: reference)
            item.merge(solve).merge(
              status: solve[:applicable] ? 'correct' : (solve[:already_aligned] ? 'aligned' : 'skip_tolerance'),
              endpoint_shift_mm: (item[:length_mm] * Math.sin(solve[:delta].abs * Math::PI / 360.0)).round(2))
          rescue StandardError => error
            { group: group, name: group.name.to_s, id: group.persistent_id,
              status: 'skip_error', error: error.message }
          end
        end
        { mode: mode, step: step, tolerance_deg: tolerance.to_f,
          reference_deg: reference, items: items, context: context }
      end

      def public_plan(mode: 'orthogonal', tolerance: 5.0)
        plan(mode: mode, tolerance: tolerance)[:items].map do |item|
          item.reject { |key, _| %i[group pivot].include?(key) }
        end
      end

      def preview(mode: 'orthogonal', tolerance: 5.0)
        items = public_plan(mode: mode, tolerance: tolerance)
        candidates = items.count { |item| item[:status] == 'correct' }
        lines = items.first(12).map do |item|
          if item[:status] == 'correct'
            "#{item[:name]}: #{item[:angle].round(2)}° => #{item[:target].round(2)}°; end shift ~#{item[:endpoint_shift_mm]}mm"
          else
            "#{item[:name]}: #{item[:status]} #{item[:error]}"
          end
        end
        lines << "... #{items.size - 12} more walls" if items.size > 12
        UI.messagebox("Wall correction preview: #{candidates}/#{items.size} eligible. No model changes.\n\n#{lines.join("\n")}")
        items
      end

      def apply(mode: 'orthogonal', tolerance: 5.0)
        model = Sketchup.active_model
        data = plan(mode: mode, tolerance: tolerance)
        changed = data[:items].select { |item| item[:status] == 'correct' }
        if changed.empty?
          UI.messagebox('Nothing to correct within the selected angle tolerance. Use Preview to inspect.')
          return { modified: 0, skipped: data[:items].size }
        end
        context = data[:context]
        bim_changed = changed.any? { |item| item[:type] == 'ArchiBIM wall' }
        if bim_changed && model.active_path && !model.active_path.empty?
          raise 'Correct ArchiBIM BIM walls at the model root; scanned groups can be edited inside their parent.'
        end
        before_broken = if bim_changed
          ArchiBIM.stored_wall_graph.audit(ArchiBIM.wall_inventory)['broken_count']
        end
        model.start_operation('ArchiBIM: Straighten selected walls', true)
        begin
          changed.each do |item|
            rotation = Geom::Transformation.rotation(item[:pivot], Z_AXIS, item[:delta] * Math::PI / 180.0)
            group = item[:group]
            group.transformation = context.inverse * rotation * context * group.transformation
          end
          if bim_changed
            ArchiBIM.rebuild_wall_junctions
            broken = ArchiBIM.stored_wall_graph.audit(ArchiBIM.wall_inventory)['broken_count']
            if broken > before_broken
              raise "Rotation would break #{broken - before_broken} stored BIM connection(s). No changes made; try a smaller tolerance."
            end
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        report = { modified: changed.size, skipped: data[:items].size - changed.size,
                   mode: data[:mode], tolerance_deg: data[:tolerance_deg],
                   details: changed.map { |item|
                     { id: item[:id], name: item[:name], type: item[:type],
                       from_deg: item[:angle].round(4), to_deg: item[:target].round(4),
                       correction_deg: item[:delta].round(4),
                       endpoint_shift_mm: item[:endpoint_shift_mm] } } }
        Diagnostics.log('wall_straighten_apply', report)
        Sketchup.status_text = "ArchiBIM: straightened #{changed.size} wall(s) about their midpoint"
        model.active_view.invalidate
        ArchiBIM.refresh_panel
        UI.messagebox("Straightened #{changed.size} wall(s) in one Undo step. #{report[:skipped]} skipped. Scan wall joints may need review. Original mesh faces and tags remain unchanged.")
        report
      end
    end
  end
end
