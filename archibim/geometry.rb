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

      def self.opening_symbols(child, wall, opening, model)
        x = opening['offset'].to_f; width = opening['width'].to_f
        sill = opening['sill'].to_f; height = opening['height'].to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        hinge_left = opening.fetch('hinge', 'left') != 'right'
        swing_sign = opening.fetch('swing', 'in') == 'out' ? -1.0 : 1.0
        if opening['kind'] == 'door'
          plan, tag = symbol_group(child, wall, opening, model, 'plan')
          hinge = hinge_left ? x : x + width
          close = hinge_left ? (x + width) : x
          y = (low + high) / 2.0
          z = 35.0 # Below the +1200 mm cut plane and visible in plan.
          # Dashed ninety-degree swing arc, visible on its own Tag.
          start_angle = hinge_left ? 0.0 : Math::PI
          end_angle = start_angle + (hinge_left ? 1.0 : -1.0) * swing_sign * Math::PI / 2.0
          arc = (0..16).map do |n|
            angle = start_angle + (end_angle - start_angle) * n / 16.0
            [hinge + width * Math.cos(angle), y + width * Math.sin(angle), z]
          end
          symbol_polyline(plan, tag, arc)
          symbol_edge(plan, tag, [hinge, y, z], arc.last)
          # Closed-position plan leaf is intentionally solid on a separate Tag.
          edge_tag = ArchiBIM.ensure_tag("AB | 2D | Plan | Door Leaf | #{(ArchiBIM.levels.find { |l| l['id'] == wall['level_id'] } || {})['name']}")
          leaf = child.entities.add_group; leaf.layer = edge_tag; leaf.name = '2D Plan Door Leaf'
          symbol_edge(leaf, edge_tag, [hinge, y, z], [close, y, z])
        end
        elev, tag = symbol_group(child, wall, opening, model, 'elevation')
        y = high + 12.0
        # Elevation dashed open-indicator graphics are independent of the frame.
        if opening['kind'] == 'window'
          symbol_edge(elev, tag, [x, y, sill], [x + width / 2.0, y, sill + height / 2.0])
          symbol_edge(elev, tag, [x + width, y, sill], [x + width / 2.0, y, sill + height / 2.0])
          symbol_edge(elev, tag, [x + width / 2.0, y, sill + height / 2.0], [x + width / 2.0, y, sill + height])
        else
          symbol_edge(elev, tag, [hinge_left ? x : x + width, y, sill],
                      [hinge_left ? x + width : x, y, sill + height])
        end
        if opening['kind'] == 'window'
          # Plan projection of glazing centreline, separate from elevation swing.
          plan_tag = ArchiBIM.ensure_tag("AB | 2D | Plan | Window | #{(ArchiBIM.levels.find { |l| l['id'] == wall['level_id'] } || {})['name']}")
          plan = child.entities.add_group; plan.layer = plan_tag; plan.name = '2D Plan Window'
          symbol_edge(plan, plan_tag, [x, (low + high) / 2.0, sill],
                      [x + width, (low + high) / 2.0, sill])
        end
      end

      def self.opening_assembly(wall, opening, model)
        kind = opening.fetch('kind')
        x = opening['offset'].to_f
        z = opening['sill'].to_f
        width = opening['width'].to_f
        height = opening['height'].to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        t = high - low
        frame = [45.0, width / 7.0, height / 7.0].min
        child = wall.fetch('_entities').add_group
        child.name = "#{kind.capitalize} #{opening['id'].to_s[0, 8]}"
        child.set_attribute('SSDigitalLab_ArchiBIM', 'hosted', true)
        child.set_attribute('SSDigitalLab_ArchiBIM', 'ifc', IFC.fetch(kind))
        child.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(opening))
        frame_mat = material(model, 'frame')
        # Frame on inside face, with jambs and header. No sill across floor-height doors.
        y0 = (low + high - 65.0) / 2.0
        y1 = (low + high + 65.0) / 2.0
        frame_group = child.entities.add_group
        box(frame_group.entities, x, x + frame, y0, y1, z, z + height)
        box(frame_group.entities, x + width - frame, x + width, y0, y1, z, z + height)
        box(frame_group.entities, x + frame, x + width - frame, y0, y1,
            z + height - frame, z + height)
        if kind == 'window'
          box(frame_group.entities, x + frame, x + width - frame, y0, y1,
              z, z + frame)
        end
        frame_group.material = frame_mat
        inner_left = x + frame
        inner_right = x + width - frame
        inner_bottom = z + (kind == 'window' ? frame : 8.0)
        inner_top = z + height - frame
        if inner_right > inner_left && inner_top > inner_bottom
          panel = child.entities.add_group
          if kind == 'window'
            # Glass is inset from the frame; independent translucent material.
            mid = (low + high) / 2.0
            box(panel.entities, inner_left, inner_right, mid - 4.0, mid + 4.0,
                inner_bottom, inner_top)
            panel.material = material(model, 'glass')
          else
            mid = (low + high) / 2.0
            box(panel.entities, inner_left, inner_right, mid - 20.0, mid + 20.0,
                inner_bottom, inner_top)
            panel.material = material(model, 'door')
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
        t = run / n
        r = rise / n
        profile = [[0.0, 0.0, 0.0], [0.0, 0.0, r]]
        (1..n).each do |i|
          profile << [i * t, 0.0, i * r]
          profile << [i * t, 0.0, (i + 1) * r] if i < n
        end
        profile << [run, 0.0, 0.0]
        face = entities.add_face(profile.map { |xyz| point(*xyz) })
        raise 'Cannot generate staircase profile' unless face
        face.reverse! if face.normal.dot(Y_AXIS) < 0
        face.pushpull(width.mm)
      end

      def self.roof(entities, data)
        pitch = data['pitch'].to_f * Math::PI / 180.0
        overhang = data['overhang'].to_f
        width = data['width'].to_f
        depth = data['depth'].to_f
        thickness = data['thickness'].to_f
        base = data['eave_offset'].to_f
        eave_x0 = -overhang
        eave_x1 = width + overhang
        mid = width / 2.0
        ridge = base + (width / 2.0 + overhang) * Math.tan(pitch)
        y0 = -overhang
        y1 = depth + overhang
        [[eave_x0, mid, base, ridge], [mid, eave_x1, ridge, base]].each do |x0, x1, z0, z1|
          quad(entities, [[x0,y0,z0],[x1,y0,z1],[x1,y1,z1],[x0,y1,z0]], [0,0,1])
          quad(entities, [[x0,y0,z0-thickness],[x0,y1,z0-thickness],
                          [x1,y1,z1-thickness],[x1,y0,z1-thickness]], [0,0,-1])
          quad(entities, [[x0,y0,z0],[x0,y0,z0-thickness],
                          [x1,y0,z1-thickness],[x1,y0,z1]], [0,-1,0])
          quad(entities, [[x0,y1,z0],[x1,y1,z1],
                          [x1,y1,z1-thickness],[x0,y1,z0-thickness]], [0,1,0])
          quad(entities, [[x0,y0,z0],[x0,y1,z0],
                          [x0,y1,z0-thickness],[x0,y0,z0-thickness]], [-1,0,0])
          quad(entities, [[x1,y0,z1],[x1,y0,z1-thickness],
                          [x1,y1,z1-thickness],[x1,y1,z1]], [1,0,0])
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
          roof(group.entities, data)
        when 'column'
          box(group.entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f,
              0.0, data['height'].to_f)
        when 'beam'
          half = data['width'].to_f / 2.0
          base = data['offset'].to_f
          box(group.entities, 0.0, data['length'].to_f, -half, half,
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
