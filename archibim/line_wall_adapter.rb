# frozen_string_literal: true
# Native SketchUp line -> parametric ArchiBIM wall adapter.
# Select loose edges (or a bounded face) in the current editing context.
require 'set'
require_relative 'line_wall_import'

module SSDigitalLab
  module ArchiBIM
    # Only follow native edges belonging to the CURRENT editing context.
    # Do not traverse into groups/components, where transforms and ownership differ.
    def selected_line_network
      model = Sketchup.active_model
      available = Set.new(model.active_entities.grep(Sketchup::Edge).select(&:valid?))
      selection = model.selection
      seeds = selection.grep(Sketchup::Edge)
      selection.grep(Sketchup::Face).each { |face| seeds.concat(face.edges) }
      seeds = seeds.select { |edge| edge.valid? && available.include?(edge) }.uniq
      raise 'Select a native SketchUp line (or its bounded face) before converting. Open any source group for editing first.' if seeds.empty?
      result = Set.new(seeds)
      queue = seeds.dup
      until queue.empty?
        edge = queue.shift
        edge.vertices.each do |vertex|
          vertex.edges.each do |other|
            next unless other.valid? && available.include?(other)
            next if result.include?(other)
            result << other
            queue << other
            raise "The connected network exceeds #{LineWallImport::MAX_EDGES} edges. Select a smaller drawing area." if result.size > LineWallImport::MAX_EDGES
          end
        end
      end
      result.to_a
    end

    def convert_selected_lines_to_walls
      model = Sketchup.active_model
      edges = selected_line_network
      context_transform = model.edit_transform
      raw = edges.map do |edge|
        a = edge.start.position.transform(context_transform)
        b = edge.end.position.transform(context_transform)
        { id: edge.persistent_id, a: [a.x.to_mm, a.y.to_mm, a.z.to_mm],
          b: [b.x.to_mm, b.y.to_mm, b.z.to_mm] }
      end
      plan = LineWallImport.build(raw)
      level = current_level
      z_delta = (plan[:plane_z_mm] - level['elevation'].to_f).abs
      if z_delta > LineWallImport::PLANE_TOLERANCE
        raise "Lines are at Z=#{plan[:plane_z_mm].round(1)} mm, but the active level #{level['name']} is Z=#{level['elevation']} mm. Set the correct active level or move the source lines onto its plane."
      end

      existing = wall_inventory.values.select { |w| w['level_id'] == level['id'] }
      plan[:segments].each do |segment|
        duplicate = existing.any? do |w|
          (LineWallImport.distance(w['start'], segment[:a]) <= 1.0 &&
           LineWallImport.distance(w['end'], segment[:b]) <= 1.0) ||
            (LineWallImport.distance(w['start'], segment[:b]) <= 1.0 &&
             LineWallImport.distance(w['end'], segment[:a]) <= 1.0)
        end
        raise 'One or more lines already match ArchiBIM walls on this level; remove duplicate source paths or work on a copy.' if duplicate
      end

      # The validation above is read-only. All model edits use one Undo step.
      created = []
      graph_added = []
      model.start_operation('ArchiBIM: Convert connected lines to walls', true)
      begin
        plan[:segments].each_with_index do |segment, index|
          a = segment.fetch(:a); b = segment.fetch(:b)
          p1 = Geom::Point3d.new(a[0].mm, a[1].mm, level['elevation'].to_f.mm)
          p2 = Geom::Point3d.new(b[0].mm, b[1].mm, level['elevation'].to_f.mm)
          data, transform = entity_payload('wall', p1, p2)
          data['name'] = "Line Wall #{index + 1}"
          data['source_native_edge_ids'] = segment[:sources]
          data['line_import'] = true
          validate_data(data)
          created << create_element(data, transform)
        end
        # This command explicitly requests association, even if the normal
        # auto-join preference was disabled. Existing unlinked tombstones remain.
        graph = stored_wall_graph
        graph_added = graph.detect(wall_inventory)
        save_wall_graph(graph)
        rebuild_wall_junctions(reconcile: false)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      model.selection.clear
      model.selection.add(created.first) unless created.empty?
      report = { source_edges: edges.size, walls: created.size,
                 linked_joints: graph_added.size, junctions: plan[:counts],
                 unresolved_multiway: plan[:junctions].select { |j| j[:type] == 'multiway' },
                 source_geometry_preserved: true, plane_z_mm: plan[:plane_z_mm].round(2) }
      Diagnostics.log('convert_connected_lines_to_walls', report)
      warning = plan[:counts]['multiway'] > 0 ? " #{plan[:counts]['multiway']} ambiguous multiway junction(s) need manual review." : ''
      graph_feedback("Created #{created.size} BIM walls from #{edges.size} connected lines; #{graph_added.size} linked junction(s).#{warning}", report)
      refresh_panel
      report
    end
  end
end
