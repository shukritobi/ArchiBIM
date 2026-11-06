# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/junctions'
require_relative '../archibim/wall_graph'

class TestConnectionMesh < Minitest::Test
  J = SSDigitalLab::ArchiBIM::Junctions
  G = SSDigitalLab::ArchiBIM::WallGraph
  def test_unlink_removes_miter_but_does_not_modify_wall_baselines
    a={id:'a',start:[0,0],end:[6000,0],thickness:150,alignment:'center',level_id:'GF'}
    b={id:'b',start:[6000,0],end:[6000,8000],thickness:150,alignment:'center',level_id:'GF'}
    walls={'a'=>G.wall(a[:start],a[:end]),'b'=>G.wall(b[:start],b[:end])}
    graph=G.new
    link=graph.detect(walls).first
    allowed=->(w,at,v,mate_at){graph.allows_geometry?(w[:id],at,v[:id],mate_at)}
    caps=J.calculate([a,b],allow_join:allowed)
    assert_equal [75.0,-75.0],caps['a']['end']
    graph.set_mode(link['id'],'unlinked',walls)
    caps=J.calculate([a,b],allow_join:allowed)
    assert_equal [0.0,0.0],caps['a']['end']
    assert_equal [0.0,0.0],caps['b']['start']
    assert_equal [6000,0],a[:end]
  end
end
