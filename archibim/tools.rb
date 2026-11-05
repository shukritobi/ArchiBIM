# frozen_string_literal: true

module SSDigitalLab
  module ArchiBIM
    class DrawTool
      def initialize(kind)
        @kind = kind
        @input = Sketchup::InputPoint.new
        @first = nil
        @hover = nil
      end

      def activate
        Sketchup.status_text = "ArchiBIM #{@kind.capitalize}: click start point, then end point. Esc cancels."
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        @hover = @input.valid? ? @input.position : nil
        view.tooltip = @input.tooltip if @input.valid?
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        p = @input.position
        if @first.nil?
          @first = p
          Sketchup.status_text = 'Click the opposite corner / end point. Esc cancels.'
        else
          begin
            ArchiBIM.create_from_tool(@kind, @first, p)
            # Continue connected walls from previous endpoint; other tools repeat from scratch.
            @first = (@kind == 'wall' ? p : nil)
          rescue StandardError => e
            UI.messagebox("ArchiBIM: #{e.message}")
            @first = nil
          end
        end
        view.invalidate
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
        if %w[slab room roof footing].include?(@kind)
          pts = [a, Geom::Point3d.new(b.x, a.y, z), b,
                 Geom::Point3d.new(a.x, b.y, z), a]
          view.draw(GL_LINE_STRIP, pts)
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

    class OpeningTool
      def initialize(kind)
        @kind = kind
      end

      def activate
        Sketchup.status_text = "ArchiBIM #{@kind.capitalize}: click a parametric wall to place the opening."
      end

      def onLButtonDown(_flags, x, y, view)
        picker = view.pick_helper
        picker.do_pick(x, y)
        wall = nil
        (0...picker.count).each do |index|
          chain = picker.path_at(index)
          next unless chain
          wall = chain.find { |e| e.is_a?(Sketchup::Group) && e.get_attribute('SSDigitalLab_ArchiBIM', 'kind') == 'wall' }
          break if wall
        end
        unless wall
          Sketchup.status_text = 'Click the surface of a wall created with ArchiBIM.'
          return
        end
        begin
          ray = view.pickray(x, y)
          inv = wall.transformation.inverse
          origin = ray[0].transform(inv)
          vector = ray[1].transform(inv)
          raise 'Pick a wall from an oblique view' if vector.y.abs < 1.0e-7
          wall_data = ArchiBIM.data_for(wall)
          plane = wall_data['thickness'].to_f.mm * 0.5
          t = (plane - origin.y) / vector.y
          hit_x = (origin.x + vector.x * t).to_mm
          ArchiBIM.place_opening(wall, @kind, hit_x)
        rescue StandardError => e
          UI.messagebox("ArchiBIM: #{e.message}")
        end
      end
    end
  end
end
