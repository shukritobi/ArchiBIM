# frozen_string_literal: true
# Safe, explicit wall-end connection repair. Never guesses across large gaps.
module SSDigitalLab
  module ArchiBIM
    module WallJunctionRepair
      extend self

      def selected_wall_ids
        Sketchup.active_model.selection.filter_map do |entity|
          data = ArchiBIM.data_for(entity)
          data['id'] if data && data['kind'] == 'wall'
        end.uniq
      end

      def plan(max_gap_mm: 170.0)
        ids = selected_wall_ids
        raise 'Select one or more ArchiBIM walls first (not the scan mesh)' if ids.empty?
        inventory = ArchiBIM.wall_inventory
        graph = ArchiBIM.stored_wall_graph
        proposal = graph.repair_plan(inventory, selected_ids: ids, max_gap_mm: max_gap_mm)
        proposal['before'] = graph.audit(inventory)
        proposal['after'] = graph.audit(proposal['walls'])
        proposal
      end

      def preview(max_gap_mm: 170.0)
        proposal = plan(max_gap_mm: max_gap_mm)
        text = proposal['changes'].first(12).map do |fix|
          "#{fix['type'].upcase} | #{fix['wall_id'][0,8]} #{fix['end']} → #{fix['host_id'][0,8]} | gap #{fix['gap_mm'].round(2)}mm"
        end
        text << "... #{proposal['changes'].length - 12} more" if proposal['changes'].length > 12
        text << "#{proposal['skipped'].length} endpoint(s) not safely repairable."
        text << "Existing broken links: #{proposal['before']['broken_count']} ; projected: #{proposal['after']['broken_count']}."
        text << 'Moves only selected wall endpoints. Changes to openings and joints remain parametric and undoable.'
        text << 'A large gap (e.g. 655mm) is deliberately left for manual review.'
        UI.messagebox("ArchiBIM wall junction repair preview\n\n#{text.join("\n")}")
        proposal
      end

      def apply(max_gap_mm: 170.0, silent: false)
        proposal = plan(max_gap_mm: max_gap_mm)
        changed = proposal.fetch('changed')
        if changed.empty?
          UI.messagebox('No safe junctions to repair. Try Preview; large or ambiguous gaps are skipped.') unless silent
          return { 'repaired' => 0, 'skipped' => proposal['skipped'].size }
        end
        groups = {}
        ArchiBIM.elements.each do |group, data|
          groups[data['id']] = [group, data] if data['kind'] == 'wall'
        end
        operations = changed.map do |id|
          group, original = groups.fetch(id)
          raise 'Scaled wall; run Repair after Scale first' if Repair.changed_scale?(group.transformation)
          target = proposal.fetch('walls').fetch(id)
          updated = JSON.parse(JSON.generate(original))
          updated['length'] = target['length']
          updated['openings'] = target['openings']
          updated.delete('joins')
          ArchiBIM.validate_data(updated)
          a, b = target.fetch('start'), target.fetch('end')
          direction = Geom::Vector3d.new((b[0] - a[0]).mm, (b[1] - a[1]).mm, 0)
          direction.normalize!
          normal = Z_AXIS.cross(direction)
          z = group.transformation.origin.z
          transform = Geom::Transformation.axes(
            Geom::Point3d.new(a[0].mm, a[1].mm, z), direction, normal, Z_AXIS)
          [group, updated, transform]
        end
        model = Sketchup.active_model
        model.start_operation('ArchiBIM: Heal selected wall junctions', true)
        begin
          operations.each do |group, updated, transform|
            group.transformation = transform
            Geometry.build(group, updated, model)
          end
          graph = ArchiBIM.stored_wall_graph
          graph.detect(ArchiBIM.wall_inventory)
          graph.remove_missing(ArchiBIM.wall_inventory)
          ArchiBIM.save_wall_graph(graph)
          ArchiBIM.rebuild_wall_junctions(reconcile: false)
          actual = graph.audit(ArchiBIM.wall_inventory)
          if actual['broken_count'] > proposal['before']['broken_count']
            raise 'Repair introduced an additional broken wall connection; operation rolled back.'
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        report = { 'repaired' => proposal['changes'].size, 'walls' => changed.size,
                   'skipped' => proposal['skipped'].size, 'max_gap_mm' => proposal['max_gap_mm'],
                   'before_broken' => proposal['before']['broken_count'],
                   'after_broken' => actual['broken_count'],
                   'details' => proposal['changes'] }
        Diagnostics.log('wall_junction_heal', report)
        ArchiBIM.graph_feedback("Repaired #{report['repaired']} wall end(s) on #{changed.size} wall(s); broken graph links: #{report['after_broken']}.")
        ArchiBIM.refresh_panel
        UI.messagebox("Repaired #{report['repaired']} endpoint(s). #{report['skipped']} skipped.\nRemaining broken graph links: #{report['after_broken']}\nUndo reverses the repair.") unless silent
        report
      end
    end
  end
end
