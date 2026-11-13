# frozen_string_literal: true
# Pure Ruby angle and orthogonal projection helpers. Degrees and millimetres.
module SSDigitalLab
  module ArchiBIM
    module WallAngleMath
      extend self
      EPS = 1.0e-6

      def finite!(value, label)
        result = Float(value)
        raise ArgumentError, "Invalid #{label}" unless result.finite?
        result
      rescue TypeError, ArgumentError
        raise ArgumentError, "Invalid #{label}"
      end

      def signed_delta(from, to)
        ((to - from + 180.0) % 360.0) - 180.0
      end

      # Orientation modulo 180 degrees: reversing a wall is equivalent.
      # Only deviations within tolerance may change. Preserve intentional angles.
      def correction(angle, step: 90.0, tolerance: 5.0, reference: 0.0)
        angle = finite!(angle, 'angle')
        step = finite!(step, 'angle increment')
        tolerance = finite!(tolerance, 'tolerance')
        reference = finite!(reference, 'reference')
        raise ArgumentError, 'Angle increment must be 15, 30, 45, or 90 degrees' unless [15.0, 30.0, 45.0, 90.0].include?(step)
        raise ArgumentError, 'Tolerance must be between 0.1 and 15 degrees' unless tolerance.between?(0.1, 15.0)
        index = ((angle - reference) / step).round
        target = reference + index * step
        delta = signed_delta(angle, target)
        { angle: angle, target: target, delta: delta,
          applicable: delta.abs <= tolerance && delta.abs >= 0.02,
          outside_tolerance: delta.abs > tolerance,
          already_aligned: delta.abs < 0.02 }
      end

      # Preserve the distance along the intended axis, removing cross-axis drift.
      def project_endpoint(a, b, step: 90.0, tolerance: 5.0, reference: 0.0)
        ax, ay = Array(a).first(2).map { |v| finite!(v, 'start') }
        bx, by = Array(b).first(2).map { |v| finite!(v, 'end') }
        dx, dy = bx - ax, by - ay
        return { point: [bx, by], snapped: false } if Math.hypot(dx, dy) < EPS
        result = correction(Math.atan2(dy, dx) * 180.0 / Math::PI, step: step, tolerance: tolerance, reference: reference)
        return { point: [bx, by], snapped: false } if result[:outside_tolerance]
        radians = result[:target] * Math::PI / 180.0
        x_axis = Math.cos(radians)
        y_axis = Math.sin(radians)
        distance = dx * x_axis + dy * y_axis
        { point: [ax + distance * x_axis, ay + distance * y_axis],
          snapped: true, angle: result[:target] }
      end

      def rotate_point(point, pivot, angle)
        radians = finite!(angle, 'angle') * Math::PI / 180.0
        px, py = point.map(&:to_f)
        cx, cy = pivot.map(&:to_f)
        x, y = px - cx, py - cy
        [cx + Math.cos(radians) * x - Math.sin(radians) * y,
         cy + Math.sin(radians) * x + Math.cos(radians) * y]
      end
    end
  end
end
