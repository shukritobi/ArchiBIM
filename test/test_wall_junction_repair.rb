# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/wall_graph'
class WallJunctionRepairRegression < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def test_binary_rounding_at_exact_ten_mm_is_not_broken
    w = {'a'=>G.wall([0,0],[4000,0]),
         'b'=>G.wall([4000,10.000000000001364],[4000,2000])}
    g=G.new
    links=g.detect(w)
    assert_equal 1, links.length
    assert g.touching?(links.first,w)
    assert_equal 0, g.audit(w)['broken_count']
  end
  def test_butt_branch_150mm_from_wall_face_requires_explicit_heal
    w = {'host'=>G.wall([0,0],[8000,0], alignment:'left'),
         'branch'=>G.wall([4000,-2000],[4000,-150],alignment:'center')}
    g=G.new
    assert_empty g.detect(w)
    plan=g.repair_plan(w,selected_ids:['branch'],max_gap_mm:170)
    assert_equal 1,plan['changes'].length
    assert_equal 'tee',plan['changes'].first['type']
    assert_in_delta 0,plan['walls']['branch']['end'][1],1e-7
    assert_equal -150,w['branch']['end'][1] # source unchanged
    joined=G.new
    assert_equal 1,joined.detect(plan['walls']).length
    assert_equal 0, joined.audit(plan['walls'])['broken_count']
  end
  def test_repairs_off_axis_host_face_without_forcing_midline
    w = {'host'=>G.wall([0,0],[8000,0], alignment:'center'),
         'branch'=>G.wall([4000,-2000],[4000,-200],alignment:'center')}
    g=G.new
    plan=g.repair_plan(w,selected_ids:['branch'],max_gap_mm:170)
    assert_equal 1,plan['changes'].length
    assert_in_delta(-75,plan['walls']['branch']['end'][1],1e-8)
  end
  def test_655mm_displaced_junction_not_guessed
    w={'a'=>G.wall([0,0],[6000,0]),'b'=>G.wall([6655,0],[6655,3000])}
    g=G.new
    assert_empty g.repair_plan(w,selected_ids:['a'],max_gap_mm:170)['changes']
  end
  def test_no_repair_across_stories_or_parallel_walls
    w={'a'=>G.wall([0,0],[6000,0]), 'parallel'=>G.wall([0,150],[6000,150]),
       'upstairs'=>G.wall([4000,150],[4000,4000],level_id:'L01')}
    g=G.new
    assert_empty g.repair_plan(w,selected_ids:['a'],max_gap_mm:170)['changes']
  end
  def test_tied_opening_stays_world_anchored_after_repair
    w={'host'=>G.wall([0,0],[8000,0],alignment:'left'),
       'branch'=>G.wall([4000,-2000],[4000,-150],openings:[
         {'id'=>'door','offset'=>900.0,'width'=>800.0,'height'=>1800.0,'sill'=>0.0}])}
    g=G.new
    plan=g.repair_plan(w,selected_ids:['branch'],max_gap_mm:170)
    assert_equal 1,plan['changes'].length
    assert_in_delta 900.0,plan['walls']['branch']['openings'].first['offset'],1e-8
    assert_equal 1850.0,w['branch']['end'][1]+2000.0
  end
  def test_healing_is_idempotent
    w={'host'=>G.wall([0,0],[8000,0],alignment:'left'),
       'branch'=>G.wall([4000,-2000],[4000,-150])}
    g=G.new
    p=g.repair_plan(w,selected_ids:['branch'],max_gap_mm:170)
    g.detect(p['walls'])
    assert_empty g.repair_plan(p['walls'],selected_ids:['branch'],max_gap_mm:170)['changes']
  end
  def test_limit_validation_and_disabled_wall
    w={'host'=>G.wall([0,0],[8000,0],alignment:'left'),
       'branch'=>G.wall([4000,-2000],[4000,-150])}
    g=G.new
    assert_raises(ArgumentError){g.repair_plan(w,selected_ids:['branch'],max_gap_mm:500)}
    g.unlink_wall('branch')
    assert_empty g.repair_plan(w,selected_ids:['branch'],max_gap_mm:170)['changes']
  end
end
