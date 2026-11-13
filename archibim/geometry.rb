# frozen_string_literal: true
require_relative 'core'
require_relative 'stair_math'

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
              'door' => 'IfcDoor', 'window' => 'IfcWindow',
              'sliding_door' => 'IfcDoor' }.freeze

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
        # Acute/angled wall joins can legitimately collapse one boundary face
        # to zero area. SketchUp raises "Duplicate points in array" if passed
        # coincident polygon vertices; skip only those degenerate faces.
        duplicate = coords.combination(2).any? do |a,b|
          Math.sqrt((a[0]-b[0])**2+(a[1]-b[1])**2+(a[2]-b[2])**2) < 0.0001
        end
        return nil if duplicate
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
        tag = hidden_symbol_tag(name, dashed: true)
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

      # The elevation marker uses the exact glass opening, including the same
      # minimum-frame clamps as the 3D casement geometry. This prevents symbols
      # projecting outside the glazing when smaller windows are drawn.
      def self.window_glass_bays(opening)
        x = opening['offset'].to_f
        z = opening['sill'].to_f
        width = opening['width'].to_f
        height = opening['height'].to_f
        outer = [opening.fetch('outer_frame', 50.0).to_f, width / 6.0, height / 6.0].min
        sash = [opening.fetch('inner_frame', 30.0).to_f, width / 12.0, height / 12.0].min
        count = [[opening.fetch('panels', 2).to_i, 1].max, 20].min
        inner_left = x + outer
        cell = (width - outer * 2.0) / count
        count.times.filter_map do |index|
          left = inner_left + cell * index + sash
          right = inner_left + cell * (index + 1) - sash
          bottom = z + outer + sash
          top = z + height - outer - sash - (opening.fetch('transom', false) ? opening.fetch('transom_height',450.0).to_f : 0.0)
          [left, right, bottom, top] if right - left > 5 && top - bottom > 5
        end
      end

      def self.frame_bounds(wall, opening)
        low, high = Junctions.side_offsets(wall['thickness'], wall['alignment'])
        depth = [high - low, 65.0].min
        mount = opening.fetch('mount', 'center')
        exterior = wall.fetch('exterior_side', 'right')
        side = case mount
               when 'exterior' then exterior
               when 'interior' then exterior == 'left' ? 'right' : 'left'
               else 'center'
               end
        case side
        when 'left' then [high - depth, high]
        when 'right' then [low, low + depth]
        else
          mid = (low + high) / 2.0
          [mid - depth / 2.0, mid + depth / 2.0]
        end
      end

      # Build a slab mesh with boundary faces on each void, including holes
      # touching an outer edge. Subtraction happens in the slab local axes.
      def self.slab_mesh(entities, data)
        holes = data.fetch('cutouts', [])
        if holes.empty?
          box(entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f,
              -data['thickness'].to_f, 0.0)
          return
        end
        _xs, _ys, cells = Core.slab_cells(data['width'], data['depth'], holes)
        raise 'Stair opening covers entire slab footprint' if cells.empty?
        t = data['thickness'].to_f
        cells.each do |(i,j), (x0,x1,y0,y1)|
          quad(entities, [[x0,y0,0],[x1,y0,0],[x1,y1,0],[x0,y1,0]], [0,0,1])
          quad(entities, [[x0,y1,-t],[x1,y1,-t],[x1,y0,-t],[x0,y0,-t]], [0,0,-1])
          unless cells.key?([i-1,j])
            quad(entities, [[x0,y0,-t],[x0,y0,0],[x0,y1,0],[x0,y1,-t]], [-1,0,0])
          end
          unless cells.key?([i+1,j])
            quad(entities, [[x1,y1,-t],[x1,y1,0],[x1,y0,0],[x1,y0,-t]], [1,0,0])
          end
          unless cells.key?([i,j-1])
            quad(entities, [[x1,y0,-t],[x1,y0,0],[x0,y0,0],[x0,y0,-t]], [0,-1,0])
          end
          unless cells.key?([i,j+1])
            quad(entities, [[x0,y1,-t],[x0,y1,0],[x1,y1,0],[x1,y1,-t]], [0,1,0])
          end
        end
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
        if Core.leafless_door?(opening)
          # Passage without a frame or leaf: dashed plan reveal/soffit
          # rectangle follows actual wall reference-line face offsets.
          tag = hidden_symbol_tag("AB | 2D | Plan | Open Passage | #{label}", dashed: true)
          plan = child.entities.add_group
          plan.name = 'Open passage | dashed plan reveal'
          plan.layer = tag
          z_cut = sill + [height / 2.0, 1200.0].min
          points = [[x, low, z_cut], [x + width, low, z_cut],
                    [x + width, high, z_cut], [x, high, z_cut], [x, low, z_cut]]
          symbol_polyline(plan, tag, points)
        elsif opening['kind'] == 'sliding_door'
          plan, dashed = symbol_group(child, wall, opening, model, 'plan')
          y0,y1 = frame_bounds(wall,opening)
          count = [[opening.fetch('panels',2).to_i,2].max,4].min
          count.times do |i|
            a=x+width*i/count; b=x+width*(i+1)/count
            forward=(opening.fetch('slide_direction','left')=='left')
            cy=(y0+y1)/2.0+((i.even? == forward) ? -12.0 : 12.0)
            symbol_edge(plan,dashed,[a,cy,20],[b,cy,20])
          end
        elsif opening['kind'] == 'door'
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
          leaf_tag = hidden_symbol_tag("AB | 2D | Plan | Door Leaf | #{label}")
          leaf = child.entities.add_group
          leaf.name = 'Door plan leaf (open)'
          leaf.layer = leaf_tag
          symbol_edge(leaf, leaf_tag, [hinge, y, z], arc.last)
        else
          plan_tag = hidden_symbol_tag("AB | 2D | Plan | Window | #{label}")
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
        if Core.leafless_door?(opening)
          tag = hidden_symbol_tag("AB | 2D | Elevation | Open Passage | #{label}", dashed: true)
          elev = child.entities.add_group
          elev.name = 'Open passage | dashed elevation opening'
          elev.layer = tag
          y = high + 1.0
          symbol_polyline(elev, tag, [[x,y,sill],[x+width,y,sill],
                                      [x+width,y,sill+height],[x,y,sill+height],
                                      [x,y,sill]])
          return
        end
        elev, dashed = symbol_group(child, wall, opening, model, 'elevation')
        # Project the symbolic vee directly onto the visible glazing / door leaf.
        # Never offset the symbol in front of the outer frame or into free space.
        if opening['kind'] == 'sliding_door'
          count = [[opening.fetch('panels', 2).to_i, 2].max, 4].min
          outer = [opening.fetch('outer_frame',45.0).to_f,width/6.0,height/6.0].min
          y0,y1=frame_bounds(wall,opening)
          mid_y = (y0+y1)/2.0
          (1...count).each do |i|
            px=x+width*i/count
            symbol_edge(elev,dashed,[px,mid_y+25,sill+outer],[px,mid_y+25,sill+height-outer])
          end
        elsif opening['kind'] == 'window' && opening.fetch('operation','casement') == 'fixed'
          # Fixed windows have no hinge or opening direction wedge.
        elsif opening['kind'] == 'window'
          glass = opening.fetch('glass_thickness', 3.0).to_f
          panes = window_glass_bays(opening)
          marker = opening.fetch('marker','hinge')
          mid_y=frame_bounds(wall,opening).sum/2.0
          # Elevation symbols on BOTH faces. A far-side elevation must mirror
          # the near-side marking rather than repeating the same V direction.
          [-1.0,1.0].each do |side|
            y=mid_y+side*(glass/2.0+0.55)
            panes.each_with_index do |(left,right,min_z,max_z),index|
              if opening.fetch('hinge','left') == 'top'
                mid_x=(left+right)/2.0
                apex_z=marker=='hinge' ? max_z : min_z
                edge_z=marker=='hinge' ? min_z : max_z
                symbol_edge(elev,dashed,[left,y,edge_z],[mid_x,y,apex_z])
                symbol_edge(elev,dashed,[mid_x,y,apex_z],[right,y,edge_z])
                next
              end
              hinge_left_at=panes.length == 1 ? opening.fetch('hinge','left') != 'right' :
                (panes.length == 2 ? index.zero? : index.even?)

              # Reverse views mirror automatically: do not invert the hinge twice.
              marked_left=marker=='hinge' ? hinge_left_at : !hinge_left_at
              point_x,far_x=marked_left ? [left,right] : [right,left]
              mid_z=(min_z+max_z)/2.0
              symbol_edge(elev,dashed,[far_x,y,min_z],[point_x,y,mid_z])
              symbol_edge(elev,dashed,[point_x,y,mid_z],[far_x,y,max_z])
            end
          end
        else
          outer=opening.fetch('outer_frame',45.0).to_f
          frameless=opening.fetch('style','solid')=='glass_frameless'
          outer=5.0 if frameless
          left,right=x+outer,x+width-outer
          min_z,max_z=sill+8.0,sill+height-outer
          mid_y=frame_bounds(wall,opening).sum/2.0
          thickness=frameless ? opening.fetch('glass_thickness',10.0).to_f : 40.0
          marker=opening.fetch('marker','hinge')
          [-1.0,1.0].each do |side|
            y=mid_y+side*(thickness/2.0+0.55)
            point_left=marker=='hinge' ? hinge_left : !hinge_left

            # Reverse-facing elevation mirrors in view, not in world geometry.
            point_x,far_x=point_left ? [left,right] : [right,left]
            next unless right>left && max_z>min_z
            mid_z=(min_z+max_z)/2.0
            symbol_edge(elev,dashed,[far_x,y,min_z],[point_x,y,mid_z])
            symbol_edge(elev,dashed,[point_x,y,mid_z],[far_x,y,max_z])
          end
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
        ifc_class = Core.leafless_door?(opening) ? 'IfcOpeningElement' : IFC.fetch(kind)
        child.set_attribute('SSDigitalLab_ArchiBIM', 'ifc', ifc_class)
        child.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(opening))
        if Core.leafless_door?(opening)
          # Wall mesh is already voided by Core.wall_cells. Keep no 3D leaf,
          # jamb frame, threshold, or head profile in the passage.
          child.name = "Open passage #{opening['id'].to_s[0,8]}"
          opening_symbols(child, wall, opening, model)
          classify(child, 'IfcOpeningElement')
          return child
        end
        outer = [opening.fetch('outer_frame', kind == 'window' ? 50.0 : 45.0).to_f,
                 width / 6.0, height / 6.0].min
        sash = [opening.fetch('inner_frame', 30.0).to_f, width / 12.0, height / 12.0].min
        glass = opening.fetch('glass_thickness', 3.0).to_f
        y0, y1 = frame_bounds(wall, opening)
        mid_y = (y0 + y1) / 2.0
        # Frameless glass doors use pivot clamps instead of jambs/head frame.
        frameless = kind == 'door' && opening.fetch('style','solid') == 'glass_frameless'
        frame_group = child.entities.add_group
        frame_group.name = 'Outer frame'
        frame_group.material = material(model, 'frame')
        unless frameless
          box(frame_group.entities, x, x + outer, y0, y1, z, z + height)
          box(frame_group.entities, x + width - outer, x + width, y0, y1, z, z + height)
          box(frame_group.entities, x + outer, x + width - outer, y0, y1,
              z + height - outer, z + height)
          box(frame_group.entities, x + outer, x + width - outer, y0, y1,
              z, z + outer) if kind == 'window'
        end
        inner_l, inner_r = x + (frameless ? 5.0 : outer), x + width - (frameless ? 5.0 : outer)
        inner_b, inner_t = z + (kind == 'window' ? outer : 8.0), z + height - (frameless ? 8.0 : outer)
        transom_top = transom_assembly(child, opening, model, y0, y1, frameless ? 5.0 : outer)
        inner_t = [inner_t, transom_top].min if transom_top

        if kind == 'sliding_door'
          count = [[opening.fetch('panels', 2).to_i, 2].max, 4].min
          pane_width = (inner_r - inner_l) / count
          count.times do |index|
            xl = inner_l + index*pane_width
            xr = xl + pane_width
            next if xr-xl < 2*sash+5.0 || inner_t-inner_b < 2*sash+5.0
            track = child.entities.add_group
            track.name = "Sliding panel #{index+1} of #{count}"
            track.material = material(model, 'frame')
            # Alternate panels across two parallel sliding tracks.
            forward=(opening.fetch('slide_direction','left')=='left')
            cy = mid_y + ((index.even? == forward) ? -14.0 : 14.0)
            [[xl,xl+sash,inner_b,inner_t],[xr-sash,xr,inner_b,inner_t],
             [xl+sash,xr-sash,inner_b,inner_b+sash],
             [xl+sash,xr-sash,inner_t-sash,inner_t]].each do |a,b,c,d|
              box(track.entities,a,b,cy-10,cy+10,c,d)
            end
            glass_group = track.entities.add_group
            glass_group.name = 'Sliding glazing'
            glass_group.material = material(model, 'glass')
            box(glass_group.entities,xl+sash,xr-sash,cy-glass/2.0,cy+glass/2.0,
                inner_b+sash,inner_t-sash)
          end
          # Parallel floor/head tracks make the sliding action legible in plan.
          rail = child.entities.add_group
          rail.name='Sliding door tracks'
          rail.material=material(model,'frame')
          [-14.0,14.0].each do |shift|
            box(rail.entities,inner_l,inner_r,mid_y+shift-7,mid_y+shift+7,z,z+10)
          end
        elsif kind == 'door'
          if inner_r > inner_l && inner_t > inner_b
            style = opening.fetch('style', 'solid')
            panel = child.entities.add_group
            panel.name = style == 'solid' ? 'Door leaf' : 'Glass door leaf'
            glass = opening.fetch('glass_thickness',3.0).to_f
            thickness = style == 'solid' ? 40.0 : glass
            box(panel.entities, inner_l, inner_r,
                mid_y - thickness / 2.0, mid_y + thickness / 2.0, inner_b, inner_t)
            panel.material = material(model, style == 'solid' ? 'door' : 'glass')
            pivot_hinges(child, opening, mid_y, z, z + height, model) if frameless
            door_hardware(child, opening, model, mid_y, inner_b, inner_t, style)
          end
        else
          count = [[opening.fetch('panels', 2).to_i, 1].max, 20].min
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

      # Sweep one 2D stair flight profile through its width. The continuous
      # inclined soffit replaces the former full-height blocks/wall under each
      # tread. Riser and tread geometry are generated in the same solid.
      def self.stair_flight(entities, run, width, waist, structure)
        x0 = run.fetch('x')
        direction = run.fetch('direction')
        y0 = run.fetch('y')
        count = run.fetch('risers')
        if structure == 'open'
          tread = run.fetch('tread')
          thickness = [40.0, run.fetch('rise') / count * 0.4].min
          count.times do |i|
            a = x0 + direction * tread * i
            b = x0 + direction * tread * (i + 1)
            z = run.fetch('base') + run.fetch('rise') / count * (i + 1)
            box(entities, [a,b].min, [a,b].max, y0, y0 + width, z - thickness, z)
          end
        else
          points = StairMath.flight_profile(risers: count, going: run['going'],
                                            rise: run['rise'], waist: waist,
                                            base: run['base'])
          coords = points.map { |x,z| point(x0 + direction * x, y0, z) }
          face = entities.add_face(coords)
          raise 'Cannot generate the stair flight profile' unless face
          face.reverse! if face.normal.dot(Y_AXIS) < 0
          face.pushpull(width.mm)
        end
      end

      # Model simple cylindrical handrails and vertical balusters. These are
      # independent tagged child groups, not permanently fused to the stair slab.
      def self.tube(entities, a, b, diameter, faces = 10)
        delta = [b[0]-a[0], b[1]-a[1], b[2]-a[2]]
        length = Math.sqrt(delta.sum { |v| v*v })
        return if length < 1.0
        axis = delta.map { |v| v / length }
        reference = axis[2].abs < 0.9 ? [0,0,1] : [0,1,0]
        u = [axis[1]*reference[2]-axis[2]*reference[1],
             axis[2]*reference[0]-axis[0]*reference[2],
             axis[0]*reference[1]-axis[1]*reference[0]]
        norm = Math.sqrt(u.sum { |v| v*v })
        u.map! { |v| v / norm }
        v = [axis[1]*u[2]-axis[2]*u[1],
             axis[2]*u[0]-axis[0]*u[2],
             axis[0]*u[1]-axis[1]*u[0]]
        radius = diameter / 2.0
        ring = lambda do |center|
          (0...faces).map do |i|
            angle = Math::PI * 2 * i / faces
            (0..2).map { |j| center[j] + radius*(u[j]*Math.cos(angle)+v[j]*Math.sin(angle)) }
          end
        end
        low, high = ring.call(a), ring.call(b)
        entities.add_face(low.map { |xyz| point(*xyz) })
        entities.add_face(high.reverse.map { |xyz| point(*xyz) })
        faces.times do |i|
          j = (i + 1) % faces
          entities.add_face([low[i],low[j],high[j],high[i]].map { |xyz| point(*xyz) })
        end
      end

      def self.stair_railings(entities, data, runs, model)
        mode = data.fetch('handrail', 'both')
        return if mode == 'none'
        height = data.fetch('rail_height', 950.0).to_f
        diameter = data.fetch('rail_diameter', 40.0).to_f
        spacing = [data.fetch('post_spacing', 900.0).to_f, 200.0].max
        sr = data['rise'].to_f / data['steps'].to_i
        group = entities.add_group
        group.name = 'Stair handrails and posts'
        level = (ArchiBIM.levels.find { |l| l['id'] == data['level_id'] } || {})['name'] || 'Ground Floor'
        group.layer = ArchiBIM.ensure_tag("AB | Stair railings | #{level}")
        group.material = material(model, 'frame')
        runs.each do |run|
          sides = mode == 'both' ? %w[left right] : [mode]
          sides.each do |side|
            y = run['y'] + (side == 'right' ? data['width'].to_f : 0.0)
            start = [run['x'], y, run['base'] + sr + height]
            last = [run['x'] + run['direction'] * run['going'], y,
                    run['base'] + run['rise'] + height]
            tube(group.entities, start, last, diameter)
            posts = [(run['going'] / spacing).ceil, 1].max
            (0..posts).each do |i|
              t = i.to_f / posts
              x = run['x'] + run['direction']*run['going']*t
              bottom_z = run['base'] + [sr*(1 + (t*run['risers']).floor), run['rise']].min
              top_z = start[2] + t*(last[2]-start[2])
              tube(group.entities, [x,y,bottom_z], [x,y,top_z], [diameter*0.58,15.0].max, 8)
            end
          end
        end
      end

      def self.stair(entities, data, model)
        runs = StairMath.layout(data)
        structure = data.fetch('structure', 'waist')
        waist = data.fetch('waist', 150.0).to_f
        runs.each_with_index do |run, i|
          flight = entities.add_group
          flight.name = "Flight #{i + 1} | #{run['risers']} risers"
          stair_flight(flight.entities, run, data['width'].to_f, waist, structure)
        end
        if data.fetch('style', 'straight') == 'u'
          run = runs.first
          depth = data.fetch('landing', data['width']).to_f
          z = run['rise']
          x = run['going']
          landing = entities.add_group
          landing.name = 'Intermediate landing'
          box(landing.entities, x, x + depth, 0.0,
              2.0 * data['width'].to_f + data.fetch('gap', 150.0).to_f,
              z - waist, z)
        end
        stair_railings(entities, data, runs, model)
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

      # Conceptual steel profiles. Structural sizing and connections need review.
      def self.steel_member(parent, a, b, size, mat)
        v = Geom::Vector3d.new((b[0]-a[0]).mm, (b[1]-a[1]).mm, (b[2]-a[2]).mm)
        length = v.length.to_mm
        return if length < 1.0
        xaxis = v.normalize
        reference = xaxis.parallel?(Y_AXIS) ? X_AXIS : Y_AXIS
        zaxis = xaxis.cross(reference).normalize
        yaxis = zaxis.cross(xaxis).normalize
        g = parent.entities.add_group
        g.name = 'Conceptual SHS steel member'
        g.transformation = Geom::Transformation.axes(point(*a), xaxis, yaxis, zaxis)
        box(g.entities, 0, length, -size/2.0, size/2.0, -size/2.0, size/2.0)
        g.material = mat
      end

      # Parametric square-gutter trough along a world-aligned rectangle eave.
      # Drainage sizing/fall is deliberately NOT represented as engineered.
      def self.roof_drainage(entities, data, model, mode, x0, x1, y0, y1, xm, base)
        return unless data.fetch('gutter_enabled', false)
        width = data.fetch('gutter_width', 150.0).to_f
        depth = data.fetch('gutter_depth', 100.0).to_f
        return if width < 20 || depth < 20
        walls = case mode
                when 'gable', 'saltbox' then [[:along_y, x0], [:along_y, x1]]
                when 'butterfly' then [[:along_y, xm]]
                when 'awning' then [[:along_y, x1]]
                when 'shed', 'flat' then [[:along_y, x0]]
                else [[:along_y, x0], [:along_y, x1], [:along_x, y0], [:along_x, y1]]
                end
        finish = material(model, 'frame')
        lvl = (ArchiBIM.levels.find { |l| l['id'] == data['level_id'] } || {})['name'] || 'Roof'
        tag = ArchiBIM.ensure_tag("AB | Roof drainage | #{lvl}")
        walls.each do |direction, position|
          child = entities.add_group
          child.name = 'Gutter | preliminary box profile'
          child.layer = tag
          t = [3.0, width/8.0, depth/8.0].min
          ztop = base + (mode == 'butterfly' ? 0 : 0)
          if direction == :along_y
            # Lower edge at the eave, trough open to sky.
            box(child.entities, position-width/2, position+width/2, y0, y1,
                ztop-depth, ztop-depth+t)
            box(child.entities, position-width/2, position-width/2+t, y0, y1,
                ztop-depth+t, ztop)
            box(child.entities, position+width/2-t, position+width/2, y0, y1,
                ztop-depth+t, ztop)
            outlet = [position, y1-width/2, ztop-depth]
          else
            box(child.entities, x0, x1, position-width/2, position+width/2,
                ztop-depth, ztop-depth+t)
            box(child.entities, x0, x1, position-width/2, position-width/2+t,
                ztop-depth+t, ztop)
            box(child.entities, x0, x1, position+width/2-t, position+width/2,
                ztop-depth+t, ztop)
            outlet = [x1-width/2, position, ztop-depth]
          end
          child.material = finish
          next unless data.fetch('downpipe_enabled', false)
          dia = data.fetch('downpipe_diameter', 75.0).to_f
          drop = data.fetch('downpipe_drop', 3000.0).to_f
          next unless dia > 0 && drop > 0
          pipe = entities.add_group
          pipe.name = 'Downpipe | conceptual circular profile'
          pipe.layer = tag
          circle = pipe.entities.add_circle(point(*outlet), Z_AXIS, (dia/2.0).mm, 16)
          face = pipe.entities.add_face(circle)
          face.pushpull(-drop.mm) if face
          pipe.material = finish
        end
      end

      def self.roof_steelwork(entities, data, model, mode, width, depth, overhang, base, ridge)
        finish = material(model, 'frame')
        lvl = (ArchiBIM.levels.find { |l| l['id'] == data['level_id'] } || {})['name'] || 'Roof'
        tag = ArchiBIM.ensure_tag("AB | Steel roof structure | #{lvl}")
        member = data.fetch('truss_member', 75.0).to_f
        return unless member > 0
        if mode == 'awning'
          child = entities.add_group
          child.name = 'Steel awning framing | preliminary'
          child.layer = tag
          height0 = base + width * Math.tan(data['pitch'].to_f * Math::PI / 180)
          [0.0, depth].each do |y|
            steel_member(child, [0, y, height0-100], [width, y, base-100], member, finish)
            if data.fetch('awning_posts', true)
              steel_member(child, [width, y, 0], [width, y, base-100], member, finish)
            end
          end
          steel_member(child, [width, 0, base-100], [width, depth, base-100], member, finish)
        elsif data.fetch('truss_enabled', false) && %w[gable saltbox].include?(mode)
          spacing = [data.fetch('truss_spacing', 1200.0).to_f, 100.0].max
          count = [[(depth/spacing).ceil, 1].max, 100].min
          (0..count).each do |i|
            y = depth * i / count.to_f
            truss = entities.add_group
            truss.name = "Roof truss #{i + 1} (#{data.fetch('truss_style', 'king_post')})"
            truss.layer = tag
            peakx = mode == 'saltbox' ? width*0.35 : width/2.0
            apex = [peakx, y, ridge-data['thickness'].to_f-100]
            left = [0, y, base-100]
            right = [width, y, base-100]
            steel_member(truss, left, right, member, finish)
            steel_member(truss, left, apex, member, finish)
            steel_member(truss, apex, right, member, finish)
            if data.fetch('truss_style', 'king_post') == 'fink'
              steel_member(truss, apex, [width*0.25,y,base-100], member, finish)
              steel_member(truss, apex, [width*0.75,y,base-100], member, finish)
            else
              steel_member(truss, apex, [peakx,y,base-100], member, finish)
            end
          end
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
        if %w[shed awning flat butterfly saltbox].include?(mode)
          rise = Math.tan(pitch)
          ridge_height = base
          if mode == 'butterfly'
            ridge_height = base + (width / 2.0 + o) * rise
            polys = [
              [[x0,y0,ridge_height],[xm,y0,base],[xm,y1,base],[x0,y1,ridge_height]],
              [[xm,y0,base],[x1,y0,ridge_height],[x1,y1,ridge_height],[xm,y1,base]]
            ]
          elsif mode == 'saltbox'
            pivot = x0 + (x1-x0)*0.35
            ridge_height = base + (pivot-x0)*rise
            polys = [
              [[x0,y0,base],[pivot,y0,ridge_height],[pivot,y1,ridge_height],[x0,y1,base]],
              [[pivot,y0,ridge_height],[x1,y0,base],[x1,y1,base],[pivot,y1,ridge_height]]
            ]
          else
            roof_rise = mode == 'flat' ? [rise, Math.tan(3.0*Math::PI/180.0)].min : rise
            ridge_height = base + (x1-x0)*roof_rise
            polys = if mode == 'awning'
                      [[[x0,y0,ridge_height],[x1,y0,base],[x1,y1,base],[x0,y1,ridge_height]]]
                    else
                      [[[x0,y0,base],[x1,y0,ridge_height],[x1,y1,ridge_height],[x0,y1,base]]]
                    end
          end
          polys.each { |poly| roof_panel(entities, poly, thickness) }
          roof_steelwork(entities, data, model, mode, width, depth, o, base, ridge_height)
          roof_drainage(entities, data, model, mode, x0, x1, y0, y1, xm, base)
          return
        end
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
        ridge_height = if mode == 'gable'
                         base + (width / 2.0 + o)*Math.tan(pitch)
                       else
                         base + [x1-x0, y1-y0].min / 2.0 * Math.tan(pitch)
                       end
        roof_steelwork(entities, data, model, mode, width, depth, o, base, ridge_height)
        roof_drainage(entities, data, model, mode, x0, x1, y0, y1, xm, base)
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
          if data.fetch('wall_type','brick') == 'glass'
            glass_wall_mesh(group.entities, data, model)
          else
            wall_mesh(group.entities, data)
            soften_coplanar_wall_edges(group.entities)
          end
          wall_data = data.merge('_entities' => group.entities)
          data.fetch('openings', []).each { |o| opening_assembly(wall_data, o, model) }
        when 'slab'
          slab_mesh(group.entities, data)
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
          stair(group.entities, data, model)
        when 'room'
          box(group.entities, 0.0, data['width'].to_f, 0.0, data['depth'].to_f, 5.0, 8.0)
          group.entities.add_text(data.fetch('name', 'Room'),
                                  point(150.0, 150.0, 12.0))
        end
        group.material = material(model, kind == 'wall' && data.fetch('wall_type','brick') == 'glass' ? 'glass' : kind)
        # Display consistent AB | identifiers in Outliner without changing BIM data or LayOut tags.
        label = data.fetch('name', kind.capitalize).to_s
        group.name = label.start_with?('AB | ') ? label : "AB | #{label} | #{data['id'].to_s[0,8]}"
        group.set_attribute('SSDigitalLab_ArchiBIM', 'kind', kind)
        group.set_attribute('SSDigitalLab_ArchiBIM', 'data', JSON.generate(data))
        classify(group, IFC.fetch(kind))
        group
      end
    end
  end
end
