# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/wall_angle_math'

class TestWallAngleMath < Minitest::Test
  M = SSDigitalLab::ArchiBIM::WallAngleMath
  def test_near_orthogonal
    assert_in_delta 2, M.correction(88, step: 90)[:delta], 1e-8
    assert_in_delta -2, M.correction(92, step: 90)[:delta], 1e-8
  end
  def test_negative_axis_and_reverse_direction
    assert_in_delta 1, M.correction(-91)[:delta], 1e-8
    assert M.correction(179)[:applicable]
  end
  def test_intentional_slants_stay_untouched
    refute M.correction(30, step: 90)[:applicable]
    refute M.correction(15, step: 90)[:applicable]
  end
  def test_architectural_increment
    out = M.correction(31.3, step: 15, tolerance: 3)
    assert_in_delta -1.3, out[:delta], 1e-8
    assert out[:applicable]
  end
  def test_reference_relative_perpendicular
    out = M.correction(91.7, step: 90, reference: 2, tolerance: 5)
    assert_in_delta 0.3, out[:delta], 1e-8
  end
  def test_too_large_deviation_skipped
    out = M.correction(8, tolerance: 5)
    assert out[:outside_tolerance]
    refute out[:applicable]
  end
  def test_zero_correction_ignored
    assert M.correction(90)[:already_aligned]
    refute M.correction(90)[:applicable]
  end
  def test_projection_orthogonal
    out = M.project_endpoint([0,0],[1000,40],tolerance:5)
    assert out[:snapped]
    assert_in_delta 0, out[:point][1], 1e-9
    assert_in_delta 1000, out[:point][0], 1e-9
  end
  def test_projection_diagonal_unchanged
    out = M.project_endpoint([0,0],[1000,1000],tolerance:5)
    refute out[:snapped]
    assert_equal [1000,1000],out[:point]
  end
  def test_midpoint_rotation_invariant
    a=[0.0,0.0];b=[6000.0,300.0];mid=[3000.0,150.0]
    x=M.rotate_point(a,mid,-2.8);y=M.rotate_point(b,mid,-2.8)
    assert_in_delta mid[0],(x[0]+y[0])/2,1e-8
    assert_in_delta mid[1],(x[1]+y[1])/2,1e-8
  end
  def test_invalid_input
    assert_raises(ArgumentError) { M.correction(Float::NAN) }
    assert_raises(ArgumentError) { M.correction(2,tolerance:40) }
  end
end
