# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../archibim/documentation'
require_relative '../archibim/dxf_export'

class DocumentationSmokeTest < Minitest::Test
  def test_all_eleven_sheet_ids_are_distinct
    ids = SSDigitalLab::ArchiBIM::Documentation::DRAWING_CODES
    assert_equal 11, ids.size
    assert_equal ids.size, ids.values.uniq.size
    assert_equal 'A-401', ids['rcp_ground']
    assert_equal 'A-402', ids['rcp_first']
  end

  def test_dxf_output_contains_mm_units_and_editable_lines
    export = SSDigitalLab::ArchiBIM::DxfExport
    dxf = export.dxf_text([['AB_2D_CUT', [0, 0], [8000, 0]],
                           ['AB_2D_OPENINGS', [1000, 0], [1900, 0]]])
    assert_includes dxf, "$INSUNITS\n70\n4"
    assert_includes dxf, "AB_2D_OPENINGS"
    assert_equal 2, dxf.scan(/^LINE$/).length
    assert_match(/0\nEOF\n\z/, dxf)
  end

  def test_projection_is_orthographic
    e = SSDigitalLab::ArchiBIM::DxfExport
    assert_equal [10, 20], e.project([10, 20, 30], 'ground')
    assert_equal [20, 30], e.project([10, 20, 30], 'east')
    assert_equal [-10, 30], e.project([10, 20, 30], 'north')
  end

  def test_section_splits_planar_quad
    e = SSDigitalLab::ArchiBIM::DxfExport
    poly = [[0,0,0],[100,0,0],[100,0,100],[0,0,100]]
    segments = e.intersect_polygon(poly, 2, 50)
    assert_equal 1, segments.length
    a,b = segments.first
    assert_in_delta 50, a[2]
    assert_in_delta 50, b[2]
  end
end
