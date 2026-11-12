# frozen_string_literal: true
# Preliminary 2D CAD geometry derived from existing ArchiBIM solid meshes.
# DXF units: millimetres. Visible projected faces are not occlusion solved.
require 'fileutils'

module SSDigitalLab
  module ArchiBIM
    module DxfExport
      extend self
      LAYERS = {
        'AB_2D_CUT' => ['CONTINUOUS', 7],
        'AB_2D_VISIBLE' => ['CONTINUOUS', 7],
        'AB_2D_OPENINGS' => ['DASHED', 3],
        'AB_2D_ROOF' => ['CONTINUOUS', 5],
        'AB_2D_DRAINAGE' => ['CONTINUOUS', 4],
        'AB_2D_STRUCTURE' => ['CONTINUOUS', 2]
      }.freeze
      EPS = 0.05

      def coordinates(point)
        [point.x.to_mm, point.y.to_mm, point.z.to_mm]
      end

      # Recursively collect face polygons, honoring nested group/component axes.
      def faces(entities, tr, &block)
        entities.each do |entity|
          next unless entity.valid?
          if entity.is_a?(Sketchup::Face)
            polygon = entity.vertices.map { |vertex| coordinates(vertex.position.transform(tr)) }
            yield polygon if polygon.length >= 3
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            next if entity.name.to_s.start_with?('2D ')
            nested = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            faces(nested, tr * entity.transformation, &block)
          end
        end
      end

      def project(p, view)
        case view
        when 'north' then [-p[0], p[2]]
        when 'south' then [p[0], p[2]]
        when 'east' then [p[1], p[2]]
        when 'west' then [-p[1], p[2]]
        when 'section_a' then [-p[0], p[2]]
        when 'section_b' then [p[1], p[2]]
        else [p[0], p[1]]
        end
      end

      def intersect_polygon(vertices, axis, station)
        cuts = []
        vertices.each_with_index do |a, i|
          b = vertices[(i + 1) % vertices.size]
          da, db = a[axis] - station, b[axis] - station
          if da.abs < EPS && db.abs < EPS
            cuts << [a, b]
          elsif da.abs < EPS
            cuts << [a]
          elsif (da < -EPS && db > EPS) || (da > EPS && db < -EPS)
            t = -da.to_f / (db - da).to_f
            cuts << [a.each_index.map { |j| a[j] + (b[j] - a[j]) * t }]
          end
        end
        return cuts.select { |segment| segment.size == 2 } if cuts.any? { |x| x.size == 2 }
        points = cuts.flatten(1).uniq { |a| a.map { |n| (n / EPS).round } }
        return [] if points.length < 2
        # Valid convex planar faces cross the section in exactly two unique points.
        [[points[0], points[1]]]
      end

      def collect(model, key, levels)
        bounds = model.bounds
        c = coordinates(bounds.center)
        floor = key == 'ground' || key == 'rcp_ground' ? levels[0] : levels[1]
        floor ||= levels[0]
        plane = case key
                when 'ground', 'first'
                  [2, floor['elevation'].to_f + 1200.0]
                when 'section_a' then [1, c[1]]
                when 'section_b' then [0, c[0]]
                when 'rcp_ground', 'rcp_first'
                  [2, floor['elevation'].to_f + 1200.0]
                end
        segments = []
        ArchiBIM.elements.each do |group, data|
          next if data['kind'] == 'room'
          case key
          when 'ground', 'first'
            next if data['level_id'] != floor['id'] || data['kind'] == 'roof'
          when 'roof'
            next unless data['kind'] == 'roof'
          when 'rcp_ground', 'rcp_first'
            # Without ceiling families, show only cut geometry as a preview.
            next unless %w[slab beam column wall].include?(data['kind'])
          end
          layer = key == 'roof' ? 'AB_2D_ROOF' : (plane ? 'AB_2D_CUT' : 'AB_2D_VISIBLE')
          faces(group.entities, group.transformation) do |poly|
            world_segments = if plane
                               intersect_polygon(poly, *plane)
                             else
                               poly.each_with_index.map { |p, i| [p, poly[(i+1) % poly.size]] }
                             end
            world_segments.each do |a, b|
              pa = project(a, key)
              pb = project(b, key)
              next if Math.hypot(pb[0]-pa[0], pb[1]-pa[1]) < EPS
              segments << [layer, pa, pb]
            end
          end
          if %w[ground first].include?(key) && data['kind'] == 'wall'
            add_opening_symbols(segments, group, data)
          end
        end
        # Keep coincident face edges from exploding CAD line-count.
        uniq = {}
        segments.each do |layer, a, b|
          vertices = [a, b].map { |v| v.map { |n| (n * 10).round } }.sort
          uniq[[layer, vertices]] ||= [layer, a, b]
        end
        uniq.values
      end

      def add_opening_symbols(segments, wall, data)
        length = data['length'].to_f
        return if length <= 0
        data.fetch('openings', []).each do |opening|
          x = opening['offset'].to_f
          w = opening['width'].to_f
          next unless x >= 0 && w > 0
          tr = wall.transformation
          if opening['kind'] == 'door'
            left_hinge = opening.fetch('hinge', 'left') != 'right'
            hinge = left_hinge ? x : x+w
            a0 = left_hinge ? 0.0 : Math::PI
            sign = (left_hinge ? 1.0 : -1.0) * (opening.fetch('swing', 'in') == 'out' ? -1.0 : 1.0)
            arc = (0..16).map do |i|
              ang = a0 + sign * Math::PI / 2.0 * i / 16.0
              p = Geom::Point3d.new((hinge+w*Math.cos(ang)).mm, (w*Math.sin(ang)).mm, 0)
              coordinates(p.transform(tr))
            end
            arc.each_cons(2) do |p1,p2|
              segments << ['AB_2D_OPENINGS', project(p1,'ground'), project(p2,'ground')]
            end
          elsif opening['kind'] == 'window' || opening['kind'] == 'sliding_door'
            a = coordinates(Geom::Point3d.new(x.mm, 0, 0).transform(tr))
            b = coordinates(Geom::Point3d.new((x+w).mm, 0, 0).transform(tr))
            segments << ['AB_2D_OPENINGS', project(a,'ground'), project(b,'ground')]
          end
        end
      end

      def dxf_text(segments)
        lines = []
        put = ->(*xs) { xs.each { |x| lines << x.to_s } }
        put.call(0,'SECTION',2,'HEADER',9,'$ACADVER',1,'AC1015',
                 9,'$INSUNITS',70,4,9,'$MEASUREMENT',70,1,0,'ENDSEC',
                 0,'SECTION',2,'TABLES',0,'TABLE',2,'LTYPE',70,2)
        put.call(0,'LTYPE',2,'CONTINUOUS',70,0,3,'Solid',72,65,73,0,40,0.0)
        put.call(0,'LTYPE',2,'DASHED',70,0,3,'Dashed',72,65,73,2,40,12.0,49,8.0,74,0,49,-4.0,74,0)
        put.call(0,'ENDTAB',0,'TABLE',2,'LAYER',70,LAYERS.size)
        LAYERS.each do |name, (line_type, color)|
          put.call(0,'LAYER',2,name,70,0,62,color,6,line_type)
        end
        put.call(0,'ENDTAB',0,'ENDSEC',0,'SECTION',2,'ENTITIES')
        segments.each do |layer, a, b|
          next unless [*a, *b].all? { |v| v.is_a?(Numeric) && v.finite? }
          put.call(0,'LINE',8,layer,10,format('%.4f',a[0]),20,format('%.4f',a[1]),30,'0',
                   11,format('%.4f',b[0]),21,format('%.4f',b[1]),31,'0')
        end
        put.call(0,'ENDSEC',0,'EOF')
        lines.join("\n") + "\n"
      end

      def export_set
        model = Sketchup.active_model
        levels = ArchiBIM.levels.sort_by { |l| l['elevation'].to_f }
        raise 'Add at least one ArchiBIM level' if levels.empty?
        raise 'Add model elements before exporting drawings' if ArchiBIM.elements.empty?
        save = UI.savepanel('Choose DXF set folder name', nil, 'ArchiBIM_CAD_Drawings')
        return unless save
        folder = save.sub(/\.dxf\z/i, '')
        FileUtils.mkdir_p(folder)
        keys = %w[ground roof north south east west section_a section_b rcp_ground]
        keys.insert(1, 'first') if levels.length >= 2
        keys << 'rcp_first' if levels.length >= 2
        files = []
        keys.each do |key|
          code = Documentation::DRAWING_CODES.fetch(key)
          name = key.tr('_', '-')
          filepath = File.join(folder, "#{code}_#{name}.dxf")
          File.write(filepath, dxf_text(collect(model, key, levels)), mode: 'w')
          files << filepath
        end
        ArchiBIM::Diagnostics.log('dxf_set_export', { files: files.size, folder: folder })
        UI.messagebox("Exported #{files.length} preliminary CAD line drawings to:\n#{folder}\nVerify CAD visibility, hatch, dimension and section details before use.")
        files
      end
    end
  end
end
