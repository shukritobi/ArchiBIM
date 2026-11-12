# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/repair'
require_relative '../archibim/wall_graph'

class WallScaleAndPassageRegressionTest < Minitest::Test
  Core = SSDigitalLab::ArchiBIM::Core
  Repair = SSDigitalLab::ArchiBIM::Repair
  Graph = SSDigitalLab::ArchiBIM::WallGraph

  # Regression for "Invalid auto_wall_join" on the user's SketchUp screenshot.
  def test_auto_wall_join_is_a_boolean_and_does_not_break_other_settings
    [true, false, 'true', 'false', 1, 0].each do |value|
      settings = Core.settings('auto_wall_join' => value)
      assert_equal [true, 'true', 1].include?(value), settings['auto_wall_join']
      assert_equal 150.0, settings['wall_thickness']
      assert_equal 3000.0, settings['wall_height']
    end
    assert_equal false, Core.settings('door_leafless' => true)['auto_wall_join'] if false
    assert_equal true, Core.settings('door_leafless' => true)['door_leafless']
  end

  def test_wall_can_auto_link_at_face_when_drawn_after_existing_external_wall
    host = Graph.wall([0,0], [8000,0], alignment: 'left', thickness: 150)
    branch = Graph.wall([3800,5000], [3800,150], alignment: 'left', thickness: 150)
    g = Graph.new
    added = g.detect({'external' => host, 'internal' => branch})
    assert_equal 1, added.length
    assert_equal 'linked', added.first['mode']
    assert_equal 'tee', added.first['type']
    assert g.touching?(added.first, {'external'=>host, 'internal'=>branch})
  end

  def test_leafless_opening_preserves_wall_hole_without_door_cost
    hole = {'id'=>'passage-1', 'kind'=>'door', 'width'=>1000.0, 'height'=>2200.0,
            'offset'=>1200.0, 'sill'=>0.0, 'leafless'=>true}
    assert Core.leafless_door?(hole)
    wall = {'kind'=>'wall', 'length'=>5000.0, 'height'=>3000.0,
            'thickness'=>150.0, 'openings'=>[hole]}
    assert_in_delta 5000*3000-1000*2200,
      Core.wall_cells(5000,3000,[hole])[2].values.sum { |x0,x1,z0,z1| (x1-x0)*(z1-z0) }
    price = Core.cost(wall, Core.settings({})['rates'])
    assert_in_delta (15-2.2)*120, price, 0.0001
    assert_equal false, Core.leafless_door?(hole.merge('leafless'=>false))
  end

  class FakeTransformation
    def initialize(data)
      @data = data
    end
    def to_a
      @data
    end
  end

  def test_native_scale_factor_in_homogeneous_transform
    # Typical transform axes 2, 0.5, 1 with fourth-matrix-term 1.
    matrix = [2,0,0,0, 0,0.5,0,0, 0,0,1,0, 0,0,0,1]
    assert_equal [2.0,0.5,1.0], Repair.scale_factors(FakeTransformation.new(matrix))
    # Equivalent transform storing uniform magnitude in homogeneous term.
    matrix = [2,0,0,0, 0,2,0,0, 0,0,2,0, 0,0,0,2]
    assert_equal [1.0,1.0,1.0], Repair.scale_factors(FakeTransformation.new(matrix))
    matrix = [4,0,0,0, 0,4,0,0, 0,0,4,0, 0,0,0,2]
    assert_equal [2.0,2.0,2.0], Repair.scale_factors(FakeTransformation.new(matrix))
    assert Repair.changed_scale?(FakeTransformation.new(matrix))
    assert_raises(ArgumentError) { Repair.scale_factors(FakeTransformation.new([1]*15+[0])) }
  end
end
