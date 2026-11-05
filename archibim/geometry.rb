# frozen_string_literal: true
require_relative 'core'

module SSDigitalLab
  module ArchiBIM
    module Geometry
      MATERIALS = {
        'wall' => ['ArchiBIM | Wall plaster', [226, 228, 225], 1.0],
        'slab' => ['ArchiBIM | Concrete slab', [165, 169, 174], 1.0],
        'footing' => ['ArchiBIM | Footing concrete', [128, 130, 137], 1.0],
        'roof' => ['ArchiBIM | Roof finish', [81, 95, 114], 1.0],
        'column' => ['ArchiBIM | Concrete column', [144, 150, 157], 1.0],
        'beam' => ['ArchiBIM | Concrete beam', [160, 165, 170], 1.0],
        'stair' => ['ArchiBIM | Stairs', [172, 177, 183], 1.0],
        'room' => ['ArchiBIM | Room zone', [111, 198, 183], 0.26],
        'door' => ['ArchiBIM | Timber door', [175, 127, 87], 1.0],
        'frame' => ['ArchiBIM | Aluminium frame', [62, 72, 85], 1.0],
        'glass' => ['ArchiBIM | Glazing', [114, 191, 214], 0.32]
      }.freeze
      IFC = { 'wall' => 'IfcWall', 'slab' => 'IfcSlab', 'column' => 'IfcColumn',
              'beam' => 'IfcBeam', 'stair' => 'IfcStair', 'room' => 'IfcSpace',
              'roof' => 'IfcRoof', 'footing' => 'IfcFooting',
              'door' => 'IfcDoor', 'window' => 'IfcWindow' }.freeze

      def self.point(x, y, z)
        Geom::Point3d.new(x.mm, y.mm, z.mm)
      end

      def self.material(model, kind)
        name, rgb, alpha = MATERIALS.fetch(kind)
        existing = model.materials[name]
        return existing if existing
        mat = model.materials.add(name)
        mat.color = Sketchup::Color.new(*rgb)
        mat.alpha = alpha
        mat
      end

      def self.box(entities, x0, x1, y0, y1, z0, z1, mat = nil)
        raise ArgumentError, 'Box needs positive dimensions' unless x1 > x0 && y1 > y0 && z1 > z0
        face = entities.add_face(point(x0, y0, z0), point(x1, y0, z0),
                                 point(x1, y1, z0), point(x0, y1, z0))
        raise 'Cannot create box face' unless face
        face.reverse! if face.normal.dot(Z_AXIS) < 0
        face.pushpull((z1 - z0).mm)
        if mat
          # Material is carried by the encapsulating group to preserve cutout materials.
          entities.grep(Sketchup::Face).each do |f|
            f.material = mat
            f.back_material = mat
          end
        end
      end

      def self.quad(entities, coords, normal)
        face = entities.add_face(coords.map { |c| point(*c) })
        return unless face && face.valid?
        expected = Geom::Vector3d.new(*normal)
        face.reverse! if face.normal.dot(expected) < 0
        face
      end

      # Wall face positions follow the placement reference line. At clean corners
      # the end sections are mitred, at tees the free wall receives a butt cut.
      # Geometry remains a proper closed cutout mesh with local parametric data.
      def self.wall_mesh(entities, data)
        length = data['length'].to_f
        height = data['height'].to_f
        low, high = Junctions.side_offsets(data['thickness'], data['alignment'])
        xs, zs, cells = Core.wall_cells(length, height, data.fetch('openings', []))
        join = data.fetch('joins', {})
        a = join.fetch('start', [0.0, 0.0]); b = join.fetch('end', [0.0, 0.0])
        last = xs.size - 2
        cells.each do |(i, j), (x0, x1, z0, z1)|
          low0 = x0 + (i.zero? ? a[0].to_f : 0.0)
          high0 = x0 + (i.zero? ? a[1].to_f : 0.0)
          low1 = x1 + (i == last ? b[0].to_f : 0.0)
          high1 = x1 + (i == last ? b[1].to_f : 0.0)
          quad(entities, [[low0, low, z0], [low1, low, z0],
                          [low1, low, z1], [low0, low, z1]], [0, -1, 0])
          quad(entities, [[high0, high, z0], [high0, high, z1],
                          [high1, high, z1], [high1, high, z0]], [0, 1, 0])
          unless cells.key?([i - 1, j])
            quad(entities, [[low0, low, z0], [low0, low, z1],
                            [high0, high, z1], [high0, high, z0]], [-1, 0, 0])
          end
          unless cells.key?([i + 1, j])
            quad(entities, [[low1, low, z0], [high1, high, z0],
                            [high1, high, z1], [low1, low, z1]], [1, 0, 0])
          end
          unless cells.key?([i, j - 1])
            quad(entities, [[low0, low, z0], [high0, high, z0],
                            [high1, high, z0], [low1, low, z0]], [0, 0, -1])
          end
          unless cells.key?([i, j + 1])
            quad(entities, [[low0, low, z1], [low1, low, z1],
                            [high1, high, z1], [high0, high, z1]], [0, 0, 1])
          end
        end
      end

      def self.symbol_group(child, wall, opening, model, orientation)
        level = ArchiBIM.levels.find { |l| l['id'] == wall['level_id'] }
        label = level ? level['name'] : 'Unknown'
        prefix = orientation == 'plan' ? 'AB | 2D | Plan' : 'AB | 2D | Elevation'
        name = "#{prefix} | #{opening['kind'].capitalize} Swing | #{label}"
        tag = ArchiBIM.ensure_tag(name, dashed: true)
        group = child.entities.add_group
        group.name = "2D #{orientation.capitalize} Swing"
        group.layer = tag
        [group, tag]
      end

      def self.symbol_edge(group, tag, a, b)
        e = group.entities.add_line(point(*a), point(*b))
        e.layer = tag if e
      end

      def self.symbol_polyline(group, tag, points)
        points.each_cons(2) { |a, b| symbol_edge(group, tag, a, b) }
      end

      # Render the plan leaf and dashed swing arc independently of the
      # elevation marker. Elevation marker uses a wedge, not a single slash:
      # the point identifies the hinge or handle edge, configurable per opening.
      def self.opening_symbols(child, wall, opening, model)
        x = opening['offset'].to_f
        width = opening['width'].to_f
        sill = opening['sill'].to_f
        height = opening['height'].to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        hinge_left = opening.fetch('hinge', 'left') != 'right'
        swing_sign = opening.fetch('swing', 'in') == 'out' ? -1.0 : 1.0
        label = (ArchiBIM.levels.find { |l| l['id'] == wall['level_id'] } || {})['name'] || 'Unknown'
        if opening['kind'] == 'door'
          plan, dashed = symbol_group(child, wall, opening, model, 'plan')
          hinge = hinge_left ? x : x + width
          y = (low + high) / 2.0
          z = 20.0
          a0 = hinge_left ? 0.0 : Math::PI
          a1 = a0 + (hinge_left ? 1.0 : -1.0) * swing_sign * Math::PI / 2.0
          arc = (0..32).map do |n|
            a = a0 + (a1 - a0) * n / 32.0
            [hinge + width * Math.cos(a), y + width * Math.sin(a), z]
          end
          symbol_polyline(plan, dashed, arc)
          leaf_tag = ArchiBIM.ensure_tag("AB | 2D | Plan | Door Leaf | #{label}")
          leaf = child.entities.add_group
          leaf.name = 'Door plan leaf (open)'
          leaf.layer = leaf_tag
          symbol_edge(leaf, leaf_tag, [hinge, y, z], arc.last)
        else
          plan_tag = ArchiBIM.ensure_tag("AB | 2D | Plan | Window | #{label}")
          plan = child.entities.add_group
          plan.name = 'Window plan centreline'
          plan.layer = plan_tag
          panes = opening.fetch('panels', 2).to_i
          mid_y = (low + high) / 2.0
          symbol_edge(plan, plan_tag, [x, mid_y, sill + 25], [x + width, mid_y, sill + 25])
          (1...panes).each do |index|
            px = x + width * index / panes
            symbol_edge(plan, plan_tag, [px, low, sill + 25], [px, high, sill + 25])
          end
        end
        elev, dashed = symbol_group(child, wall, opening, model, 'elevation')
        # A separate tag controls the line style and hiding in 3D renders.
        y = high + 16.0
        count = opening['kind'] == 'window' ? opening.fetch('panels', 2).to_i : 1
        count = [[count, 1].max, 4].min
        (0...count).each do |index|
          left = x + width * index / count
          right = x + width * (index + 1) / count
          hinge_on_left = if opening['kind'] == 'window' && count == 2
                            index == 0
                          else
                            hinge_left
                          end
          marker = opening.fetch('marker', 'hinge')
          point_on_left = marker == 'hinge' ? hinge_on_left : !hinge_on_left
          point_x = point_on_left ? left : right
          far_x = point_on_left ? right : left
          # Two equal-height diagonals meeting at the hinge/handle midpoint.
          symbol_edge(elev, dashed, [far_x, y, sill], [point_x, y, sill + height / 2.0])
          symbol_edge(elev, dashed, [point_x, y, sill + height / 2.0],
                      [far_x, y, sill + height])
        end
      end

      def self.opening_assembly(wall, opening, model)
        kind = opening.fetch('kind')
        x = opening['offset'].to_f
        z = opening['sill'].to_f
        width = opening['width'].to_f
        height = opening['height'].to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        child = wall.fetch('_entities').add_group
        child.name = "#{kind.capitalize} #{opening['id'].to_s[0, 8]}"
        child.set_attribute('SSDigitalLab_ArchiBIM', 'hosted', true)
        child.set_attribute('SSDigitalLab_ArchiBIM', 'ifc', IFC.fetch(kind))
        child.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(opening))
        outer = [opening.fetch('outer_frame', kind == 'window' ? 50.0 : 45.0).to_f,
                 width / 6.0, height / 6.0].min
        sash = [opening.fetch('inner_frame', 30.0).to_f, width / 12.0, height / 12.0].min
        glass = opening.fetch('glass_thickness', 3.0).to_f
        mid_y = (low + high) / 2.0
        frame_depth = [high - low, 65.0].min
        y0, y1 = mid_y - frame_depth / 2.0, mid_y + frame_depth / 2.0
        frame_group = child.entities.add_group
        frame_group.name = 'Outer frame'
        frame_group.material = material(model, 'frame')
        box(frame_group.entities, x, x + outer, y0, y1, z, z + height)
        box(frame_group.entities, x + width - outer, x + width, y0, y1, z, z + height)
        box(frame_group.entities, x + outer, x + width - outer, y0, y1,
            z + height - outer, z + height)
        box(frame_group.entities, x + outer, x + width - outer, y0, y1,
            z, z + outer) if kind == 'window'
        inner_l, inner_r = x + outer, x + width - outer
        inner_b, inner_t = z + (kind == 'window' ? outer : 8.0), z + height - outer
        if kind == 'door'
          if inner_r > inner_l && inner_t > inner_b
            panel = child.entities.add_group
            panel.name = 'Door leaf'
            box(panel.entities, inner_l, inner_r, mid_y - 20.0, mid_y + 20.0, inner_b, inner_t)
            panel.material = material(model, 'door')
          end
        else
          count = [[opening.fetch('panels', 2).to_i, 1].max, 4].min
          pane_width = (inner_r - inner_l) / count
          (0...count).each do |index|
            xl = inner_l + index * pane_width
            xr = inner_l + (index + 1) * pane_width
            next unless xr - xl > 2.0 * sash + 5.0 && inner_t - inner_b > 2.0 * sash + 5.0
            pane = child.entities.add_group
            pane.name = "Casement #{index + 1} of #{count}"
            sash_group = pane.entities.add_group
            sash_group.name = 'Inner sash frame'
            sash_group.material = material(model, 'frame')
            [[xl, xl + sash, inner_b, inner_t],
             [xr - sash, xr, inner_b, inner_t],
             [xl + sash, xr - sash, inner_b, inner_b + sash],
             [xl + sash, xr - sash, inner_t - sash, inner_t]].each do |a, b, c, d|
              box(sash_group.entities, a, b, mid_y - 18, mid_y + 18, c, d)
            end
            glass_group = pane.entities.add_group
            glass_group.name = "#{glass} mm glazing"
            box(glass_group.entities, xl + sash, xr - sash,
                mid_y - glass / 2.0, mid_y + glass / 2.0,
                inner_b + sash, inner_t - sash)
            glass_group.material = material(model, 'glass')
          end
        end
        opening_symbols(child, wall, opening, model)
        classify(child, IFC.fetch(kind))
        child
      end

      def self.stair(entities, data)
        n = data['steps'].to_i
        run = data['run'].to_f
        rise = data['rise'].to_f
        width = data['width'].to_f
        step_rise = rise / n
        style = data.fetch('style', 'straight')
        if style == 'u'
          first = (n / 2.0).ceil
          second = n - first
          raise ArgumentError, 'U stair requires at least four risers' if second < 2
          landing = data.fetch('landing', width).to_f
          gap = data.fetch('gap', 150.0).to_f
          flight = run - landing
          raise ArgumentError, 'Stair run must exceed landing length' if flight < 200.0
          tread = flight / [first, second].max
          # First flight ascends +X; return flight ascends -X after landing.
          (0...first).each do |i|
            x0 = i * tread; x1 = (i + 1) * tread
            box(entities, x0, x1, 0, width, 0, step_rise * (i + 1))
          end
          box(entities, flight, flight + landing, 0, 2.0 * width + gap,
              [step_rise * first - 150.0, 0].max, step_rise * first)
          (0...second).each do |i|
            x0 = flight - (i + 1) * tread; x1 = flight - i * tread
            box(entities, x0, x1, width + gap, 2.0 * width + gap,
                0, step_rise * (first + i + 1))
          end
        else
          tread = run / n
          (0...n).each do |i|
            box(entities, i * tread, (i + 1) * tread, 0, width,
                0, step_rise * (i + 1))
          end
        end
      end

      def self.roof_panel(entities, polygon, thickness)
        bottom = polygon.map { |p| [p[0], p[1], p[2] - thickness] }
        quad(entities, polygon, [0, 0, 1])
        quad(entities, bottom.reverse, [0, 0, -1])
        polygon.each_index do |index|
          j = (index + 1) % polygon.length
          quad(entities, [polygon[index], bottom[index], bottom[j], polygon[j]], [0, 0, 1])
        end
      end

      def self.roof(entities, data, model)
        pitch = data['pitch'].to_f * Math::PI / 180.0
        o = data['overhang'].to_f
        width = data['width'].to_f
        depth = data['depth'].to_f
        thickness = data['thickness'].to_f
        base = data['eave_offset'].to_f
        x0, x1, y0, y1 = -o, width + o, -o, depth + o
        xm, ym = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        mode = data.fetch('roof_type', 'gable')
        if mode == 'hip'
          w, d = x1 - x0, y1 - y0
          peak = base + [w, d].min / 2.0 * Math.tan(pitch)
          if w <= d
            ya = y0 + w / 2.0; yb = y1 - w / 2.0
            planes = [
              [[x0,y0,base],[x0,y1,base],[xm,yb,peak],[xm,ya,peak]],
              [[x1,y0,base],[xm,ya,peak],[xm,yb,peak],[x1,y1,base]],
              [[x0,y0,base],[xm,ya,peak],[x1,y0,base]],
              [[x0,y1,base],[x1,y1,base],[xm,yb,peak]]]
          else
            xa = x0 + d / 2.0; xb = x1 - d / 2.0
            planes = [
              [[x0,y0,base],[xa,ym,peak],[xb,ym,peak],[x1,y0,base]],
              [[x0,y1,base],[x1,y1,base],[xb,ym,peak],[xa,ym,peak]],
              [[x0,y0,base],[x0,y1,base],[xa,ym,peak]],
              [[x1,y0,base],[xb,ym,peak],[x1,y1,base]]]
          end
          planes.each { |polygon| roof_panel(entities, polygon, thickness) }
        else
          # Gable ridge along Y; wall-side eaves at X=0 and X=width.
          ridge = base + (width / 2.0 + o) * Math.tan(pitch)
          [[ [x0,y0,base],[xm,y0,ridge],[xm,y1,ridge],[x0,y1,base] ],
           [ [xm,y0,ridge],[x1,y0,base],[x1,y1,base],[xm,y1,ridge] ]].each do |poly|
            roof_panel(entities, poly, thickness)
          end
          if data.fetch('infill', true)
            # Vertical gable closure, not a ceiling. Positioned at both wall-end
            # planes; follows ridge height and roof pitch for each regeneration.
            edge_top = base + o * Math.tan(pitch) - thickness
            ridge_under = ridge - thickness
            if ridge_under > base + 1.0
              [0.0, depth - data.fetch('infill_thickness', 150.0).to_f].each do |y|
                group = entities.add_group
                group.name = 'Gable wall infill'
                level = (ArchiBIM.levels.find { |l| l['id'] == data['level_id'] } || {})['name'] || 'Ground Floor'
                group.layer = ArchiBIM.ensure_tag("AB | Roof infill | #{level}")
                thick = data.fetch('infill_thickness', 150.0).to_f
                points = [[0,y,base],[width,y,base],[width,y,[base,edge_top].max],
                          [width/2.0,y,ridge_under],[0,y,[base,edge_top].max]]
                face = group.entities.add_face(points.map { |xyz| point(*xyz) })
                if face
                  face.pushpull(thick.mm)
                  group.material = material(model, 'wall')
                end
              end
            end
          end
        end
      end

      def self.classify(group, ifc_class)
        group.set_attribute('SSDigitalLab_ArchiBIM', 'ifc', ifc_class)
        %w[IFC\ 4 IFC\ 2x3].each do |schema|
          begin
            group.definition.add_classification(schema, ifc_class)
            return true
          rescue StandardError, TypeError
            # SketchUp only supports schemas actually loaded by the current model.
          end
        end
        false
      end

      def self.build(group, data, model)
        raise ArgumentError, 'Invalid BIM element' unless Core::ALLOWED_KINDS.include?(data['kind'])
        group.make_unique
        group.entities.clear!
        kind = data['kind']
        case kind
        when 'wall'
          wall_mesh(group.entities, data)
          wall_data = data.merge('_entities' => group.entities)
          data.fetch('openings', []).each { |o| opening_assembly(wall_data, o, model) }
        when 'slab'
          box(group.entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f,
              -data['thickness'].to_f, 0.0)
        when 'footing'
          box(group.entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f,
              -data['thickness'].to_f, 0.0)
        when 'roof'
          roof(group.entities, data, model)
        when 'column'
          w = data['width'].to_f
          h = data['depth'].to_f
          alignment = data.fetch('alignment', 'center')
          xmin = alignment == 'left' ? 0.0 : (alignment == 'right' ? -w : -w / 2.0)
          box(group.entities, xmin, xmin + w, -h / 2.0, h / 2.0,
              0.0, data['height'].to_f)
        when 'beam'
          low, high = Junctions.side_offsets(data['width'], data.fetch('alignment', 'center'))
          base = data['offset'].to_f
          box(group.entities, 0.0, data['length'].to_f, low, high,
              base, base + data['depth'].to_f)
        when 'stair'
          stair(group.entities, data)
        when 'room'
          box(group.entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f, 5.0, 8.0)
          group.entities.add_text(data.fetch('name', 'Room'),
                                  point(150.0, 150.0, 12.0))
        end
        group.material = material(model, kind)
        group.name = data.fetch('name', kind.capitalize)
        group.set_attribute('SSDigitalLab_ArchiBIM', 'kind', kind)
        group.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(data))
        classify(group, IFC.fetch(kind))
        group
      end
    end
  end
end
