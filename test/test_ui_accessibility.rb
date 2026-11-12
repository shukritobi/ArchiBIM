# frozen_string_literal: true
require 'minitest/autorun'

class ArchiBIMAccessibilityTest < Minitest::Test
  HTML = File.read(File.expand_path('../archibim/ui/panel.html', __dir__), encoding: 'UTF-8')

  def test_qa_flagged_fields_have_explicit_labels
    %w[currentLevel newLevelName newLevelZ footprintPercent].each do |id|
      assert_includes HTML, %(for="#{id}"), "Missing accessible label for #{id}"
      assert_includes HTML, %(id="#{id}"), "Missing actual control for #{id}"
    end
  end

  def test_dynamic_level_controls_have_corresponding_labels
    assert_includes HTML, 'for="ln_${html(l.id)}"'
    assert_includes HTML, 'for="lz_${html(l.id)}"'
    assert_includes HTML, 'for="${html(id)}"'
  end

  def test_responsive_grid_and_tool_picker
    assert_match(/@media\s*\(max-width:520px\)/, HTML)
    assert_match(/\.grid\.tools\s*\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/, HTML)
    assert_match(/\.grid,\.grid\.three\s*\{grid-template-columns:minmax\(0,1fr\)/, HTML)
  end

  def test_live_status_does_not_claim_unconfirmed_success
    assert_includes HTML, 'id="actionFeedback"'
    assert_includes HTML, 'role="status" aria-live="polite"'
    assert_includes HTML, 'Awaiting model feedback.'
    assert_includes HTML, 'Model information refreshed from SketchUp.'
    refute_includes HTML, 'Saved successfully!'
  end
end
