# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/junctions'
class TestGlazingRegressionsV088 < Minitest::Test
  C = SSDigitalLab::ArchiBIM::Core
  J = SSDigitalLab::ArchiBIM::Junctions

  def test_transom_mullions_match_lower_sashes
    (1..8).each do |panels|
      opening={'kind'=>'window','width'=>4260.0,'panels'=>panels}
      count=C.transom_layout_count(opening)
      assert_equal panels,count
      assert_equal panels-1,count-1
    end
    assert_equal 8,C.transom_layout_count({'kind'=>'window','width'=>4260.0})
  end

  def test_legacy_door_uses_maximum_transom_panel_width
    assert_equal 2,C.transom_layout_count({'kind'=>'door','width'=>2300.0})
    assert_equal 2,C.transom_layout_count({'kind'=>'door','width'=>2300.0,'panels'=>2})
  end

  def test_top_hung_window_is_valid
    assert C.opening_valid?({'kind'=>'window','width'=>900.0,'height'=>900.0,
      'offset'=>200.0,'sill'=>1500.0,'hinge'=>'top','operation'=>'casement'},3000,3000)
  end

  def test_upper_partition_corner_uses_own_face_offsets
    a={id:'a',start:[0,0],end:[4000,0],level_id:'GF',thickness:100,alignment:'center',
      face_offsets:[-25.0,75.0]}
    b={id:'b',start:[4000,0],end:[4000,4000],level_id:'GF',thickness:100,alignment:'center',
      face_offsets:[-25.0,75.0]}
    corners=J.calculate([a,b])
    refute_equal [0.0,0.0],corners['a']['end']
    refute_equal [0.0,0.0],corners['b']['start']
    assert_equal [-25.0,75.0],J.face_offsets(a)
  end

  def test_rear_elevation_is_a_mirror_of_world_marker_not_second_x
    text=File.read(File.expand_path('../archibim/geometry.rb',__dir__))
    refute_match(/hinge_left_at\s*=\s*!hinge_left_at\s+if\s+side\.negative\?/,text)
    refute_match(/point_left\s*=\s*!point_left\s+if\s+side\.negative\?/,text)
    assert_includes text, "vertical_hinge_marker_segments(left,right,min_z,max_z,"
  end
end
