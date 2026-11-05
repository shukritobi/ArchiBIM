# frozen_string_literal: true
# Reproduce SketchUp Vector3d semantics in CI: * is vector cross product.
require 'minitest/autorun'
require_relative '../archibim/repair'

unless defined?(Geom::Vector3d)
  module Geom
    class Vector3d
      attr_accessor :x, :y, :z
      def initialize(x,y,z)
        @x,@y,@z=x.to_f,y.to_f,z.to_f
      end
      def length
        Math.sqrt(x*x+y*y+z*z)
      end
      def normalize!
        n=length
        raise ArgumentError,'Zero vector' if n.zero?
        @x/=n;@y/=n;@z/=n
        self
      end
      def dot(v)
        x*v.x+y*v.y+z*v.z
      end
      def cross(v)
        self.class.new(y*v.z-z*v.y,z*v.x-x*v.z,x*v.y-y*v.x)
      end
      def reverse!
        @x=-x;@y=-y;@z=-z;self
      end
      def *(other)
        raise ArgumentError,'Cannot convert argument to Geom::Vector3d' unless other.is_a?(Vector3d)
        cross(other)
      end
      def self.linear_combination(a,v1,b,v2)
        new(a*v1.x+b*v2.x,a*v1.y+b*v2.y,a*v1.z+b*v2.z)
      end
    end
    class Transformation
      attr_reader :origin,:xaxis,:yaxis,:zaxis
      def initialize(origin,xaxis,yaxis,zaxis)
        @origin,@xaxis,@yaxis,@zaxis=origin,xaxis,yaxis,zaxis
      end
      def self.axes(origin,xaxis,yaxis,zaxis)
        new(origin,xaxis,yaxis,zaxis)
      end
    end
  end
end

class RepairTransformNormalizationTest < Minitest::Test
  R=SSDigitalLab::ArchiBIM::Repair
  V=Geom::Vector3d
  T=Geom::Transformation
  def check_unit_axes(t)
    assert_in_delta 1,t.xaxis.length,1e-8
    assert_in_delta 1,t.yaxis.length,1e-8
    assert_in_delta 1,t.zaxis.length,1e-8
    assert_in_delta 0,t.xaxis.dot(t.yaxis),1e-8
    assert_in_delta 0,t.xaxis.dot(t.zaxis),1e-8
    assert_in_delta 0,t.yaxis.dot(t.zaxis),1e-8
  end
  def test_unscaled_edit_and_opening_path
    t=T.axes([12,34,56],V.new(1,0,0),V.new(0,1,0),V.new(0,0,1))
    n=R.normalized_transform(t)
    check_unit_axes(n)
    assert_equal [12,34,56],n.origin
  end
  def test_nonuniform_scale
    t=T.axes([0,0,0],V.new(2,0,0),V.new(0,0.4,0),V.new(0,0,3))
    assert_equal [2,0.4,3],R.scale_factors(t)
    check_unit_axes(R.normalized_transform(t))
  end
  def test_rotated_sheared_wall
    t=T.axes([7,8,9],V.new(1,2,0),V.new(-2,1.3,0),V.new(0,0,2))
    n=R.normalized_transform(t)
    check_unit_axes(n)
    assert_equal [7,8,9],n.origin
  end
  def test_collapsed_transform
    t=T.axes([0,0,0],V.new(0,0,0),V.new(0,1,0),V.new(0,0,1))
    assert_match(/collapsed BIM element/,assert_raises(ArgumentError){R.normalized_transform(t)}.message)
  end
  def test_parallel_transform
    t=T.axes([0,0,0],V.new(3,0,0),V.new(8,0,0),V.new(0,0,1))
    assert_match(/near-parallel/,assert_raises(ArgumentError){R.normalized_transform(t)}.message)
  end
end
