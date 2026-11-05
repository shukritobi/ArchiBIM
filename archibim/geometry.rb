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

      def self.wall_mesh(entities, data)
        length = data['length'].to_f
        height = data['height'].to_f
        thickness = data['thickness'].to_f
        xs, zs, cells = Core.wall_cells(length, height, data.fetch('openings', []))
        cells.each do |(i, j), (x0, x1, z0, z1)|
          quad(entities, [[x0, 0, z0], [x1, 0, z0], [x1, 0, z1], [x0, 0, z1]], [0, -1, 0])
          quad(entities, [[x0, thickness, z0], [x0, thickness, z1],
                          [x1, thickness, z1], [x1, thickness, z0]], [0, 1, 0])
          if !cells.key?([i - 1, j])
            quad(entities, [[x0, 0, z0], [x0, 0, z1], [x0, thickness, z1],
                            [x0, thickness, z0]], [-1, 0, 0])
          end
          if !cells.key?([i + 1, j])
            quad(entities, [[x1, 0, z0], [x1, thickness, z0],
                            [x1, thickness, z1], [x1, 0, z1]], [1, 0, 0])
          end
          if !cells.key?([i, j - 1])
            quad(entities, [[x0, 0, z0], [x0, thickness, z0],
                            [x1, thickness, z0], [x1, 0, z0]], [0, 0, -1])
          end
          if !cells.key?([i, j + 1])
            quad(entities, [[x0, 0, z1], [x1, 0, z1],
                            [x1, thickness, z1], [x0, thickness, z1]], [0, 0, 1])
          end
        end
      end

      def self.opening_assembly(wall, opening, model)
        kind = opening.fetch('kind')
        x = opening['offset'].to_f
        z = opening['sill'].to_f
        width = opening['width'].to_f
        height = opening['height'].to_f
        t = wall['thickness'].to_f
        frame = [45.0, width / 7.0, height / 7.0].min
        child = wall.fetch('_entities').add_group
        child.name = "#{kind.capitalize} #{opening['id'].to_s[0, 8]}"
        child.set_attribute('SSDigitalLab_ArchiBIM', 'hosted', true)
        child.set_attribute('SSDigitalLab_ArchiBIM', 'ifc', IFC.fetch(kind))
        child.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(opening))
        frame_mat = material(model, 'frame')
        # Frame on inside face, with jambs and header. No sill across floor-height doors.
        y0 = (t - 65.0) / 2.0
        y1 = (t + 65.0) / 2.0
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
            mid = t / 2.0
            box(panel.entities, inner_left, inner_right, mid - 4.0, mid + 4.0,
                inner_bottom, inner_top)
            panel.material = material(model, 'glass')
          else
            mid = t / 2.0
            box(panel.entities, inner_left, inner_right, mid - 20.0, mid + 20.0,
                inner_bottom, inner_top)
            panel.material = material(model, 'door')
          end
        end
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
