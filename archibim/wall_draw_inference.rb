# frozen_string_literal: true
# Native-like inferencing for ArchiBIM's wall drawing tool, without replacing it.
require_relative 'wall_angle_math'
module SSDigitalLab
  module ArchiBIM
    module WallDrawInference
      def activate
        super
        return unless @kind == 'wall'
        Sketchup.status_text = 'ArchiBIM wall: 0/90° polar snap within 5°. Right=red X, Left=green Y, Down=unlock, hold Shift=freeze direction.'
      end

      def onMouseMove(flags, x, y, view)
        super
        @hover ||= ArchiBIM.workplane_pick(view, x, y) if @kind == 'wall'
        return unless @kind == 'wall' && @first && @hover
        dx = @hover.x - @first.x
        dy = @hover.y - @first.y
        if @direction_lock == :x
          @hover = Geom::Point3d.new(@hover.x, @first.y, @first.z)
        elsif @direction_lock == :y
          @hover = Geom::Point3d.new(@first.x, @hover.y, @first.z)
        elsif @shift_direction
          vx, vy = @shift_direction
          along = dx * vx + dy * vy
          @hover = Geom::Point3d.new(@first.x + along * vx, @first.y + along * vy, @first.z)
        else
          plan = WallAngleMath.project_endpoint([@first.x, @first.y], [@hover.x, @hover.y],
                                                step: 90, tolerance: 5)
          @hover = Geom::Point3d.new(plan[:point][0], plan[:point][1], @first.z)
        end
        view.tooltip = @direction_lock ? "Wall axis locked: #{@direction_lock.to_s.upcase}" :
          (@shift_direction ? 'Wall direction locked (Shift)' : 'ArchiBIM: 0/90° polar snapping')
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        onMouseMove(flags, x, y, view) if @kind == 'wall'
        super
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless @kind == 'wall' && @first
        case key
        when VK_RIGHT
          @direction_lock = :x
          @shift_direction = nil
          lock_wall_axis(view)
        when VK_LEFT
          @direction_lock = :y
          @shift_direction = nil
          lock_wall_axis(view)
        when VK_DOWN
          @direction_lock = nil
          @shift_direction = nil
          view.lock_inference
        when VK_SHIFT
          return unless @hover
          dx = @hover.x - @first.x
          dy = @hover.y - @first.y
          size = Math.hypot(dx, dy)
          return if size < 0.001
          @shift_direction = [dx / size, dy / size]
          @direction_lock = nil
          view.lock_inference(Sketchup::InputPoint.new(@first), Sketchup::InputPoint.new(@hover))
        when VK_UP
          Sketchup.status_text = 'Plan walls stay horizontal: Right locks red X, Left locks green Y, Down unlocks.'
        end
        view.invalidate
      end

      def onKeyUp(key, _repeat, _flags, view)
        return unless @kind == 'wall' && key == VK_SHIFT && @shift_direction
        @shift_direction = nil
        lock_wall_axis(view)
        view.invalidate
      end

      def lock_wall_axis(view)
        return view.lock_inference unless @first && @direction_lock
        vector = @direction_lock == :x ? X_AXIS : Y_AXIS
        view.lock_inference(Sketchup::InputPoint.new(@first),
                            Sketchup::InputPoint.new(@first.offset(vector, 1.m)))
      end

      def finish(point, view)
        super
      ensure
        if @kind == 'wall'
          @direction_lock = nil
          @shift_direction = nil
          view.lock_inference
        end
      end

      def onCancel(reason, view)
        @direction_lock = nil
        @shift_direction = nil
        view.lock_inference
        super
      end

      def deactivate(view)
        view.lock_inference if view
        super
      end
    end
    DrawTool.prepend(WallDrawInference) unless DrawTool.ancestors.include?(WallDrawInference)
  end
end
