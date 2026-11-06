# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/core'
require_relative '../archibim/junctions'
require_relative '../archibim/geometry'

module SSDigitalLab
  module ArchiBIM
    class FeaturesV06Test < Minitest::Test
      def test_defaults_are_backward_compatible_and_new_family_settings_exist
        s=Core.settings({})
        assert_equal 'center',s['door_mount']
        assert_equal 'right',s['wall_exterior_side']
        assert_equal true,s['stair_cut_slab']
        assert_equal 50.0,s['stair_hole_clearance']
        assert_equal 2,s['sliding_door_panels']
        assert_equal true,s['room_add_zone']
      end

      def test_parametric_settings_validate_mounting_and_sides
        s=Core.settings({'window_mount'=>'exterior','wall_exterior_side'=>'left','room_add_zone'=>false,
                          'stair_cut_slab'=>false,'sliding_door_panels'=>4})
        assert_equal 'exterior',s['window_mount']
        assert_equal false,s['room_add_zone']
        assert_equal false,s['stair_cut_slab']
        assert_equal 4,s['sliding_door_panels']
        assert_raises(ArgumentError) { Core.settings('door_mount'=>'unsupported') }
        assert_raises(ArgumentError) { Core.settings('wall_exterior_side'=>'no') }
      end

      def test_opening_clamps_at_both_ends_and_keeps_clear_size
        assert_equal 0.0, Core.clamp_opening_offset(-200,900,6000)
        assert_equal 0.0, Core.clamp_opening_offset(40,900,6000)
        assert_equal 5550.0, Core.clamp_opening_offset(6000,450,6000)
        assert_in_delta 2550,Core.clamp_opening_offset(3000,900,6000),0.01
        assert_raises(ArgumentError) { Core.clamp_opening_offset(500,1100,900) }
      end

      def test_slab_net_area_and_quantity_subtract_one_stairwell
        holes=[{'x0'=>1500,'x1'=>2500,'y0'=>500,'y1'=>3000}]
        _xs,_ys,cells=Core.slab_cells(8000,6000,holes)
        assert_operator cells.size, :>, 0
        assert_equal 45_500_000.0,Core.slab_net_area_mm2(8000,6000,holes)
        q=Core.quantities({'kind'=>'slab','width'=>8000,'depth'=>6000,'thickness'=>150,'cutouts'=>holes})
        assert_in_delta 48.0,q['area_m2'],1e-8
        assert_in_delta 45.5,q['net_area_m2'],1e-8
        assert_in_delta 6.825,q['volume_m3'],1e-8
      end

      def test_clipped_edge_opening_and_union_of_overlapping_holes
        holes=[{'x0'=>-100,'x1'=>2000,'y0'=>1000,'y1'=>3000},
               {'x0'=>1000,'x1'=>3000,'y0'=>1000,'y1'=>3000}]
        # Union: 3000 x 2000, not 4000 x 2000.
        assert_in_delta 42_000_000,Core.slab_net_area_mm2(8000,6000,holes),0.01
        assert_equal 48_000_000.0,Core.slab_net_area_mm2(8000,6000,[])
        outside=[{'x0'=>9000,'x1'=>10000,'y0'=>1000,'y1'=>2000}]
        assert_equal 48_000_000.0,Core.slab_net_area_mm2(8000,6000,outside)
      end

      def test_exterior_flush_respects_wall_direction_and_reference_line
        d={'thickness'=>150,'alignment'=>'center','exterior_side'=>'right'}
        assert_equal [-75.0,-10.0],Geometry.frame_bounds(d,{'mount'=>'exterior'})
        assert_equal [10.0,75.0],Geometry.frame_bounds(d,{'mount'=>'interior'})
        assert_equal [-32.5,32.5],Geometry.frame_bounds(d,{'mount'=>'center'})
        d['exterior_side']='left'
        assert_equal [10.0,75.0],Geometry.frame_bounds(d,{'mount'=>'exterior'})
        d['alignment']='left'
        assert_equal [85.0,150.0],Geometry.frame_bounds(d,{'mount'=>'exterior'})
      end
    end
  end
end
