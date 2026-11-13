# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/geometry'

class TestVerticalHungWindowV089 < Minitest::Test
  C = SSDigitalLab::ArchiBIM::Core
  G = SSDigitalLab::ArchiBIM::Geometry
  HTML = File.read(File.expand_path('../archibim/ui/panel.html', __dir__), encoding: 'UTF-8')

  def test_top_hung_apex_is_at_top_centre
    edges = G.vertical_hinge_marker_segments(20.0, 120.0, 50.0, 150.0, 'top', 'hinge')
    assert_equal [[[20.0, 50.0], [70.0, 150.0]], [[70.0, 150.0], [120.0, 50.0]]], edges
  end

  def test_bottom_hung_apex_is_at_bottom_centre
    edges = G.vertical_hinge_marker_segments(20.0, 120.0, 50.0, 150.0, 'bottom', 'hinge')
    assert_equal [[[20.0, 150.0], [70.0, 50.0]], [[70.0, 50.0], [120.0, 150.0]]], edges
  end

  def test_handle_marker_reverses_apex_vertically_not_sideways
    edges = G.vertical_hinge_marker_segments(20.0, 120.0, 50.0, 150.0, 'top', 'handle')
    assert_equal [[[20.0, 150.0], [70.0, 50.0]], [[70.0, 50.0], [120.0, 150.0]]], edges
  end

  def test_side_hung_does_not_use_vertical_symbol
    assert_equal [], G.vertical_hinge_marker_segments(20, 120, 50, 150, 'left')
    assert_equal [], G.vertical_hinge_marker_segments(20, 120, 50, 150, 'right')
  end

  def test_window_hinge_schema_and_input_validation
    assert_equal 'top', C.settings({'window_hinge'=>'top'})['window_hinge']
    assert_equal 'bottom', C.settings({'window_hinge'=>'bottom'})['window_hinge']
    assert_raises(ArgumentError) { C.settings({'window_hinge'=>'sideways'}) }
    good={'kind'=>'window','width'=>900.0,'height'=>900.0,
      'offset'=>200.0,'sill'=>1500.0,'hinge'=>'bottom'}
    assert C.opening_valid?(good, 3000.0, 3000.0)
    assert_raises(ArgumentError) { C.opening_valid?(good.merge('hinge'=>'diagonal'), 3000.0, 3000.0) }
  end

  def test_existing_window_inspector_exposes_vertical_hinges
    assert_includes HTML, "o.kind==='window'?choices.windowHinges"
    assert_includes HTML, "['top','Top-hung (apex UP)']"
    assert_includes HTML, "['bottom','Bottom-hung (apex DOWN)']"
    assert_includes HTML, 'id="eyedropperFeedback"'
    assert_includes HTML, 'eyedropperStatus(message)'
  end

  def test_window_tool_has_top_bottom_keyboard_bindings
    script=File.read(File.expand_path('../archibim/tools.rb',__dir__))
    assert_includes script, "@hinge = 'top'"
    assert_includes script, "@hinge = 'bottom'"
  end
end
