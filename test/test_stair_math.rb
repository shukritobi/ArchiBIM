# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/stair_math'

class StairMathTest < Minitest::Test
  S = SSDigitalLab::ArchiBIM::StairMath

  def test_straight_flight_has_n_minus_one_treads_and_sloped_underside
    data = {'style'=>'straight','steps'=>18,'rise'=>3000.0,'run'=>4500.0,'width'=>1000.0}
    run = S.layout(data).first
    assert_equal 18, run.fetch('risers')
    assert_in_delta 4500.0 / 17.0, run.fetch('tread'), 0.001
    profile = S.flight_profile(risers:18,going:4500.0,rise:3000.0,waist:150.0)
    assert_equal [0.0, 0.0], profile.first
    assert_equal [4500.0, 2850.0], profile.last
    assert_in_delta 3000.0, profile[-2][1], 0.001
    assert_equal 37, profile.length
  end

  def test_u_stair_has_two_flights_and_landing_clearance
    data = {'style'=>'u','steps'=>18,'rise'=>3000.0,'run'=>5000.0,'width'=>1100.0,'landing'=>1100.0,'gap'=>150.0}
    flights=S.layout(data)
    assert_equal 2, flights.length
    assert_equal(-1,flights.last['direction'])
    assert_equal 9, flights.first.fetch('risers')
    assert_in_delta 1500.0, flights.last.fetch('base'), 0.001
    assert_operator flights.first['going'], :>, 3000.0
  end

  def test_riser_and_tread_warnings
    data={'style'=>'straight','steps'=>12,'rise'=>3000.0,'run'=>2200.0,'width'=>900.0}
    messages=S.warnings(data)
    assert messages.any? { |m| m.include?('Riser') }
    assert messages.any? { |m| m.include?('Going') }
  end

  def test_impossible_u_stair_is_rejected
    data={'style'=>'u','steps'=>4,'rise'=>3000.0,'run'=>1000.0,'width'=>900.0,'landing'=>1200.0,'gap'=>150.0}
    assert_raises(ArgumentError){S.layout(data)}
  end

  def test_inspector_dimension_formatting_does_not_consume_boolean_values
    raw = [true, false, 'gable', '150mm', 3000.0, 125.0, 0.0]
    assert_equal [3000.0, 125.0, 0.0], SSDigitalLab::ArchiBIM::Core.numeric_dimensions(raw)
  end

  def test_boolean_preset_and_level_defaults
    s=SSDigitalLab::ArchiBIM::Core.settings({'roof_infill'=>false,'auto_repair_scale'=>false,'roof_type'=>'hip','stair_handrail'=>'left'})
    assert_equal false, s['roof_infill']
    assert_equal false, s['auto_repair_scale']
    assert_equal 'hip', s['roof_type']
    assert_equal 'left', s['stair_handrail']
    assert_equal 2, SSDigitalLab::ArchiBIM::Core.default_levels.size
  end
end
