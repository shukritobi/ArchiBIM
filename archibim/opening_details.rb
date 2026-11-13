# frozen_string_literal: true
# Parametric glazing and hardware primitives shared by wall and hosted openings.
module SSDigitalLab
  module ArchiBIM
    module Geometry
      def self.hidden_symbol_tag(name, dashed: false)
        model = Sketchup.active_model
        # Migrate legacy 2D drawing tags only once. This hides symbols that
        # were created before this feature without overriding visibility the
        # user explicitly changes after the migration.
        key = 'symbols_3d_default_hidden_v086'
        unless model.get_attribute(ArchiBIM::DICT, key, false)
          model.layers.each do |layer|
            next unless layer.name.start_with?('AB | 2D |')
            layer.visible = false
          end
          model.set_attribute(ArchiBIM::DICT, key, true)
        end
        existed = model.layers[name]
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

      # Build separate clipped glass panes inside the frame. Unlike the legacy
      # wall_mesh(glass), this cannot pass through the perimeter, door voids or
      # vertical mullions. Each exposed panel remains separately identifiable.
      def self.glass_wall_mesh(entities, wall, model)
        length = wall.fetch('length').to_f
        height = wall.fetch('height').to_f
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        cy = (low + high) / 2.0
        glass = wall.fetch('glass_wall_glass_thickness', 3.0).to_f
        frame = wall.fetch('glass_wall_frame_width', 30.0).to_f
        mullion_width = GlazingLayout.transom_width(wall)
        framed = wall.fetch('glass_wall_frame', true)
        panes = GlazingLayout.pane_rectangles(wall)
        panes.each_with_index do |(x0,x1,z0,z1),index|
          pane = entities.add_group
          pane.name = "Clipped fixed glass pane #{index+1}"
          pane.material = material(model, 'glass')
          box(pane.entities,x0,x1,cy-glass/2.0,cy+glass/2.0,z0,z1)
        end
        if framed
          raise ArgumentError, 'Glass-wall perimeter frame is wider than the available wall' if length <= frame*2 || height <= frame*2
          [
            ['Head rail',frame,length-frame,height-frame,height],
            ['Left jamb',0,frame,0,height],
            ['Right jamb',length-frame,length,0,height]
          ].each do |label,x0,x1,z0,z1|
            next if label == 'Left jamb' && GlazingLayout.mitered_frame?(wall,'start')
            next if label == 'Right jamb' && GlazingLayout.mitered_frame?(wall,'end')
            member = entities.add_group
            member.name = "Glazing frame | #{label}"
            member.material = material(model,'frame')
            box(member.entities,x0,x1,low,high,z0,z1)
          end
          # The sill is broken at every ground-level door opening. No aluminium
          # member can run under a frameless glass door.
          GlazingLayout.segments_outside_openings(length,wall.fetch('openings',[]),0.0,frame).each do |x0,x1|
            next unless x1-x0 > 0.01
            member = entities.add_group
            member.name='Glazing bottom rail (door voids excluded)'
            member.material=material(model,'frame')
            box(member.entities,x0,x1,low,high,0,frame)
          end
        end
        GlazingLayout.active_vertical_stations(length,wall.fetch('openings',[]),
          wall.fetch('glass_wall_mullions_count',0)).each_with_index do |x,index|
          member = entities.add_group
          member.name = "Vertical mullion #{index+1}"
          member.material = material(model,'frame')
          box(member.entities,x-mullion_width/2.0,x+mullion_width/2.0,
              low,high,framed ? frame : 0.0,framed ? height-frame : height)
        end
        GlazingLayout.transom_stations(wall).each do |z|
          member=entities.add_group
          member.name="Automatically aligned transom at #{z.round}mm (door head)"
          member.material=material(model,'frame')
          # Sitting immediately above door head, not bisecting the glazed door.
          z1=[z+mullion_width,height-(framed ? frame : 0.0)].min
          next unless z1>z
          box(member.entities,framed ? frame : 0.0,
              length-(framed ? frame : 0.0),low,high,z,z1)
        end
        if wall.fetch('glass_wall_partition_above',false)
          partition_h=wall.fetch('glass_wall_partition_height',900.0).to_f
          partition_t=wall.fetch('glass_wall_partition_thickness',100.0).to_f
          if partition_h>0
            partition=entities.add_group
            partition.name='Partition Above | solid box-up'
            partition.material=material(model,'wall')
            box(partition.entities,0,length,cy-partition_t/2.0,cy+partition_t/2.0,
                height,height+partition_h)
            soften_coplanar_wall_edges(partition.entities)
          end
        end
        %w[start end].each do |at|
          next unless GlazingLayout.mitered_frame?(wall,at)
          profile = entities.add_group
          profile.name = "Hollow corner profile | #{at}"
          profile.material = material(model,'frame')
          outside = wall['thickness'].to_f
          skin = wall.fetch('glass_wall_corner_skin',3.0).to_f
          centre_x = at == 'start' ? 0.0 : length
          x0,x1 = centre_x-outside/2.0,centre_x+outside/2.0
          y0,y1 = cy-outside/2.0,cy+outside/2.0
          # Hollow aluminium profile modelled as four sides rather than a solid.
          [[x0,x0+skin,y0,y1],[x1-skin,x1,y0,y1],
           [x0+skin,x1-skin,y0,y0+skin],
           [x0+skin,x1-skin,y1-skin,y1]].each do |xa,xb,ya,yb|
            box(profile.entities,xa,xb,ya,yb,0,height)
          end
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

      # Conceptual PT10/PT20 style fittings, guided by Dormakaba/Hafele
      # catalogues. 164 x 51 mm covers, 5mm each exposed face, Ø15 pivot,
      # and floor bearing rising only 3mm. Actual selected fitting governs.
      def self.pivot_hinges(child, opening, y, bottom, top, model)
        left = opening.fetch('hinge','left') != 'right'
        x = opening['offset'].to_f
        w = opening['width'].to_f
        start_x = left ? x+5.0 : x+w-169.0
        end_x = start_x+164.0
        hinge_x = left ? start_x+55.0 : end_x-55.0
        glass = [opening.fetch('glass_thickness',10.0).to_f,8.0].max
        fittings = child.entities.add_group
        fittings.name='Top and bottom pivot patch hardware'
        fittings.material=material(model,'frame')
        [[bottom+3.0,bottom+54.0,'Bottom patch'],
         [top-54.0,top-3.0,'Top patch']].each do |z0,z1,label|
          [-1,1].each do |side|
            plate=fittings.entities.add_group
            plate.name="#{label} | 5mm face cover"
            y0,y1 = [y+side*glass/2.0,y+side*(glass/2.0+5.0)].minmax
            box(plate.entities,start_x,end_x,y0,y1,z0,z1)
          end
        end
        # 3mm tall flush pivot bearing at floor (not a chunky floor patch).
        bearing=fittings.entities.add_group
        bearing.name='Flush floor pivot bearing | 3mm projection'
        box(bearing.entities,hinge_x-25.0,hinge_x+25.0,y-25.0,y+25.0,bottom,bottom+3.0)
        [bottom+3.0,top-15.0].each_with_index do |z,index|
          pivot=fittings.entities.add_group
          pivot.name=index.zero? ? 'Lower cylindrical pivot Ø15' : 'Upper cylindrical pivot Ø15'
          ring=pivot.entities.add_circle(point(hinge_x,y,z),Z_AXIS,7.5.mm,24)
          face=pivot.entities.add_face(ring)
          if face
            face.reverse! if face.normal.dot(Z_AXIS)<0
            face.pushpull(12.mm)
          end
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
