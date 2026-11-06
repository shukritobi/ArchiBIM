# frozen_string_literal: true
# Dedicated two-click SketchUp Tool: single-transaction parametric wall movement.
# Does not intercept native SketchUp Move/Scale observers.
module SSDigitalLab
  module ArchiBIM
    class ConnectedMoveTool
      def initialize(wall_id)
        @id = wall_id
        @anchor = nil
        @preview = nil
        @preview_error = nil
        @distance_mm = 0.0
        @input = Sketchup::InputPoint.new
      end

      def activate
        entry = find_wall
        raise 'Wall is missing. Reselect and restart Connected Move.' unless entry
        @group, @data = entry
        tr = @group.transformation
        start = ORIGIN.transform(tr)
        finish = Geom::Point3d.new(@data['length'].to_f.mm, 0, 0).transform(tr)
        dx = finish.x - start.x
        dy = finish.y - start.y
        len = Math.hypot(dx, dy)
        raise 'Cannot move zero-length wall' if len < 1.mm
        @normal = [-dy / len, dx / len]
        @z = start.z
        Sketchup.status_text = 'ArchiBIM Connected Move: click a reference point, move perpendicular to wall, click again. Type 10\' or -3048mm for exact distance. Esc cancels.'
      end

      def deactivate(view); view.invalidate if view; end
      def onCancel(_reason, view)
        @anchor = nil
        @preview = nil
        view.invalidate
        Sketchup.active_model.select_tool(nil)
      end

      def find_wall
        ArchiBIM.elements.find { |_, d| d['kind'] == 'wall' && d['id'] == @id }
      end

      def workplane_point(view, x, y)
        ray = view.pickray(x, y)
        if ray[1].z.abs > 0.0000001
          t = (@z - ray[0].z) / ray[1].z
          ray[0].offset(ray[1], t)
        else
          @input.pick(view, x, y)
          @input.valid? ? @input.position : nil
        end
      end

      def onMouseMove(_flags, x, y, view)
        return unless @anchor
        point = workplane_point(view, x, y)
        return unless point
        delta_x = point.x - @anchor.x
        delta_y = point.y - @anchor.y
        # Constraint along selected wall's reference-normal, so a rectangle
        # remains rectangular when its north/south/east/west wall is moved.
        @distance_mm = (delta_x * @normal[0] + delta_y * @normal[1]).to_mm
        compute_preview(view)
      end

      def compute_preview(view)
        dx = @normal[0] * @distance_mm
        dy = @normal[1] * @distance_mm
        begin
          @preview = ArchiBIM.connected_wall_preview(@id, dx, dy)
          @preview_error = nil
          # Validate actual hosted cutouts too, not just reference-line length.
          @preview['changed'].each do |id|
            w = @preview['walls'].fetch(id)
            Core.wall_cells(w['length'], w['height'], w.fetch('openings', []))
          end
          view.tooltip = "Connected Move: #{ArchiBIM.fmt_mm(@distance_mm)} | #{@preview['changed'].size} walls. Click to apply."
        rescue StandardError => e
          @preview = nil
          @preview_error = e.message
          view.tooltip = "Cannot move walls: #{e.message}"
          Diagnostics.log('connected_move_preview_invalid', { id: @id, reason: e.message }) if @last_error != e.message
          @last_error = e.message
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        if @anchor.nil?
          @anchor = workplane_point(view, x, y)
          Sketchup.status_text = 'Move perpendicular to wall or enter exact displacement in Measurements. Click to confirm.' if @anchor
          view.invalidate
          return
        end
        onMouseMove(0, x, y, view)
        apply_and_finish(view)
      end

      def onUserText(text, view)
        unless @anchor
          UI.beep
          Sketchup.status_text = 'Click the starting reference point on the wall before typing a distance.'
          return
        end
        length = Sketchup.parse_length(text.to_s.strip)
        raise ArgumentError, 'Invalid distance. Try 10\', -10\', or 3048mm.' unless length
        amount = length.to_mm
        # Match cursor side for unsigned dimensions, as native SketchUp does.
        if !text.to_s.strip.start_with?('-') && @distance_mm < 0
          amount = -amount.abs
        end
        @distance_mm = amount
        compute_preview(view)
        apply_and_finish(view)
      rescue StandardError => e
        UI.beep
        Sketchup.status_text = "Connected Move: #{e.message}"
      end

      def apply_and_finish(view)
        if @preview.nil?
          Sketchup.status_text = "Connected Move blocked: #{@preview_error || 'Invalid location'}"
          UI.beep
          return
        end
        dx = @normal[0] * @distance_mm
        dy = @normal[1] * @distance_mm
        ArchiBIM.move_connected_wall(@id, dx, dy)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      rescue StandardError => e
        Diagnostics.error('connected_move', e)
        UI.messagebox("ArchiBIM Connected Move: #{e.message}")
      end

      def draw(view)
        inventory = ArchiBIM.wall_inventory
        base = inventory[@id]
        return unless base
        draw_segment(view, base['start'], base['end'], [125, 139, 158], 2)
        return unless @anchor
        walls = @preview && @preview['walls']
        if walls
          @preview['changed'].each do |id|
            w = walls.fetch(id)
            draw_segment(view, w['start'], w['end'], id == @id ? [23, 185, 160] : [50, 133, 222], 4)
          end
        else
          draw_segment(view, base['start'], base['end'], [235, 71, 71], 4)
        end
        view.line_stipple = ''
      rescue StandardError => e
        Diagnostics.error('connected_move_preview_draw', e)
      end

      def draw_segment(view, a, b, rgb, width)
        z = @z
        view.drawing_color = Sketchup::Color.new(*rgb)
        view.line_width = width
        view.line_stipple = '-'
        points = [Geom::Point3d.new(a[0].mm, a[1].mm, z),
                  Geom::Point3d.new(b[0].mm, b[1].mm, z)]
        view.draw(GL_LINES, points)
        view.draw_points(points, 7, 3, Sketchup::Color.new(*rgb))
      end

      def getExtents
        bb = Geom::BoundingBox.new
        ArchiBIM.wall_inventory.each do |id, w|
          next unless id == @id || (@preview && @preview['changed'].include?(id))
          [w['start'], w['end']].each { |p| bb.add(Geom::Point3d.new(p[0].mm, p[1].mm, @z)) }
        end
        if @preview
          @preview['changed'].each do |id|
            w = @preview['walls'][id]
            [w['start'], w['end']].each { |p| bb.add(Geom::Point3d.new(p[0].mm, p[1].mm, @z)) }
          end
        end
        bb
      end
    end
  end
end
