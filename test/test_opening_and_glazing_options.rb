# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
class TestOpeningAndGlazingOptions < Minitest::Test
  C = SSDigitalLab::ArchiBIM::Core
  def opening(kind='door', overrides={})
    {'kind'=>kind,'width'=>900.0,'height'=>2100.0,'offset'=>100.0,'sill'=>0.0}.merge(overrides)
  end
  def test_wall_construction_defaults
    assert_equal({'thickness'=>150.0,'height'=>3000.0},C.wall_preset('brick'))
    assert_equal({'thickness'=>100.0,'height'=>3000.0},C.wall_preset('partition'))
    assert_equal({'thickness'=>50.0,'height'=>2100.0},C.wall_preset('glass'))
    assert_raises(ArgumentError){C.wall_preset('unsupported')}
  end
  def test_glass_defaults_and_wall_settings
    s=C.settings({'wall_type'=>'glass','glass_wall_frame'=>false,'glass_wall_frame_width'=>30.0})
    assert_equal 'glass',s['wall_type']
    refute s['glass_wall_frame']
    assert_equal 3.0,s['glass_wall_glass_thickness']
    assert_raises(ArgumentError){C.settings({'wall_type'=>'furniture'})}
  end
  def test_glass_door_options_and_hardware
    %w[solid glass_frameless glass_framed].each do |style|
      %w[lever round_knob pull].each do |handle|
        assert C.opening_valid?(opening('door',{'style'=>style,'handle'=>handle}),6000,3000)
      end
    end
    assert_raises(ArgumentError){C.opening_valid?(opening('door',{'style'=>'broken'}),6000,3000)}
    assert_raises(ArgumentError){C.opening_valid?(opening('door',{'handle'=>'cube'}),6000,3000)}
  end
  def test_fixed_window_has_valid_geometry
    %w[fixed casement].each do |operation|
      assert C.opening_valid?(opening('window',{'operation'=>operation,'sill'=>900.0,'height'=>1200.0}),6000,3000)
    end
    assert_raises(ArgumentError){C.opening_valid?(opening('window',{'operation'=>'awning'}),6000,3000)}
  end
  def test_transom_height_compatibility
    assert C.opening_valid?(opening('door',{'transom'=>true,'transom_height'=>450.0}),6000,3000)
    assert_raises(ArgumentError){C.opening_valid?(opening('door',{'transom'=>true,'transom_height'=>2040.0}),6000,3000)}
    assert_raises(ArgumentError){C.opening_valid?(opening('door',{'transom'=>true,'transom_height'=>2000.0}),6000,3000)}
  end
  def test_overlapping_batch_inputs_remain_invalid
    a=opening('window',{'id'=>'a','offset'=>100.0,'width'=>1200.0,'sill'=>900.0,'height'=>1200.0})
    b=opening('window',{'id'=>'b','offset'=>1400.0,'width'=>1200.0,'sill'=>900.0,'height'=>1200.0})
    assert C.opening_valid?(a,6000,3000,[b])
    assert_raises(ArgumentError) { C.opening_valid?(a.merge('width'=>1800.0),6000,3000,[b]) }
  end
end
