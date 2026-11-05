# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/junctions'

class JunctionMathTest < Minitest::Test
  J = SSDigitalLab::ArchiBIM::Junctions

  def wall(id, a, b, width = 150.0, alignment = 'center', level = 'GF')
    { id: id, start: a, end: b, thickness: width, alignment: alignment, level_id: level }
  end

  def test_left_middle_right_reference_lines
    assert_equal [0.0, 150.0], J.side_offsets(150, 'left')
    assert_equal [-75.0, 75.0], J.side_offsets(150, 'center')
    assert_equal [-150.0, 0.0], J.side_offsets(150, 'right')
    assert_equal [0.0, 150.0], J.side_offsets(150, nil) # old models
  end

  def test_l_join_miters_both_walls
    a = wall('a', [0, 0], [8000, 0])
    b = wall('b', [8000, 0], [8000, 6000])
    caps = J.calculate([a,b])
    assert_equal [75.0,-75.0], caps['a']['end']
    assert_equal [-75.0,75.0], caps['b']['start']
    assert_equal [0.0,0.0], caps['a']['start']
  end

  def test_reverse_draw_order_paired_faces
    a = wall('a', [0,0], [8000,0])
    b = wall('b', [8000,6000],[8000,0])
    caps = J.calculate([a,b])
    assert_in_delta 75.0, caps['a']['end'][0], 0.01
    assert_in_delta -75.0, caps['a']['end'][1], 0.01
    assert_in_delta -75.0, caps['b']['end'][0], 0.01
    assert_in_delta 75.0, caps['b']['end'][1], 0.01
  end

  def test_t_junction_stops_branch_at_host_face
    host = wall('host', [0,0],[8000,0],200)
    branch = wall('branch', [4000,-3000],[4000,0],150)
    caps = J.calculate([host,branch])
    assert_equal [0.0, 0.0], caps['host']['start']
    assert_equal [0.0, 0.0], caps['host']['end']
    assert_equal [-100.0,-100.0], caps['branch']['end']
  end

  def test_separate_levels_never_connect
    a = wall('a',[0,0],[8000,0])
    b = wall('b',[8000,0],[8000,6000],150,'center','L01')
    caps = J.calculate([a,b])
    assert_equal [0.0,0.0], caps['a']['end']
    assert_equal [0.0,0.0], caps['b']['start']
  end

  def test_parallel_collinear_stays_unaltered
    a = wall('a',[0,0],[8000,0])
    b = wall('b',[8000,0],[12000,0])
    caps = J.calculate([a,b])
    assert_equal [0.0,0.0], caps['a']['end']
  end

  def test_unsupported_three_way_join_is_not_mitred
    a = wall('a',[0,0],[8000,0])
    b = wall('b',[8000,0],[8000,6000])
    c = wall('c',[8000,0],[12000,2500])
    caps = J.calculate([a,b,c])
    assert_equal [0.0,0.0], caps['a']['end']
  end

  def test_no_join_when_endpoints_outside_tolerance
    a = wall('a',[0,0],[8000,0])
    b = wall('b',[8010,0],[8000,6000])
    caps = J.calculate([a,b])
    assert_equal [0.0,0.0], caps['a']['end']
  end
end
