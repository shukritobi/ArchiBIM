# frozen_string_literal: true
# Read-only inventory for SketchUp iPad Scan-to-Design (RoomPlan and Canvas).
# No entity is edited, hidden, moved, re-tagged or deleted.
require 'json'
require 'time'

module SSDigitalLab
  module ArchiBIM
    module ScanAudit
      extend self
      MAX_CONTAINERS = 350
      MAX_SAMPLE_PER_CONTAINER = 1500
      MAX_DEPTH = 12
      INCH_TO_MM = 25.4

      # Conservative heuristics. Results are candidates, never asserted BIM elements.
      # Dimensions are world-aligned bounding-box spans, not certified measurements.
      def infer(labels, dimensions_mm, planes = {})
        label = labels.join(' ').downcase.tr('_-', '  ')
        kind = case label
               when /\b(?:walls?|partitions?)\b/ then 'wall'
               when /\b(?:floors?|slabs?)\b/ then 'floor'
               when /\bceilings?\b/ then 'ceiling'
               when /\b(?:cabinets?|cupboards?|wardrobes?|joinery|pantries|counters?)\b/ then 'cabinet'
               when /\b(?:doors?|doorways?|openings?)\b/ then 'opening'
               when /\bwindows?\b/ then 'window'
               else nil
               end
        return { kind: kind, evidence: 'name_or_tag', confidence: 'needs_verification' } if kind

        dims = Array(dimensions_mm).map(&:to_f)
        return { kind: 'unknown', evidence: 'insufficient_geometry', confidence: 'unknown' } unless dims.length == 3
        xy = dims[0, 2].sort
        z = dims[2]
        horizontal = planes.fetch('horizontal_area_m2', 0.0).to_f
        vertical = planes.fetch('vertical_area_m2', 0.0).to_f
        if z <= 200 && xy[0] >= 800 && xy[1] >= 800 && horizontal > vertical * 3
          { kind: 'floor_or_ceiling', evidence: 'horizontal_surface', confidence: 'needs_verification' }
        elsif xy[0] <= 350 && xy[1] >= 800 && z >= 1800 && vertical > horizontal * 2
          { kind: 'wall', evidence: 'vertical_surface', confidence: 'needs_verification' }
        else
          { kind: 'unknown', evidence: 'ambiguous_geometry', confidence: 'unknown' }
        end
      end

      def bounds_mm(bounds, parent_transform)
        return [0.0, 0.0, 0.0] if bounds.empty?
        points = (0...8).map { |i| bounds.corner(i).transform(parent_transform) }
        axes = [points.map(&:x), points.map(&:y), points.map(&:z)]
        axes.map { |a| ((a.max - a.min).to_f * INCH_TO_MM).round(2) }
      end

      def plane_sample(face, world_transform)
        vertices = face.outer_loop.vertices
        return nil if vertices.length < 3
        a, b, c = vertices.first(3).map { |v| v.position.transform(world_transform) }
        n = (b - a).cross(c - a)
        return nil if n.length < 1.0e-10
        n.normalize!
        area_m2 = face.area(world_transform).to_f * (INCH_TO_MM / 1000.0)**2
        return nil unless area_m2.finite? && area_m2 > 0
        if n.z.abs >= 0.95
          [:horizontal, area_m2]
        elsif n.z.abs <= 0.2
          [:vertical, area_m2]
        else
          [:sloping, area_m2]
        end
      rescue StandardError
        nil
      end

      def summarize_children(entities, transform, tag_counts)
        counts = { 'faces_sampled' => 0, 'edges_sampled' => 0,
                   'nested_containers' => 0, 'sample_truncated' => false }
        area = { 'horizontal_area_m2' => 0.0, 'vertical_area_m2' => 0.0,
                 'sloping_area_m2' => 0.0 }
        visited = 0
        local_tags = Hash.new(0)
        entities.each do |child|
          next unless child.valid?
          visited += 1
          if visited > MAX_SAMPLE_PER_CONTAINER
            counts['sample_truncated'] = true
            break
          end
          tag = child.layer&.name.to_s
          unless tag.empty?
            tag_counts[tag] += 1
            local_tags[tag] += 1
          end
          if child.is_a?(Sketchup::Face)
            counts['faces_sampled'] += 1
            sample = plane_sample(child, transform)
            area["#{sample[0]}_area_m2"] += sample[1] if sample
          elsif child.is_a?(Sketchup::Edge)
            counts['edges_sampled'] += 1
          elsif child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
            counts['nested_containers'] += 1
          end
        end
        area.transform_values! { |v| v.round(4) }
        counts.merge(area).merge('sampled_tags' => local_tags.sort.to_h)
      end

      def report(model)
        selected = model.selection.to_a
        scope = selected.empty? ? 'all_root_containers' : 'selected_entities'
        sources = selected.empty? ? model.entities : selected
        tags = Hash.new(0)
        candidates = []
        warnings = []
        visited_count = 0
        # Iterate root without model.entities.to_a: large Canvas scans can be huge.
        stack = []
        sources.each do |entity|
          next unless entity.valid?
          if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            stack << [entity, Geom::Transformation.new, 0, [], []]
          end
        end
        root_samples = summarize_children(model.entities, Geom::Transformation.new, tags) if selected.empty?
        until stack.empty?
          break if visited_count >= MAX_CONTAINERS
          entity, parent_transform, depth, path, ancestors = stack.pop
          next unless entity.valid?
          visited_count += 1
          tag = entity.layer&.name.to_s
          tags[tag] += 1 unless tag.empty?
          component = entity.is_a?(Sketchup::ComponentInstance)
          definition = entity.definition
          name = entity.name.to_s
          name = definition.name.to_s if name.empty?
          name = '(unnamed)' if name.empty?
          transform = parent_transform * entity.transformation
          dimensions = bounds_mm(entity.bounds, parent_transform)
          child_stats = summarize_children(definition.entities, transform, tags)
          prediction = infer([name, definition.name.to_s, tag] + child_stats['sampled_tags'].keys, dimensions, child_stats)
          candidates << {
            'persistent_id' => entity.persistent_id,
            'path' => (path + [name]).join(' / ')[0, 500],
            'name' => name[0, 120], 'tag' => tag,
            'type' => component ? 'component_instance' : 'group',
            'depth' => depth, 'dimensions_mm_world_aabb' => dimensions,
            'sample' => child_stats, 'candidate' => prediction
          }
          if depth >= MAX_DEPTH
            warnings << 'Maximum nesting depth reached; deeper objects omitted.'
            next
          end
          definition_id = definition.object_id
          if ancestors.include?(definition_id)
            warnings << 'Recursive component definition encountered; skipped.'
            next
          end
          next_ancestors = ancestors + [definition_id]
          definition.entities.each do |child|
            if child.valid? && (child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance))
              stack << [child, transform, depth + 1, path + [name], next_ancestors]
            end
          end
        end
        warnings << "Stopped at #{MAX_CONTAINERS} nested groups/components; narrower selection recommended." unless stack.empty?
        warnings << 'Only sampled geometry is measured, and occlusions/mesh triangulation may prevent classification.'
        warnings << 'Tags and object names are clues, not verified semantic classes.'
        {
          'schema' => 'archibim.scan_audit.v1',
          'generated_at_utc' => Time.now.utc.iso8601,
          'sketchup_version' => Sketchup.version,
          'source_file' => File.basename(model.path.to_s),
          'scope' => scope,
          'selected_entities' => selected.length,
          'root_sample' => root_samples,
          'containers_inspected' => visited_count,
          'sampled_tag_occurrences' => tags.sort.to_h,
          'tag_definitions' => model.layers.map do |layer|
            { 'name' => layer.name, 'visible' => layer.visible?,
              'folder' => (layer.respond_to?(:folder) ? layer.folder&.name : nil) }
          end.sort_by { |tag| tag['name'] },
          'candidates' => candidates,
          'warnings' => warnings.uniq,
          'model_modified' => false
        }
      end

      def export(model = Sketchup.active_model)
        path = UI.savepanel('Export ArchiBIM iPad scan audit', nil, 'ArchiBIM_Scan_Audit.json')
        return nil unless path
        data = report(model)
        File.open(path, 'w:UTF-8') { |f| f.write(JSON.pretty_generate(data)) }
        data['exported_to'] = path
        data
      end
    end
  end
end
