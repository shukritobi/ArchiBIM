# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/repair'

class RepairTest < Minitest::Test
  include SSDigitalLab::ArchiBIM

  def test_adopting_scale_changes_length_not_thickness_or_openings
    before = { 'kind' => 'wall', 'length' => 6000.0, 'height' => 3000.0,
               'thickness' => 150.0,
               'openings' => [{ 'offset' => 2000.0, 'width' => 900.0, 'height' => 2100.0, 'sill' => 0 }] }
    after = Repair.scaled_data(before, 0.8, 0.5)
    assert_in_delta 4800, after['length'], 0.001
    assert_in_delta 150, after['thickness'], 0.001
    assert_in_delta 900, after['openings'][0]['width'], 0.001
    assert_in_delta 1510, after['openings'][0]['offset'], 0.001
    assert_equal 6000.0, before['length']
  end

  def test_scaled_window_does_not_fit_throws_instead_of_creating_wrong_cut
    before = { 'kind' => 'wall', 'length' => 1500.0,
               'openings' => [{ 'offset' => 300.0, 'width' => 1200.0 }] }
    assert_raises(ArgumentError) { Repair.scaled_data(before, 0.2, 0.2) }
  end

  def test_roof_and_slab_keep_thickness
    %w[roof slab].each do |kind|
      data = { 'kind' => kind, 'width' => 5000.0, 'depth' => 6000.0,
               'thickness' => 125.0, 'pitch' => 25.0 }
      updated = Repair.scaled_data(data, 0.75, 0.60)
      assert_equal 3750.0, updated['width']
      assert_equal 3600.0, updated['depth']
      assert_equal 125.0, updated['thickness']
    end
  end

  def test_beam_and_stairs_preserve_cross_section
    beam = { 'kind' => 'beam', 'length' => 5000.0, 'width' => 300.0, 'depth' => 450.0 }
    stair = { 'kind' => 'stair', 'run' => 4000.0, 'width' => 1000.0, 'rise' => 3000.0 }
    assert_equal 2500.0, Repair.scaled_data(beam, 0.5, 0.5)['length']
    assert_equal 300.0, Repair.scaled_data(beam, 0.5, 0.5)['width']
    assert_equal 2500.0, Repair.scaled_data(stair, 0.625, 0.5)['run']
    assert_equal 3000.0, Repair.scaled_data(stair, 0.625, 0.5)['rise']
  end

  def test_new_family_presets
    s = Core.settings({ 'roof_type' => 'hip', 'stair_style' => 'u',
                        'window_panels' => 2, 'roof_infill' => false,
                        'column_alignment' => 'right', 'beam_alignment' => 'left' })
    assert_equal 'hip', s['roof_type']
    assert_equal 'u', s['stair_style']
    assert_equal 2, s['window_panels']
    assert_equal false, s['roof_infill']
    assert_equal 'right', s['column_alignment']
    assert_equal 'left', s['beam_alignment']
    assert_equal 50, s['window_outer_frame']
    assert_equal 30, s['window_inner_frame']
    assert_equal 3, s['window_glass_thickness']
    assert_raises(ArgumentError) { Core.settings({ 'roof_type' => 'butterfly' }) }
    assert_raises(ArgumentError) { Core.settings({ 'window_panels' => 9 }) }
  end
end
