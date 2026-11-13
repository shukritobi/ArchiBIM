# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/glazing_layout'
class TestGlazingLayout < Minitest::Test
  M = SSDigitalLab::ArchiBIM::GlazingLayout
  def wall(**args)
    {'length'=>4800.0,'height'=>2700.0,'glass_wall_frame'=>true,
     'glass_wall_frame_width'=>30.0,'glass_wall_mullions_count'=>0,
     'glass_wall_mullion_width'=>20.0,'openings'=>[]}.merge(args.transform_keys(&:to_s))
  end
  def test_glass_stops_within_perimeter_frame
    panes=M.pane_rectangles(wall)
    assert_equal [[33.0,4767.0,33.0,2667.0]],panes
  end
  def test_frameless_glass_fills_envelope
    assert_equal [[0.0,4800.0,0.0,2700.0]],M.pane_rectangles(wall(glass_wall_frame:false))
  end
  def test_equal_vertical_mullions
    assert_equal [1200,2400,3600],M.vertical_stations(4800,3)
    panes=M.pane_rectangles(wall(glass_wall_mullions_count:3))
    assert_equal 4,panes.length
    assert panes.each_cons(2).all?{|a,b| b[0]>a[1]}
  end
  def test_frameless_door_void_and_auto_head
    opening={'kind'=>'door','offset'=>1800.0,'width'=>900.0,'height'=>2100.0,'sill'=>0.0,'style'=>'glass_frameless'}
    w=wall(openings:[opening],glass_wall_mullions_count:3)
    assert_equal [2100.0], M.transom_stations(w)
    panes=M.pane_rectangles(w)
    refute panes.any?{|a,b,c,d| (a+b)/2.0 > 1800 && (a+b)/2.0 < 2700 && (c+d)/2.0 < 2100}
    assert panes.any?{|a,b,c,d| (a+b)/2.0 > 1800 && (a+b)/2.0 < 2700 && c > 2100}
    refute M.active_vertical_stations(4800,[opening],3).include?(2400)
    assert_equal [[0,1800],[2700,4800]],M.segments_outside_openings(4800,[opening],0,30)
  end
  def test_no_door_no_auto_transom
    assert_empty M.transom_stations(wall)
  end
  def test_disabled_auto_transom
    opening={'kind'=>'door','offset'=>1800.0,'width'=>900.0,'height'=>2100.0,'sill'=>0.0}
    assert_empty M.transom_stations(wall(openings:[opening],glass_wall_auto_transom:false))
  end
  def test_window_preset_bay_math_and_transoms
    require_relative '../archibim/core'
    c=SSDigitalLab::ArchiBIM::Core
    assert_equal 2,c.window_panel_count(900)
    assert_equal 1,c.window_panel_count(300)
    assert_equal 4,c.window_panel_count(2100)
    assert_equal 2,c.transom_panel_count(2300)
    p=c.window_preset('toilet_top_hung')
    assert_equal 900.0,p['width']
    assert_equal 'top',p['hinge']
    assert_equal 300.0,c.window_preset('tall_narrow')['sill']
  end
  def test_mullion_limits
    assert_raises(ArgumentError){M.vertical_stations(4800,31)}
  end
end
