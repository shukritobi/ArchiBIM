# frozen_string_literal: true
# Parametric glazing and hardware primitives shared by wall and hosted openings.
module SSDigitalLab
  module ArchiBIM
    module Geometry
      def self.hidden_symbol_tag(name, dashed: false)
        existed = Sketchup.active_model.layers[name]
        tag = ArchiBIM.ensure_tag(name, dashed: dashed)
        tag.visible = false unless existed
        tag
      end

      # Only soften seams between coplanar panels from the wall boolean grid.
      # Never soften the 90-degree jamb/sill/head reveal or external corners.
      def self.soften_coplanar_wall_edges(entities)
        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.size == 2
          a, b = edge.faces
          next unless a.normal.dot(b.normal) > 0.9999
          next unless a.plane[0] * b.vertices.first.position.x +
                      a.plane[1] * b.vertices.first.position.y +
                      a.plane[2] * b.vertices.first.position.z +
                      a.plane[3] < 0.001 &&
                      a.plane[0] * b.vertices.first.position.x +
                      a.plane[1] * b.vertices.first.position.y +
                      a.plane[2] * b.vertices.first.position.z +
                      a.plane[3] > -0.001
          edge.soft = true
          edge.smooth = false
        end
      end

      def self.glass_wall_mesh(entities, wall, model)
        length = wall['length'].to_f
        height = wall['height'].to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        center = (low + high) / 2.0
        glass = wall.fetch('glass_wall_glass_thickness', 3.0).to_f
        frame = wall.fetch('glass_wall_frame_width', 30.0).to_f
        glazing = entities.add_group
        glazing.name = 'Architectural glazing'
        glazing.material = material(model, 'glass')
        wall_mesh(glazing.entities,
                  wall.merge('thickness' => glass, 'alignment' => 'center', 'joins' => {}))
        glazing.transformation = Geom::Transformation.translation([0, center.mm, 0])
        soften_coplanar_wall_edges(glazing.entities)
        return unless wall.fetch('glass_wall_frame', true)
        raise ArgumentError, 'Wall too short for glazing perimeter' if length <= frame * 2
        raise ArgumentError, 'Wall too low for glazing perimeter' if height <= frame * 2
        members = [
          ['Left jamb', 0.0, frame, 0.0, height],
          ['Right jamb', length - frame, length, 0.0, height],
          ['Head', frame, length - frame, height - frame, height],
          ['Bottom rail', frame, length - frame, 0.0, frame]
        ]
        members.each do |label, x0, x1, z0, z1|
          member = entities.add_group
          member.name = "Glazing frame | #{label}"
          member.material = material(model, 'frame')
          box(member.entities, x0, x1, low, high, z0, z1)
        end
      end

      # A cylinder's axis is the local Y direction, facing the room.
      def self.handle_cylinder(entities, x, y, z, radius, depth, side)
        normal = Geom::Vector3d.new(0, side, 0)
        ring = entities.add_circle(point(x, y, z), normal, radius.mm, 16)
        face = entities.add_face(ring)
        return unless face
        face.reverse! if face.normal.dot(normal) < 0
        face.pushpull(depth.mm)
      end

      def self.door_hardware(child, opening, model, y, lower_z, upper_z, style)
        width = opening['width'].to_f
        x = opening['offset'].to_f
        hinge_left = opening.fetch('hinge', 'left') != 'right'
        handle_x = hinge_left ? x + width - 95.0 : x + 95.0
        handle_z = [[lower_z + 1050.0, upper_z - 140.0].min, lower_z + 220.0].max
        handle_style = opening.fetch('handle', 'lever')
        if style == 'glass_frameless'
          handle_style = 'pull' if handle_style == 'lever'
        end
        fittings = child.entities.add_group
        fittings.name = "Door hardware | #{handle_style}"
        fittings.material = material(model, 'frame')
        [-1, 1].each do |side|
          fy = y + side * (style == 'solid' ? 26.0 : 8.0)
          if handle_style == 'round_knob'
            handle_cylinder(fittings.entities, handle_x, fy, handle_z, 28.0, 15.0, side)
            handle_cylinder(fittings.entities, handle_x, fy + side * 15.0,
                            handle_z, 22.0, 28.0, side)
          elsif handle_style == 'pull'
            # Long vertical rectangular pull like the supplied frosted-glass reference.
            pull = fittings.entities.add_group
            pull.name = 'Vertical pull 500 mm'
            box(pull.entities, handle_x - 12, handle_x + 12,
                fy + (side.positive? ? 35 : -55), fy + (side.positive? ? 55 : -35),
                [lower_z + 250, handle_z - 250].max,
                [upper_z - 120, handle_z + 250].min)
            [handle_z - 165, handle_z + 165].each do |z|
              post = fittings.entities.add_group
              y0, y1 = [fy, fy + side * 45].minmax
              box(post.entities, handle_x - 9, handle_x + 9, y0, y1, z - 9, z + 9)
            end
          else
            handle_cylinder(fittings.entities, handle_x, fy, handle_z, 25.0, 9.0, side)
            lever = fittings.entities.add_group
            lever.name = 'Lever grip'
            travel = hinge_left ? -90.0 : 90.0
            from_x, to_x = [handle_x, handle_x + travel].minmax
            y0, y1 = [fy + side * 9.0, fy + side * 26.0].minmax
            box(lever.entities, from_x, to_x, y0, y1, handle_z - 8.0, handle_z + 8.0)
          end
        end
      end

      def self.pivot_hinges(child, opening, y, bottom, top, model)
        x = opening['offset'].to_f
        w = opening['width'].to_f
        at = opening.fetch('hinge', 'left') == 'right' ? x + w - 48.0 : x + 48.0
        hinges = child.entities.add_group
        hinges.name = 'Floor and ceiling glass pivot hinges'
        hinges.material = material(model, 'frame')
        [bottom, top - 38.0].each do |z|
          clamp = hinges.entities.add_group
          box(clamp.entities, at - 45, at + 45, y - 25, y + 25, z, z + 38)
        end
      end

      def self.transom_assembly(child, opening, model, y0, y1, outer)
        return nil unless opening.fetch('transom', false)
        x = opening['offset'].to_f
        z = opening['sill'].to_f
        w = opening['width'].to_f
        h = opening['height'].to_f
        transom = opening.fetch('transom_height', 450.0).to_f
        bar = [[outer, 20.0].max, 60.0].min
        split = z + h - transom
        if opening.fetch('style','solid') == 'glass_frameless'
          y0 = (y0 + y1) / 2.0 - 25
          y1 = y0 + 50
        end
        rail = child.entities.add_group
        rail.name = 'Transom horizontal framing'
        rail.material = material(model,'frame')
        box(rail.entities,x+outer,x+w-outer,y0,y1,split-bar/2,split+bar/2)
        pane = child.entities.add_group
        pane.name = 'Upper fixed transom glass'
        pane.material = material(model,'glass')
        glass = opening.fetch('glass_thickness',3.0).to_f
        cy = (y0+y1)/2.0
        box(pane.entities,x+outer+5,x+w-outer-5,cy-glass/2,cy+glass/2,
            split+bar/2+5,z+h-outer-5)
        split - bar / 2.0
      end
    end
  end
end
