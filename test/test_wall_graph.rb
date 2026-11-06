# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/wall_graph'

class TestWallGraph < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def shell
    { 'south' => G.wall([0,0],[6096,0]),
      'east' => G.wall([6096,0],[6096,21336]),
      'north' => G.wall([6096,21336],[0,21336]),
      'west' => G.wall([0,21336],[0,0]) }
  end
  def graph
    g=G.new
    assert_equal 4,g.detect(shell).length
    g
  end
  def test_creates_4_linked_corners
    g=graph
    assert_equal %w[linked linked linked linked],g.records.map{|r|r['mode']}
    assert_equal 4,g.to_h['connections'].length
    assert_equal 0,g.detect(shell).length
  end
  def test_moves_south_out_10ft_without_changing_wall_specs
    g=graph
    plan=g.move_plan(shell,'south',dx:0,dy:-3048)
    w=plan.fetch('walls')
    assert_in_delta 24384, g.length(w['east']),0.01
    assert_in_delta 24384, g.length(w['west']),0.01
    assert_equal shell['north']['end'], w['north']['end']
    assert_equal [0,-3048], w['south']['start']
    assert_equal 150, w['east']['thickness']
    assert_equal 3000, w['east']['height']
    assert_equal 4,plan['changed'].size-0 if false # north unchanged
    assert_equal %w[east south west],plan['changed'].sort
    assert_equal [0,0],shell['south']['start'] # no mutation
  end
  def test_unlink_one_corner_excludes_right_neighbor
    g=graph
    se=g.records.find{|r|[r['a'],r['b']].sort==%w[east south]}
    g.set_mode(se['id'],'unlinked',shell)
    plan=g.move_plan(shell,'south',dx:0,dy:-3048)
    assert_equal %w[south west],plan['changed'].sort
    assert_equal shell['east']['start'],plan['walls']['east']['start']
    assert_equal 0,g.detect(shell).length
  end
  def test_join_only_is_geometric_without_move_propagation
    g=graph
    g.connections_for('south').each{|r|g.set_mode(r['id'],'join_only',shell)}
    plan=g.move_plan(shell,'south',dx:0,dy:-3048)
    assert_equal ['south'],plan['changed']
  end
  def test_unlinked_reconnect_requires_contact
    g=graph
    j=g.connections_for('south').first
    g.set_mode(j['id'],'unlinked',shell)
    g.set_mode(j['id'],'linked',shell)
    assert_equal 'linked',j['mode']
    g.set_mode(j['id'],'unlinked',shell)
    walls=shell
    walls[j['a']]['start']=[900,900]
    assert_raises(ArgumentError){g.set_mode(j['id'],'linked',walls)}
  end
  def test_preserves_opening_world_position_on_extended_start
    walls=shell
    walls['east']['openings']=[{'id'=>'win','offset'=>4000.0,'width'=>1200.0,'height'=>1200.0,'sill'=>900.0}]
    plan=graph.move_plan(walls,'south',dx:0,dy:-3048)
    assert_in_delta 7048,plan['walls']['east']['openings'][0]['offset'],0.01
    assert_equal 1200.0,plan['walls']['east']['openings'][0]['width']
  end
  def test_prevents_opening_from_falling_out_when_shortened
    walls=shell
    walls['east']['openings']=[{'id'=>'win','offset'=>100.0,'width'=>1200.0,'height'=>1200.0,'sill'=>900.0}]
    assert_raises(ArgumentError){graph.move_plan(walls,'south',dx:0,dy:3000)}
    assert_equal [6096,0],walls['east']['start']
  end
  def test_non_cross_level
    walls=shell
    walls['west']['level_id']='L01'
    g=G.new
    assert_equal 2,g.detect(walls).length
  end
  def test_tee_default_linked
    walls={'host'=>G.wall([0,0],[8000,0]),'branch'=>G.wall([4000,4000],[4000,0])}
    g=G.new
    joins=g.detect(walls)
    assert_equal 1,joins.length
    assert_equal 'tee',joins[0]['type']
    assert_equal 'linked',joins[0]['mode']
    assert_equal ['branch'],g.move_plan(walls,'host',dx:0,dy:500)['changed']-['host']
  end
  def test_tee_linked_host_move_reshapes_branch
    walls={'host'=>G.wall([0,0],[8000,0]),'branch'=>G.wall([4000,4000],[4000,0])}
    g=G.new; join=g.detect(walls).first
    g.set_mode(join['id'],'linked',walls)
    plan=g.move_plan(walls,'host',dx:0,dy:500)
    assert_equal [4000,500],plan['walls']['branch']['end']
    assert_equal [4000,4000],plan['walls']['branch']['start']
  end
  def test_tee_linked_branch_slides_along_host
    walls={'host'=>G.wall([0,0],[8000,0]),'branch'=>G.wall([4000,4000],[4000,0])}
    g=G.new; join=g.detect(walls).first
    g.set_mode(join['id'],'linked',walls)
    plan=g.move_plan(walls,'branch',dx:500,dy:0)
    assert_equal ['branch'],plan['changed']
    assert_equal [4500,0],plan['walls']['branch']['end']
  end
  def test_graph_serialization_unlink_persists
    g=graph
    j=g.records.first
    g.set_mode(j['id'],'unlinked',shell)
    other=G.new(g.serialize)
    assert_equal 'unlinked',other.find(j['id'])['mode']
    assert_equal 0,other.detect(shell).length
  end
  def test_prevents_short_wall_and_does_not_commit
    walls=shell
    g=graph
    assert_raises(ArgumentError){g.move_plan(walls,'south',dx:0,dy:21310)}
    assert_equal 21336,g.length(walls['west'])
  end
  def test_unlinks_entire_wall
    g=graph
    g.unlink_wall('south')
    assert g.connections_for('south').all?{|r|r['mode']=='unlinked'}
    assert_equal 0,g.detect(shell).length
  end
end

class TestWallGraphExtra < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def test_unlink_wall_without_existing_links_blocks_future_automatic_connections
    s={'a'=>G.wall([0,0],[1000,0])}
    g=G.new
    g.unlink_wall('a')
    s['b']=G.wall([1000,0],[1000,1000])
    assert_equal [],g.detect(s)
    assert_equal ['a'],G.new(g.serialize).disabled_walls
    g.reconnect_nearby(s,'a')
    assert_equal 1,g.connections_for('a').length
    assert_equal [],g.disabled_walls
  end
  def test_unlinked_pair_does_not_allow_miter_geometry
    s={'a'=>G.wall([0,0],[1000,0]),'b'=>G.wall([1000,0],[1000,1000])}
    g=G.new
    j=g.detect(s).first
    assert g.allows_geometry?(j['a'],j['a_end'],j['b'],j['b_end'])
    g.set_mode(j['id'],'unlinked',s)
    refute g.allows_geometry?(j['a'],j['a_end'],j['b'],j['b_end'])
    assert_equal [],g.detect(s)
  end
end

class TestBrokenWallJunction < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def test_rejects_outdated_link_after_native_move
    walls={'a'=>G.wall([0,0],[6000,0]),'b'=>G.wall([6000,0],[6000,10000])}
    graph=G.new
    graph.detect(walls)
    walls['b']['start']=[6500,0]
    assert_raises(ArgumentError) { graph.move_plan(walls,'a',dx:0,dy:1000) }
    assert_equal [0,0],walls['a']['start']
  end
end
