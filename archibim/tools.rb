# frozen_string_literal: true

module SSDigitalLab
  module ArchiBIM
    # Native-like rectangle and wall drawing with the SketchUp Measurements box.
    class DrawTool
      FOOTPRINTS = %w[slab room roof footing].freeze
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
          sill = @kind == 'door' ? 0.0 : s['window_sill']
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
        sill = @kind == 'door' ? 0.0 : s['window_sill']
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
  end
end
