# frozen_string_literal: true

module SSDigitalLab
  module ArchiBIM
    # Native-like rectangle and wall drawing with the SketchUp Measurements box.
    class DrawTool
      FOOTPRINTS = %w[slab room room_walls roof footing].freeze
      LINES = %w[wall beam stair].freeze

      def initialize(kind)
        @kind = kind
        @input = Sketchup::InputPoint.new
        @first = nil
        @hover = nil
      end

      def activate
        Sketchup.status_text = "ArchiBIM #{@kind}: click start point, then end/corner. " \
                               "Type 20' or 20',70' in Measurements. Esc cancels."
      end

      def deactivate(view); view.invalidate if view; end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        @hover = @input.valid? ? @input.position : nil
        @hover = ArchiBIM.snap_wall_point(@hover, view, x, y) if @hover && @kind == 'wall'
        @hover = ArchiBIM.workplane_pick(view,x,y) if @kind == 'room_walls' && ArchiBIM.workplane_pick(view,x,y)
        view.tooltip = @input.tooltip if @input.valid?
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        p = @hover || (@input.position if @input.valid?) || ArchiBIM.workplane_pick(view, x, y)
        return unless p
        if @first.nil?
          @first = p
          Sketchup.status_text = "Click opposite corner. Type dimensions in Measurements, e.g. 20',70'."
        else
          finish(p, view)
        end
        view.invalidate
      end

      def finish(point, view)
        ArchiBIM.create_from_tool(@kind, @first, point)
        Diagnostics.log('draw_complete', { kind: @kind, start_mm: @first.to_a.map(&:to_mm), end_mm: point.to_a.map(&:to_mm) })
        @first = (@kind == 'wall' ? point : nil)
      rescue StandardError => e
        Diagnostics.error('draw_tool', e)
        UI.messagebox("ArchiBIM: #{e.message}")
        @first = nil
      ensure
        view.invalidate
      end

      def onUserText(text, view)
        return unless @first
        parts = text.strip.split(/\s*[,;xX×]\s*/)
        raise ArgumentError, 'Type one length, or width and depth separated by a comma.' if parts.empty?
        if FOOTPRINTS.include?(@kind)
          raise ArgumentError, "Enter width and depth, e.g. 20',70'" unless parts.length == 2
          width, depth = parts.map { |part| ArchiBIM.mm_from_user(part, 'footprint dimension') }
          raise ArgumentError, 'Dimensions must be positive' unless width > 50 && depth > 50
          sign_x = @hover && @hover.x < @first.x ? -1.0 : 1.0
          sign_y = @hover && @hover.y < @first.y ? -1.0 : 1.0
          p = Geom::Point3d.new(@first.x + (sign_x * width).mm,
                                @first.y + (sign_y * depth).mm, @first.z)
        else
          raise ArgumentError, 'Enter a single length, e.g. 20\'' unless parts.size == 1
          length = ArchiBIM.mm_from_user(parts.first, 'length')
          raise ArgumentError, 'Length must be above 50 mm' unless length > 50
          dx = @hover ? @hover.x - @first.x : 1.0
          dy = @hover ? @hover.y - @first.y : 0.0
          unit = Math.hypot(dx, dy)
          dx, dy, unit = 1.0, 0.0, 1.0 if unit < 0.00001
          p = Geom::Point3d.new(@first.x + dx / unit * length.mm,
                                @first.y + dy / unit * length.mm, @first.z)
        end
        finish(p, view)
      rescue StandardError => e
        UI.beep
        Sketchup.status_text = "ArchiBIM: #{e.message}"
      end

      def onCancel(_reason, view)
        @first = nil
        view.invalidate
      end

      def draw(view)
        @input.draw(view) if @input.valid?
        return unless @first && @hover
        z = ArchiBIM.current_level['elevation'].mm
        a = Geom::Point3d.new(@first.x, @first.y, z)
        b = Geom::Point3d.new(@hover.x, @hover.y, z)
        view.drawing_color = Sketchup::Color.new(37, 160, 185)
        view.line_width = 2
        if FOOTPRINTS.include?(@kind)
          pts = [a, Geom::Point3d.new(b.x, a.y, z), b, Geom::Point3d.new(a.x, b.y, z)]
          view.draw(GL_LINE_LOOP, pts)
          if @kind == 'roof'
            options = ArchiBIM.settings
            rise = Math.tan(options['roof_pitch'].to_f * Math::PI / 180.0)
            off = options['roof_overhang'].to_f.mm
            base = z + options['roof_eave_offset'].to_f.mm
            x0, x1 = [a.x, b.x].minmax
            y0, y1 = [a.y, b.y].minmax
            x0-=off; x1+=off; y0-=off; y1+=off
            mx, my = (x0+x1)/2.0, (y0+y1)/2.0
            corners = [[x0,y0],[x1,y0],[x1,y1],[x0,y1]].map { |x,y| Geom::Point3d.new(x,y,base) }
            view.drawing_color = Sketchup::Color.new(80, 219, 185)
            view.draw(GL_LINE_LOOP,corners)
            if options['roof_type']=='hip'
              w, d = x1-x0, y1-y0
              peak = base + [w,d].min/2.0 * rise
              r1,r2 = if w <= d
                [Geom::Point3d.new(mx, y0+w/2.0,peak),Geom::Point3d.new(mx,y1-w/2.0,peak)]
              else
                [Geom::Point3d.new(x0+d/2.0,my,peak),Geom::Point3d.new(x1-d/2.0,my,peak)]
              end
              view.draw(GL_LINES,[r1,r2])
              corners.each { |pt| view.draw(GL_LINES,[pt,(pt.distance(r1)<pt.distance(r2) ? r1 : r2)]) }
            else
              peak=base+(x1-x0)/2.0*rise
              r1=Geom::Point3d.new(mx,y0,peak);r2=Geom::Point3d.new(mx,y1,peak)
              view.draw(GL_LINES,[r1,r2])
              corners[0,2].each { |pt| view.draw(GL_LINES,[pt,r1]) }
              corners[2,2].each { |pt| view.draw(GL_LINES,[pt,r2]) }
            end
          end
        elsif %w[wall beam].include?(@kind)
          th = ArchiBIM.settings[@kind == 'wall' ? 'wall_thickness' : 'beam_width']
          alignment = ArchiBIM.settings[@kind == 'wall' ? 'wall_alignment' : 'beam_alignment']
          low, high = Junctions.side_offsets(th, alignment)
          dx = b.x - a.x; dy = b.y - a.y
          magnitude = Math.hypot(dx, dy)
          return if magnitude < 0.001
          nx = -dy / magnitude; ny = dx / magnitude
          outer = [low, high].map do |offset|
            vec = Geom::Vector3d.new(nx * offset.mm, ny * offset.mm, 0)
            [a.offset(vec), b.offset(vec)]
          end
          view.draw(GL_LINE_LOOP, [outer[0][0], outer[0][1], outer[1][1], outer[1][0]])
          view.line_stipple = '-'
          view.draw(GL_LINES, [a, b])
          view.line_stipple = ''
        elsif @kind == 'stair'
          opts = ArchiBIM.settings
          vx=b.x-a.x;vy=b.y-a.y;distance=Math.hypot(vx,vy)
          return if distance < 1.0
          nx=-vy/distance;ny=vx/distance
          w=opts['stair_width'].to_f.mm
          far1=Geom::Point3d.new(a.x+nx*w,a.y+ny*w,z)
          far2=Geom::Point3d.new(b.x+nx*w,b.y+ny*w,z)
          view.draw(GL_LINE_LOOP,[a,b,far2,far1])
          count=[[opts['stair_steps'].to_i,2].max,100].min
          count.times do |i|
            t=(i+1).to_f/count
            px=a.x+vx*t;py=a.y+vy*t
            view.draw(GL_LINES,[Geom::Point3d.new(px,py,z),Geom::Point3d.new(px+nx*w,py+ny*w,z)])
          end
        else
          view.draw(GL_LINES, [a, b])
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        box.add(@first) if @first
        box.add(@hover) if @hover
        box
      end
    end

    # Single-click column placement with live/ghost preview. The placement
    # point is the middle of the column width for centre alignment, and the
    # left/right face centre for left/right alignment.
    class ColumnTool
      def initialize
        @input = Sketchup::InputPoint.new
        @hover = nil
      end

      def activate
        Sketchup.status_text = 'ArchiBIM Column: hover to preview, click the column anchor. ' \
                               'Choose Left / Center / Right in the BIM Manager.'
      end

      def deactivate(view); view.invalidate if view; end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        @hover = @input.valid? ? @input.position : ArchiBIM.workplane_pick(view, x, y)
        view.tooltip = 'Column live placement preview' if @hover
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        onMouseMove(0, x, y, view)
        return unless @hover
        ArchiBIM.create_from_tool('column', @hover, @hover)
        Diagnostics.log('column_placed', { position_mm: @hover.to_a.map(&:to_mm) })
        view.invalidate
      rescue StandardError => error
        Diagnostics.error('column_tool', error)
        UI.messagebox("ArchiBIM Column: #{error.message}")
      end

      def onCancel(_reason, view)
        @hover = nil
        view.invalidate
      end

      def draw(view)
        return unless @hover
        s = ArchiBIM.settings
        width = s['column_width']; depth = s['column_depth']; height = s['column_height']
        alignment = s['column_alignment']
        left = alignment == 'left' ? 0 : (alignment == 'right' ? -width : -width / 2.0)
        right = left + width
        bottom, top = -depth / 2.0, depth / 2.0
        z = ArchiBIM.current_level['elevation'].mm
        origin = Geom::Point3d.new(@hover.x, @hover.y, z)
        vertices = [
          [left,bottom,0], [right,bottom,0], [right,top,0], [left,top,0],
          [left,bottom,height], [right,bottom,height], [right,top,height], [left,top,height]
        ].map { |x,y,h| Geom::Point3d.new(origin.x + x.mm, origin.y + y.mm, origin.z + h.mm) }
        view.drawing_color = Sketchup::Color.new(53, 202, 180)
        view.line_width = 2
        view.line_stipple = '-'
        view.draw(GL_LINE_LOOP, vertices[0,4])
        view.draw(GL_LINE_LOOP, vertices[4,4])
        (0...4).each { |i| view.draw(GL_LINES, [vertices[i],vertices[i+4]]) }
        view.line_stipple = ''
      end

      def getExtents
        box = Geom::BoundingBox.new
        box.add(@hover) if @hover
        box
      end
    end

    # Revit/Archicad-style hosted opening preview, including plan-view picking.
    class OpeningTool
      def initialize(kind)
        @kind = kind
        @wall = nil
        @hit = nil
        @valid = false
        @hinge = 'left'
        @swing = 'in'
      end

      def activate
        Sketchup.status_text = "ArchiBIM #{@kind}: hover on wall to preview, click to insert. " \
                               'H flips hinge; F reverses swing. Works in Top/Plan.'
      end

      def deactivate(view); view.invalidate if view; end

      def find_host(view, x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        (0...picker.count).each do |index|
          chain = picker.path_at(index)
          next unless chain
          hit = chain.find do |e|
            e.is_a?(Sketchup::Group) && e.get_attribute('SSDigitalLab_ArchiBIM', 'kind') == 'wall'
          end
          return hit if hit
        end
        # Plan views may pick section cap/other groups. Find nearest wall path
        # via projection of the ray onto the plan plane with a pixel tolerance.
        ray = view.pickray(x, y)
        return nil if ray[1].z.abs < 0.000001
        z = ArchiBIM.current_level['elevation'].mm
        t = (z - ray[0].z) / ray[1].z
        query = ray[0].offset(ray[1], t)
        winner = nil; best_distance = 16.0
        ArchiBIM.elements.each do |g, data|
          next unless data['kind'] == 'wall' && data['level_id'] == ArchiBIM.current_level['id']
          local = query.transform(g.transformation.inverse)
          len = data['length'].to_f.mm
          low, high = Junctions.side_offsets(data['thickness'], data['alignment'])
          next unless local.x >= -20.mm && local.x <= len + 20.mm
          next unless local.y.to_mm >= low - 120.0 && local.y.to_mm <= high + 120.0
          mid_y = ((low + high) / 2.0).mm
          path_point = Geom::Point3d.new([[local.x, 0].max, len].min, mid_y, 1200.mm)
          screen = view.screen_coords(path_point.transform(g.transformation))
          distance = Math.hypot(screen.x - x, screen.y - y)
          if distance < best_distance
            winner = g
            best_distance = distance
          end
        end
        winner
      end

      def cursor_position(view, x, y, wall)
        ray = view.pickray(x, y)
        inv = wall.transformation.inverse
        origin = ray[0].transform(inv)
        vector = ray[1].transform(inv)
        d = ArchiBIM.data_for(wall)
        low, high = Junctions.side_offsets(d['thickness'], d['alignment'])
        # In Top/Plan ray into the horizontal story plane. In elevations ray
        # into the wall's midline. Both yield wall-local horizontal offset.
        if vector.z.abs > vector.y.abs
          raise 'Parallel to floor' if vector.z.abs < 0.0000001
          t = (1200.mm - origin.z) / vector.z
        else
          raise 'Parallel to wall' if vector.y.abs < 0.0000001
          t = (((low + high) / 2.0).mm - origin.y) / vector.y
        end
        (origin.x + vector.x * t).to_mm
      end

      def onMouseMove(_flags, x, y, view)
        @wall = find_host(view, x, y)
        @hit = @wall ? cursor_position(view, x, y, @wall) : nil
        @valid = false
        if @wall && @hit
          d = ArchiBIM.data_for(@wall); s = ArchiBIM.settings
          width = s["#{@kind}_width"]
          @hit = Core.clamp_opening_offset(@hit, width, d['length']) + width/2.0
          sill = @kind == 'window' ? s['window_sill'] : 0.0
          opening = { 'kind' => @kind, 'offset' => @hit - width / 2.0,
                      'width' => width, 'height' => s["#{@kind}_height"], 'sill' => sill }
          begin
            Core.opening_valid?(opening, d['length'], d['height'], d['openings'] || [])
            @valid = true
          rescue StandardError
            @valid = false
          end
          view.tooltip = "#{@kind.capitalize} preview | #{ArchiBIM.fmt_mm(width)} × " \
                         "#{ArchiBIM.fmt_mm(opening['height'])}, sill #{ArchiBIM.fmt_mm(sill)}" \
                         " | H: hinge, F: swing"
        end
        view.invalidate
      rescue StandardError
        @wall = nil
        @hit = nil
      end

      def onKeyDown(key, _repeat, _flags, view)
        if key == 72 || key == 104 # H
          @hinge = @hinge == 'left' ? 'right' : 'left'
        elsif key == 70 || key == 102 # F
          @swing = @swing == 'in' ? 'out' : 'in'
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        onMouseMove(0, x, y, view)
        unless @wall && @valid
          Sketchup.status_text = 'Choose a valid position on an ArchiBIM wall, away from existing openings.'
          return
        end
        ArchiBIM.place_opening(@wall, @kind, @hit, { 'hinge' => @hinge, 'swing' => @swing })
        view.invalidate
      rescue StandardError => e
        UI.messagebox("ArchiBIM: #{e.message}")
      end

      def draw(view)
        return unless @wall && @hit
        d = ArchiBIM.data_for(@wall)
        return unless d
        s = ArchiBIM.settings
        width = s["#{@kind}_width"]; height = s["#{@kind}_height"]
        sill = @kind == 'window' ? s['window_sill'] : 0.0
        low, high = Junctions.side_offsets(d['thickness'], d['alignment'])
        x0 = @hit - width / 2.0; x1 = x0 + width
        # Preview on cut plane and on wall elevation so the cursor works from
        # both plan and 3D views, without modifying geometry until click.
        plan = [[x0, low, 1200.0], [x1, low, 1200.0],
                [x1, high, 1200.0], [x0, high, 1200.0]]
        face = [[x0, high + 15.0, sill], [x1, high + 15.0, sill],
                [x1, high + 15.0, sill + height], [x0, high + 15.0, sill + height]]
        t = @wall.transformation
        view.drawing_color = @valid ? Sketchup::Color.new(38, 210, 135) : Sketchup::Color.new(235, 72, 73)
        view.line_width = 3
        view.line_stipple = '-'
        [plan, face].each do |poly|
          view.draw(GL_LINE_LOOP, poly.map { |v| Geometry.point(*v).transform(t) })
        end
        view.line_stipple = ''
      end
    end

    # Pick an existing nested hosted opening, then move it by mouse while the
    # wall and all other BIM groups stay put. A preset opening ID from the
    # inspector activates direct repositioning on its already-selected wall.
    class OpeningMoveTool
      def initialize(opening_id = nil)
        @id=opening_id
        @wall=nil
        @opening=nil
        @offset=nil
        @valid=false
      end

      def activate
        wall=ArchiBIM.selected
        if @id && wall
          d=ArchiBIM.data_for(wall)
          if d && d['kind']=='wall'
            @opening=d.fetch('openings',[]).find { |o| o['id']==@id }
            @wall=wall if @opening
          end
        end
        Sketchup.status_text=@wall ? 'ArchiBIM: hover to move opening along wall; click to confirm. Esc cancels.' :
          'ArchiBIM: click a hosted door/window to select it, then move cursor and click its new position.'
      end

      def deactivate(view); view.invalidate if view; end

      def pick_existing(view,x,y)
        picker=view.pick_helper
        picker.do_pick(x,y)
        (0...picker.count).each do |index|
          path=picker.path_at(index)
          next unless path
          host=path.find { |e| e.is_a?(Sketchup::Group) && ArchiBIM.data_for(e)&.fetch('kind',nil)=='wall' }
          next unless host
          child=path.find { |e| e.is_a?(Sketchup::Group) && e.get_attribute(ArchiBIM::DICT,'hosted')==true && e.get_attribute(ArchiBIM::DICT,'data') }
          next unless child
          detail=ArchiBIM.safe_json(child.get_attribute(ArchiBIM::DICT,'data'),nil)
          next unless detail && %w[door window sliding_door].include?(detail['kind'])
          opening=ArchiBIM.data_for(host).fetch('openings',[]).find { |v| v['id']==detail['id'] }
          return [host,opening] if opening
        end
        nil
      end

      def onMouseMove(_flags,x,y,view)
        return unless @wall && @opening
        # Reuse the same wall-plane intersection as insertion, so perspective,
        # top and elevation views all provide an accurate horizontal offset.
        center=OpeningTool.new(@opening['kind']).cursor_position(view,x,y,@wall)
        d=ArchiBIM.data_for(@wall)
        @offset=Core.clamp_opening_offset(center,@opening['width'],d['length'])
        candidate=@opening.merge('offset'=>@offset)
        @valid=false
        begin
          Core.opening_valid?(candidate,d['length'],d['height'],d['openings'])
          @valid=true
        rescue ArgumentError
          @valid=false
        end
        left=@offset
        right=d['length'].to_f-@offset-@opening['width'].to_f
        view.tooltip="Move #{@opening['kind'].tr('_',' ')} | left #{ArchiBIM.fmt_mm(left)} | right #{ArchiBIM.fmt_mm(right)} | click to confirm"
        view.invalidate
      rescue StandardError
        @valid=false
      end

      def onLButtonDown(_flags,x,y,view)
        unless @wall && @opening
          picked=pick_existing(view,x,y)
          if picked
            @wall,@opening=picked
            @id=@opening['id']
            Sketchup.active_model.selection.clear
            Sketchup.active_model.selection.add(@wall)
            Sketchup.status_text='Opening selected. Hover to reposition, click to confirm.'
          else
            Sketchup.status_text='Click directly on a hosted door/window frame or leaf.'
          end
        else
          onMouseMove(0,x,y,view)
          return unless @valid
          ArchiBIM.move_opening_on_wall(@wall,@id,@offset+@opening['width'].to_f/2.0)
          Sketchup.status_text='Opening repositioned. Select another using the BIM Manager or Esc to exit.'
          Sketchup.active_model.select_tool(nil)
        end
        view.invalidate
      rescue StandardError => e
        Diagnostics.error('move_opening_tool',e)
        UI.messagebox("ArchiBIM: #{e.message}")
      end

      def onCancel(_reason,view)
        @wall=@opening=nil
        view.invalidate
      end

      def draw(view)
        return unless @wall && @opening && @offset
        d=ArchiBIM.data_for(@wall)
        return unless d
        width=@opening['width'].to_f; height=@opening['height'].to_f
        sill=@opening['sill'].to_f; low,high=Junctions.side_offsets(d['thickness'],d['alignment'])
        x0=@offset;x1=x0+width;t=@wall.transformation
        plan=[[x0,low,1200],[x1,low,1200],[x1,high,1200],[x0,high,1200]]
        face=[[x0,high+20,sill],[x1,high+20,sill],[x1,high+20,sill+height],[x0,high+20,sill+height]]
        view.drawing_color=@valid ? Sketchup::Color.new(30,221,161) : Sketchup::Color.new(238,81,75)
        view.line_width=3
        view.line_stipple='-'
        [plan,face].each { |pts| view.draw(GL_LINE_LOOP,pts.map { |xyz| Geometry.point(*xyz).transform(t) }) }
        view.line_stipple=''
        label=Geom::Point3d.new(x0,high+90,sill+height/2).transform(t)
        right=d['length'].to_f-x1
        view.draw_text(label,"#{ArchiBIM.fmt_mm(x0)}  |  #{ArchiBIM.fmt_mm(right)}",
                       size:13,color:Sketchup::Color.new(15,135,135))
      end
    end
  end
end
