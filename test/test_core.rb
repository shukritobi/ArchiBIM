# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'

class ArchiBIMCoreTest < Minitest::Test
  C = SSDigitalLab::ArchiBIM::Core

  def wall(openings = [])
    { 'kind'=>'wall', 'length'=>5000.0, 'height'=>3000.0,
      'thickness'=>150.0, 'openings'=>openings }
  end

  def opening(id='a', kind='door', x=1000.0, z=0.0, w=900.0, h=2100.0)
    { 'id'=>id,'kind'=>kind,'offset'=>x,'sill'=>z,'width'=>w,'height'=>h }
  end

  def test_defaults_are_deep_copied
    a = C.settings({}); a['rates']['wall'] = 999
    assert_equal 120.0, C.settings({})['rates']['wall']
  end

  def test_settings_validates_fields
    assert_raises(ArgumentError) { C.settings('wall_height'=>-30) }
    assert_raises(ArgumentError) { C.settings('window_sill'=>-3) }
    assert_equal 0.0, C.settings('window_sill'=>0)['window_sill']
    assert_equal 21, C.settings('stair_steps'=>21)['stair_steps']
    assert_raises(ArgumentError) { C.settings('rates'=>{'wall'=>-1}) }
  end

  def test_no_opening_wall_one_cell
    xs,zs,cells = C.wall_cells(5000,3000,[])
    assert_equal [0.0,5000.0], xs
    assert_equal [0.0,3000.0], zs
    assert_equal 1, cells.length
  end

  def test_wall_opening_cut_area_and_volume
    door = opening
    xs,zs,cells = C.wall_cells(5000,3000,[door])
    assert_equal [0.0,2100.0,3000.0], zs
    area_mm2 = cells.values.sum { |x0,x1,z0,z1| (x1-x0)*(z1-z0) }
    assert_in_delta 15_000_000 - 900*2100, area_mm2, 0.001
    q = C.quantities(wall([door]))
    assert_in_delta 13.11, q['net_area_m2'],1e-9
    assert_in_delta 1.9665,q['volume_m3'],1e-9
    assert_in_delta 15.0,q['gross_area_m2'],1e-9
  end

  def test_tall_window_and_door_multi_cut
    ops = [opening, opening('b','window',2600,800,1200,1200)]
    _,_,cells = C.wall_cells(5000,3000,ops)
    area = cells.values.sum { |x0,x1,z0,z1| (x1-x0)*(z1-z0) }
    assert_in_delta 15_000_000-900*2100-1200*1200,area,0.1
    refute cells.values.any? { |a,b,c,d| (a+b)/2 > 1000 && (a+b)/2 < 1900 && (c+d)/2 < 2100 }
  end

  def test_openings_cannot_overlap
    assert_raises(ArgumentError) { C.wall_cells(5000,3000,[opening,opening('b','window',1500,900,1200,1200)]) }
  end

  def test_opening_on_wall_end_is_valid
    assert C.opening_valid?(opening('z','window',4100,1800,900,1200),5000,3000)
  end

  def test_opening_past_wall_end_is_invalid
    assert_raises(ArgumentError) { C.wall_cells(5000,3000,[opening('q','door',4500,0,900,2100)]) }
  end

  def test_opening_above_wall_is_invalid
    assert_raises(ArgumentError) { C.wall_cells(5000,3000,[opening('q','window',1000,2000,900,1200)]) }
  end

  def test_just_touching_openings_are_valid
    assert C.wall_cells(5000,3000,[opening,opening('b','door',1900,0,900,2100)])
  end

  def test_slab_quantities
    q = C.quantities('kind'=>'slab','width'=>8000,'depth'=>6000,'thickness'=>150)
    assert_in_delta 48.0,q['area_m2'],1e-9
    assert_in_delta 7.2,q['volume_m3'],1e-9
  end

  def test_beam_column_room_quantities
    beam=C.quantities('kind'=>'beam','length'=>4200,'width'=>300,'depth'=>450)
    assert_in_delta 0.567,beam['volume_m3'],1e-9
    assert_in_delta 4.2,beam['length_m'],1e-9
    col=C.quantities('kind'=>'column','width'=>300,'depth'=>300,'height'=>3000)
    assert_in_delta 0.27,col['volume_m3'],1e-9
    room=C.quantities('kind'=>'room','width'=>4500,'depth'=>4000)
    assert_in_delta 18,room['area_m2'],1e-9
  end

  def test_cost_includes_hosted_openings_once
    q = C.cost(wall([opening,opening('b','window',2600,800,1200,1200)]),
      C.settings({})['rates'])
    assert_in_delta (15-1.89-1.44)*120 + 450 + 650,q,1e-9
  end

  def test_roof_projected_area_and_volume
    q=C.quantities('kind'=>'roof','width'=>8000,'depth'=>6000,
      'thickness'=>125,'overhang'=>500,'pitch'=>30)
    expected_area=(9000.0 / Math.cos(Math::PI / 6)) * 7000 / 1e6
    assert_in_delta expected_area,q['area_m2'],1e-9
    assert_in_delta 7.875,q['volume_m3'],1e-9
    assert_raises(ArgumentError) { C.settings('roof_pitch'=>85) }
  end

  def test_footing_area_and_volume
    q=C.quantities('kind'=>'footing','width'=>1500,'depth'=>1500,'thickness'=>450)
    assert_in_delta 2.25,q['area_m2'],1e-9
    assert_in_delta 1.0125,q['volume_m3'],1e-9
  end

  def test_stair_volume_from_step_profile
    q=C.quantities('kind'=>'stair','run'=>5040,'width'=>1100,'rise'=>3000,'steps'=>18)
    expected=5040*1100*3000.0*19/(2*18)/1e9
    assert_in_delta expected,q['volume_m3'],1e-9
  end

  def test_invalid_nan_and_infinite
    assert_raises(ArgumentError) { C.number(Float::NAN,'x') }
    assert_raises(ArgumentError) { C.number(Float::INFINITY,'x') }
  end
end
