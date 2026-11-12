# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/line_wall_import'

class TestLineWallImport < Minitest::Test
  G = SSDigitalLab::ArchiBIM::LineWallImport
  def edge(a, b, id = nil)
    { id: id || "#{a}-#{b}", a: a + [0], b: b + [0] }
  end
  def build(*edges); G.build(edges); end

  def test_rectangle_connected_four_corners
    result = build(edge([0,0],[5000,0]), edge([5000,0],[5000,3000]),
                   edge([5000,3000],[0,3000]), edge([0,3000],[0,0]))
    assert_equal 4, result[:segments].size
    assert_equal 4, result[:counts]['corners']
  end

  def test_tee_keeps_host_unbroken
    result = build(edge([0,0],[5000,0]), edge([2500,0],[2500,2000]))
    assert_equal 2, result[:segments].size
    assert_equal 1, result[:counts]['tees']
  end

  def test_cross_splits_shorter_into_two_tees
    result = build(edge([0,0],[6000,0]), edge([3000,-2000],[3000,2000]))
    assert_equal 3, result[:segments].size
    assert_equal 1, result[:counts]['crossings']
  end

  def test_plus_from_four_connected_lines_becomes_cross
    result = build(edge([0,0],[3000,0]), edge([3000,0],[6000,0]),
                   edge([3000,-2000],[3000,0]), edge([3000,0],[3000,2000]))
    assert_equal 3, result[:segments].size
    assert_equal 1, result[:counts]['crossings']
  end

  def test_collinear_lines_merge
    assert_equal 1, build(edge([0,0],[2500,0]), edge([2500,0],[5000,0]))[:segments].size
  end

  def test_diagonal_corner
    assert_equal 1, build(edge([0,0],[2000,0]), edge([2000,0],[3000,1000]))[:counts]['corners']
  end

  def test_multiple_planes_are_rejected
    edges = [edge([0,0],[5000,0]), edge([5000,0],[5000,3000])]
    edges[1][:b][2] = 200
    assert_raises(ArgumentError) { G.build(edges) }
  end

  def test_sloping_line_rejected
    e = edge([0,0],[1000,0]); e[:b][2] = 500
    assert_raises(ArgumentError) { G.build([e]) }
  end

  def test_reverse_duplicate_ignored
    assert_equal 1, build(edge([0,0],[3000,0]), edge([3000,0],[0,0]))[:segments].size
  end

  def test_overlapping_collinear_lines_rejected
    assert_raises(ArgumentError) { build(edge([0,0],[3000,0]), edge([1000,0],[4000,0])) }
  end

  def test_too_short_rejected
    assert_raises(ArgumentError) { build(edge([0,0],[30,0])) }
  end

  def test_ambiguous_y_join_reported
    result = build(edge([0,0],[2000,0]), edge([0,0],[-1000,1700]),
                   edge([0,0],[-1000,-1700]))
    assert_equal 1, result[:counts]['multiway']
  end
end
