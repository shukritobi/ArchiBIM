# frozen_string_literal: true
# Pure data reconciliation plus SketchUp transformation normalization.
module SSDigitalLab
  module ArchiBIM
    module Repair
      module_function

      def scaled_data(old, x_scale, y_scale)
        sx, sy = Float(x_scale), Float(y_scale)
        raise ArgumentError, 'Scale factors must be positive' unless sx.finite? && sy.finite? && sx > 0.01 && sy > 0.01
        data = Marshal.load(Marshal.dump(old))
        case data['kind']
        when 'wall'
          data['length'] *= sx
          data.fetch('openings', []).each do |opening|
            midpoint = (opening['offset'] + opening['width'] / 2.0) * sx
            opening['offset'] = midpoint - opening['width'] / 2.0
            raise ArgumentError, 'Scaled wall is too short for one of its openings' if opening['offset'] < -0.01 || opening['offset'] + opening['width'] > data['length'] + 0.01
          end
          data.delete('joins')
        when 'slab', 'room', 'roof', 'footing'
          data['width'] *= sx
          data['depth'] *= sy
        when 'beam'
          data['length'] *= sx
        when 'stair'
          data['run'] *= sx
        end
        data
      end

      def scale_factors(transformation)
        [transformation.xaxis.length, transformation.yaxis.length, transformation.zaxis.length]
      end

      def normalized_transform(transform)
        x, y, z = transform.xaxis, transform.yaxis, transform.zaxis
        raise ArgumentError, 'Cannot normalize a zero-size transformation' if [x.length, y.length, z.length].any? { |v| v < 0.00001 }
        x.normalize!; y.normalize!; z.normalize!
        raise ArgumentError, 'Skewed/sheared group: cannot safely reconstruct' if x.dot(y).abs > 0.001 || y.dot(z).abs > 0.001 || x.dot(z).abs > 0.001
        Geom::Transformation.axes(transform.origin, x, y, z)
      end

      def changed_scale?(transform)
        scale_factors(transform).any? { |v| (v - 1.0).abs > 0.0001 }
      end
    end
  end
end
