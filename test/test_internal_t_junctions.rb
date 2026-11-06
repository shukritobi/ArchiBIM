# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/wall_graph'
require_relative '../archibim/junctions'

class TestInternalTWallJoinRegression < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def host(alignment = 'center', thickness = 150)
    G.wall([0, 0], [8000, 0], alignment: alignment, thickness: thickness)
  end
  def branch_at(y)
    G.wall([4000, 3000], [4000, y], thickness: 150, alignment: 'center')
  end

  def test_face_aligned_center_baseline_is_detected_75mm_away
    walls = { 'outer' => host, 'partition' => branch_at(75) }
    graph = G.new
    joins = graph.detect(walls)
    assert_equal 1, joins.size
    join = joins[0]
    assert_equal 'tee', join['type']
    assert_equal 'linked', join['mode']
    assert_in_delta 75, join['face_offset'], 0.0001
    assert graph.touching?(join, walls)
    plan = graph.move_plan(walls, 'outer', dx: 0, dy: 500)
    assert_equal [4000, 575], plan['walls']['partition']['end']
    assert_equal 150, plan['walls']['partition']['thickness']
    assert_equal 3000, plan['walls']['partition']['height']
  end

  def test_left_face_aligned_wall_detected_at_far_face
    walls = {'outer' => host('left', 200), 'partition' => branch_at(200)}
    join = G.new.detect(walls).first
    refute_nil join
    assert_in_delta 200.0, join['face_offset'], 0.01
  end

  def test_right_face_aligned_wall_detected_at_face
    walls = {'outer' => host('right', 200), 'partition' => branch_at(-200)}
    join = G.new.detect(walls).first
    refute_nil join
    assert_in_delta(-200.0, join['face_offset'], 0.01)
  end

  def test_small_gap_to_wall_face_can_join
    walls = {'outer' => host, 'partition' => branch_at(84)}
    assert_equal 1, G.new.detect(walls).length
    walls['partition']['end'] = [4000, 90]
    assert_equal 0, G.new.detect(walls).length
  end

  def test_legacy_join_only_upgrades_only_by_reconnect_action
    walls = {'outer' => host, 'partition' => branch_at(75)}
    graph = G.new
    link = graph.detect(walls).first
    graph.set_mode(link['id'], 'join_only', walls)
    assert_equal ['outer'], graph.move_plan(walls, 'outer', dx: 0, dy: 500)['changed']
    assert_equal 0, graph.detect(walls).length
    result = graph.reconnect_nearby(walls, 'partition')
    assert_equal [link['id']], result['upgraded']
    assert_equal 'linked', graph.find(link['id'])['mode']
    assert_equal %w[outer partition], graph.move_plan(walls, 'outer', dx: 0, dy: 500)['changed'].sort
  end

  def test_false_join_not_created_across_levels
    walls = {'outer' => host, 'partition' => branch_at(75)}
    walls['partition']['level_id'] = 'L01'
    assert_empty G.new.detect(walls)
  end

  def test_unlinked_wall_not_automatically_reattached
    walls = {'outer' => host, 'partition' => branch_at(75)}
    graph = G.new
    join = graph.detect(walls).first
    graph.set_mode(join['id'], 'unlinked', walls)
    assert_empty graph.detect(walls)
    assert_equal 0, graph.audit(walls)['linked_count']
  end

  def test_audit_shows_broken_and_geometry_data
    walls = {'outer' => host, 'partition' => branch_at(75)}
    graph = G.new
    graph.detect(walls)
    audit = graph.audit(walls)
    assert_equal 1, audit['linked_count']
    assert_equal 0, audit['broken_count']
    assert_in_delta 75, audit['connections'][0]['contact']['signed_offset_mm'], 0.01
    walls['partition']['end'] = [4000, 300]
    audit = graph.audit(walls)
    assert_equal 1, audit['broken_count']
    assert_equal false, audit['connections'][0]['touching']
  end

  def test_tee_miter_compensates_reference_offset_to_near_wall_face
    host_desc = {id: 'host', level_id: 'GF', start: [0, 0], end: [8000, 0], thickness: 150, alignment: 'center'}
    branch_desc = {id: 'branch', level_id: 'GF', start: [4000, 3000], end: [4000, 75], thickness: 150, alignment: 'center'}
    result = SSDigitalLab::ArchiBIM::Junctions.calculate([host_desc, branch_desc])
    assert_in_delta 0, result['branch']['end'].first, 0.01
  end
end

class TestBrokenLegacyTReconnect < Minitest::Test
  G = SSDigitalLab::ArchiBIM::WallGraph
  def test_refuses_to_turn_disjoint_join_only_into_linked
    walls = {'host' => G.wall([0,0],[8000,0]), 'child' => G.wall([4000,1000],[4000,0])}
    graph = G.new
    link = graph.detect(walls).first
    graph.set_mode(link['id'], 'join_only', walls)
    walls['child']['end'] = [4000, 500]
    error = assert_raises(ArgumentError) {graph.set_mode(link['id'], 'linked', walls)}
    assert_match(/no longer touch/, error.message)
    assert_equal 'join_only', graph.find(link['id'])['mode']
  end

  def test_diagnostics_lists_nearby_partition_even_when_gap_is_80mm
    walls = {'host' => G.wall([0,0],[8000,0]), 'child' => G.wall([4000,1000],[4000,155])}
    audit=G.new.audit(walls)
    candidates=audit['nearby_unconnected']
    assert candidates.any? {|entry| entry['nearest_tee'] && entry['nearest_tee']['host_id']=='host'}
    assert candidates.any? {|entry| entry['nearest_tee'] && entry['nearest_tee']['status']=='gap_too_large'}
  end
end
