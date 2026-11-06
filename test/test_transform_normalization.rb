# frozen_string_literal: true
# Reproduces SketchUp Geom::Vector3d semantics WITHOUT needing SketchUp in CI.
# In SketchUp `Vector3d#*` means cross product and refuses a scalar argument.
require 'minitest/autorun'
require_relative '../archibim/repair'

unless defined?(Geom::Vector3d)
  module Geom
    class Vector3d
      attr_accessor :x, :y, :z
      def initialize(x, y, z)
        @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
      def length
        Math.sqrt(x * x + y * y + z * z)
      end
      def normalize!
        n = length
        raise ArgumentError, 'Zero vector' if n.zero?
        @x /= n; @y /= n; @z /= n
        self
      end
      def dot(other)
        x * other.x + y * other.y + z * other.z
      end
      def cross(other)
        self.class.new(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
      end
      def reverse!
        @x = -x; @y = -y; @z = -z
        self
      end
      def *(other)
        raise ArgumentError, 'Cannot convert argument to Geom::Vector3d' unless other.is_a?(Vector3d)
        cross(other)
      end
      def self.linear_combination(a, v1, b, v2)
        new(a * v1.x + b * v2.x, a * v1.y + b * v2.y, a * v1.z + b * v2.z)
      end
    end
    class Transformation
      attr_reader :origin, :xaxis, :yaxis, :zaxis
      def initialize(origin, xaxis, yaxis, zaxis)
        @origin, @xaxis, @yaxis, @zaxis = origin, xaxis, yaxis, zaxis
      end
      def self.axes(origin, xaxis, yaxis, zaxis)
        new(origin, xaxis, yaxis, zaxis)
      end
    end
  end
end

class RepairTransformNormalizationTest < Minitest::Test
  R = SSDigitalLab::ArchiBIM::Repair
  V = Geom::Vector3d
  T = Geom::Transformation

  def check_unit_axes(transform)
    assert_in_delta 1.0, transform.xaxis.length, 1e-8
    assert_in_delta 1.0, transform.yaxis.length, 1e-8
    assert_in_delta 1.0, transform.zaxis.length, 1e-8
    assert_in_delta 0.0, transform.xaxis.dot(transform.yaxis), 1e-8
    assert_in_delta 0.0, transform.xaxis.dot(transform.zaxis), 1e-8
    assert_in_delta 0.0, transform.yaxis.dot(transform.zaxis), 1e-8
  end

  def test_unscaled_edit_and_opening_path_no_longer_crashes
    t = T.axes([12, 34, 56], V.new(1, 0, 0), V.new(0, 1, 0), V.new(0, 0, 1))
    repaired = R.normalized_transform(t)
    check_unit_axes(repaired)
    assert_equal [12, 34, 56], repaired.origin
  end

  def test_nonuniform_scale_recovers_unit_frame
    t = T.axes([0, 0, 0], V.new(2, 0, 0), V.new(0, 0.4, 0), V.new(0, 0, 3))
    assert_equal [2.0, 0.4, 3.0], R.scale_factors(t)
    repaired = R.normalized_transform(t)
    check_unit_axes(repaired)
    assert_in_delta 1, repaired.xaxis.x, 1e-8
    assert_in_delta 1, repaired.yaxis.y, 1e-8
  end

  def test_rotated_wall_with_shear_gets_orthogonal_axes
    t = T.axes([7, 8, 9], V.new(1, 2, 0), V.new(-2, 1.3, 0), V.new(0, 0, 2))
    repaired = R.normalized_transform(t)
    check_unit_axes(repaired)
    assert_equal [7, 8, 9], repaired.origin
  end

  def test_collapsed_transform_raises_informative_error
    t = T.axes([0, 0, 0], V.new(0, 0, 0), V.new(0, 1, 0), V.new(0, 0, 1))
    assert_match(/collapsed BIM element/, assert_raises(ArgumentError) { R.normalized_transform(t) }.message)
  end

  def test_parallel_transform_raises_informative_error
    t = T.axes([0, 0, 0], V.new(3, 0, 0), V.new(8, 0, 0), V.new(0, 0, 1))
    assert_match(/near-parallel/, assert_raises(ArgumentError) { R.normalized_transform(t) }.message)
  end
end
