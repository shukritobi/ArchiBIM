# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/scan_audit'

class TestScanAudit < Minitest::Test
  A = SSDigitalLab::ArchiBIM::ScanAudit
  def test_name_guided_wall
    assert_equal 'wall', A.infer(['RoomPlan | Walls'], [150, 5000, 3000])[:kind]
  end
  def test_underscored_roomplan_tag
    assert_equal 'wall', A.infer(['RoomPlan_Walls'], [150, 6000, 3000])[:kind]
  end
  def test_name_guided_joinery
    assert_equal 'cabinet', A.infer(['Pantry cabinets'], [600, 2000, 850])[:kind]
  end
  def test_horizontal_floor_candidate
    out = A.infer(['Canvas Surface'], [4000, 5000, 10], 'horizontal_area_m2' => 20)
    assert_equal 'floor_or_ceiling', out[:kind]
    assert_equal 'needs_verification', out[:confidence]
  end
  def test_vertical_wall_candidate
    out = A.infer(['Unnamed'], [0, 4500, 2750], 'vertical_area_m2' => 11)
    assert_equal 'wall', out[:kind]
  end
  def test_unknown_furniture_is_not_a_cabinet
    assert_equal 'unknown', A.infer(['furniture'], [700, 1400, 1000])[:kind]
  end
  def test_roomplan_is_not_automatically_a_wall
    assert_equal 'unknown', A.infer(['RoomPlan'], [7000, 4000, 3000])[:kind]
  end
  def test_openings_not_confused_with_walls
    assert_equal 'opening', A.infer(['Door opening'], [100, 900, 2100])[:kind]
  end
end
