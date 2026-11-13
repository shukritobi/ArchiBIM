# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/property_transfer'

class TestPropertyEyedropper < Minitest::Test
  P = SSDigitalLab::ArchiBIM::PropertyTransfer

  def test_window_keeps_size_sill_position_and_id
    source = {'id'=>'s','kind'=>'window','width'=>2400,'height'=>1500,'offset'=>0,'sill'=>900,
      'panels'=>4,'hinge'=>'top','operation'=>'casement','glass_thickness'=>8}
    target = {'id'=>'t','kind'=>'window','width'=>900,'height'=>900,'offset'=>700,'sill'=>1500,
      'panels'=>1,'hinge'=>'left','operation'=>'fixed','glass_thickness'=>3}
    patch=P.patch(source,target)
    assert_equal 1500,patch['height']
    assert_equal 'top',patch['hinge']
    assert_equal 'casement',patch['operation']
    assert_equal 8,patch['glass_thickness']
    %w[id width offset sill panels].each { |field| refute patch.key?(field), "Should preserve #{field}" }
  end

  def test_door_style_transfers_without_changing_width
    source={'kind'=>'door','height'=>2100,'width'=>1200,'style'=>'glass_framed','glass_thickness'=>10,
      'handle'=>'pull','hinge'=>'right'}
    target={'kind'=>'door','height'=>2000,'width'=>750,'style'=>'glass_frameless','glass_thickness'=>10,
      'handle'=>'lever','hinge'=>'left'}
    patch=P.patch(source,target)
    assert_equal 'glass_framed',patch['style']
    assert_equal 'pull',patch['handle']
    assert_equal 'right',patch['hinge']
    refute patch.key?('width')
  end

  def test_wall_glazing_config_only_matches_glass_to_glass
    source={'kind'=>'wall','height'=>3000,'length'=>5000,'thickness'=>50,'wall_type'=>'glass',
      'glass_wall_mullions_count'=>3,'glass_wall_partition_above'=>true}
    glass={'kind'=>'wall','height'=>2100,'length'=>7000,'thickness'=>50,'wall_type'=>'glass',
      'glass_wall_mullions_count'=>0,'glass_wall_partition_above'=>false}
    patch=P.patch(source,glass)
    assert_equal 3000,patch['height']
    assert_equal 3,patch['glass_wall_mullions_count']
    refute patch.key?('length')
    refute patch.key?('thickness')
    brick={'kind'=>'wall','height'=>2100,'length'=>5000,'thickness'=>150,'wall_type'=>'brick'}
    refute P.patch(source,brick).key?('glass_wall_mullions_count')
  end

  def test_incompatible_kinds_fail_closed
    assert_raises(ArgumentError) { P.patch({'kind'=>'window'}, {'kind'=>'door'}) }
    assert_equal({}, P.patch({'kind'=>'room','width'=>900}, {'kind'=>'room','width'=>500}))
  end

  def test_repeated_match_same_id_rejected_by_tool
    assert P.same_object?({'id'=>'a'}, {'id'=>'a'})
    refute P.same_object?({'id'=>'a'}, {'id'=>'b'})
  end
  def test_height_is_auto_fitted_to_target_wall_without_moving_sill
    source={'kind'=>'window','id'=>'s','height'=>2100.0,'hinge'=>'top'}
    target={'kind'=>'window','id'=>'t','height'=>900.0,'width'=>900.0,'offset'=>200.0,
      'sill'=>1500.0,'hinge'=>'left','transom'=>false}
    wall={'height'=>3000.0,'openings'=>[target]}
    patch,notes=P.plan_for_host(source,target,wall)
    assert_equal 1500.0,patch['height']
    assert_equal 'top',patch['hinge']
    refute patch.key?('sill')
    refute patch.key?('width')
    assert_match(/Height fitted/,notes.join(' '))
    assert_equal 900.0,target['height'],'Planning is read-only'
    assert_equal 2100.0,source['height'],'Source never changes'
  end

  def test_overlapping_window_above_limits_copied_height
    source={'kind'=>'window','id'=>'source','height'=>2100.0}
    target={'kind'=>'window','id'=>'target','offset'=>500.0,'width'=>900.0,
      'sill'=>900.0,'height'=>500.0}
    higher={'kind'=>'window','id'=>'high','offset'=>650.0,'width'=>400.0,
      'sill'=>1600.0,'height'=>600.0}
    wall={'height'=>3000.0,'openings'=>[target,higher]}
    patch,notes=P.plan_for_host(source,target,wall)
    assert_equal 700.0,patch['height']
    assert notes.any?{|note| note.include?('Height fitted')}
  end

  def test_transom_is_shrunk_when_height_clips
    source={'kind'=>'window','id'=>'source','height'=>2000.0,
      'transom'=>true,'transom_height'=>450.0}
    target={'kind'=>'window','id'=>'target','offset'=>0.0,'width'=>900.0,
      'sill'=>1600.0,'height'=>400.0,'transom'=>false}
    wall={'height'=>2100.0,'openings'=>[target]}
    patch,notes=P.plan_for_host(source,target,wall)
    assert_equal 500.0,patch['height']
    assert_equal true,patch['transom']
    assert_equal 329.0,patch['transom_height']
    assert notes.any?{|n| n.include?('Upper fixed glass height fitted')}
  end

  def test_transom_is_disabled_when_target_too_short
    source={'kind'=>'window','id'=>'source','height'=>2000.0,
      'transom'=>true,'transom_height'=>450.0}
    target={'kind'=>'window','id'=>'target','offset'=>0.0,'width'=>900.0,
      'sill'=>1900.0,'height'=>100.0,'transom'=>false}
    wall={'height'=>2100.0,'openings'=>[target]}
    patch,notes=P.plan_for_host(source,target,wall)
    assert_equal 200.0,patch['height']
    assert_equal false,patch['transom']
    assert notes.any?{|n| n.include?('disabled')}
  end

  def test_opening_different_type_still_rejected
    assert_raises(ArgumentError) {
      P.plan_for_host({'kind'=>'door','height'=>2100}, {'kind'=>'window','height'=>900},
        {'height'=>3000,'openings'=>[]})
    }
  end

end
