# ArchiBIM 0.4.0 | SketchUp 2026 field-test fixes

Build date: 5 November 2026. Based on recorded tester screenshots of the v0.3 model. This release remains an **early test build**, not production-validated.

## Changes

1. **Wall and object rebuild:** Rebuild selected or all BIM groups from saved parameters. Normalizes accidental group Scale transformations to unit axes. The separate **Repair after native Scale** command adopts new horizontal footprints while preserving wall thickness, window and door widths, heights and frame dimensions. If a wall is too short for its hosted openings, the repair stops with an error instead of silently corrupting the cutout. Both actions use SketchUp Undo transactions.
2. **Door graphics:** Plan arcs live on a dedicated dashed Tag with a separate solid leaf Tag. Elevation opening indicators now use two diagonals of equal height, forming a wedge pointing to the hinge or handle edge. All symbols remain independently controllable through native Tags and line styles. Symbol conventions differ internationally; the marker direction can be changed in opening Properties.
3. **Double casement windows:** Default two panels. Outer frame 50 mm, sash/inner frame 30 mm, glazing thickness 3 mm, separately editable from the host wall. Supports 1–4 panels and per-pane elevation direction markers.
4. **Live structural placement:** The Column tool now shows a full 3D ghost preview at the cursor and places on a click, with center, left-face, or right-face anchors. Beam baselines use left, center or right reference lines, as walls do. Empty-model story-plane intersection is supported when SketchUp has no pickable face.
5. **Stairs:** Straight and U-return with central landing. Adjustable total rise, riser count, width, landing length, U gap, and available run length. A U flight requires at least four risers; the plugin rejects an impossible landing length. This is **mass-modeling geometry**, not a checked code-compliant stair or railing generator.
6. **Roofs:** Adds a rectangular hip roof in addition to a rectangular gable roof. Gable roofs can create roof-attached wall infill at both end elevations to cover the gable space above wall heads. Roof infill has its own Tag. A separate suspended-ceiling element, irregular outline tracing and complex valleys/junctions are not implemented yet.
7. **Properties auto-focus:** Selecting an ArchiBIM group automatically switches the BIM Manager to Properties. Selecting a wall shows its hosted openings.
8. **Diagnostics:** Local JSONL log records important element creations, edits, Scale-repair operations, errors, and SketchUp transaction undo/redo. Diagnostics tab exports the session log with model-level dimensions and transform scale factors into a single text file for bug reporting. Nothing is uploaded automatically.

## How to test

1. **Restart SketchUp** after replacing the RBZ to ensure Ruby modules are loaded from the updated plugin version. The plugin badge should read `v0.4.0`.
2. Draw a 20' × 20' slab with `20',20'` in the SketchUp Measurements field, add three walls and check corner joins.
3. Place a door and double-casement window from Top/Plan; select the host wall and verify both the plan Tags and elevation Tags separately. In the Tags tab, set dashed lines or hide them.
4. Edit wall thickness, press **Apply changes + rebuild**, then use SketchUp Undo and Redo to confirm the change is reversible.
5. Use SketchUp Scale to shorten a single wall, then **Diagnostics → Repair selected after Scale**. Confirm thickness and hosted door/window dimensions are unchanged; the total wall length should update to the scaled size.
6. Hover a column to see the ghost outline, click to insert, test reference anchor positions. Draw a beam, test its three reference lines.
7. Generate a straight stair, switch to U-return, set rise 3000 mm, and check landing appearance and geometry. Generate rectangular gable and hip roofs; test gable infill from the wall end view.
8. **Diagnostics → Export ArchiBIM testing log**, then send the text output with any screenshot/error description.

## Known limitations

- Auto-rejoin supports basic 2-wall miter and T-butt connections, not multiwall intersections.
- Native Scale does not trigger automatic synchronization; repair is an explicit undoable action. Scaling an entire house with mixed group nesting may require individual repairs or rebuilding. Directly editing mesh vertices is unsupported.
- Roof infill and U-stair geometry need real in-SketchUp visual/regression testing, and roof/wall assemblies have no automatic join/cut with neighboring roof groups.
- Complex traced roof footprints, arbitrary roof intersections/valleys, true ceiling family, stair railings, window opening-specific 2D detail levels, and associative CAD drawings remain future work.
- IFC export uses SketchUp's native exporter when supported; IFC semantics still require independent model validation.

## Relevant design and API references

- [SketchUp Ruby SelectionObserver](https://ruby.sketchup.com/Sketchup/SelectionObserver.html)
- [SketchUp Ruby ModelObserver](https://ruby.sketchup.com/Sketchup/ModelObserver.html)
- [Vectorworks Door 2D/3D visualization and hinge markers](https://app-help.vectorworks.net/2026/eng/VW2026_Guide/DoorWindow/Door_settings.htm)
- [Vectorworks Window sash and hinge markers](https://app-help.vectorworks.net/2026/eng/VW2026_Guide/DoorWindow/Window_settings.htm)
- [Revit Component Stair design](https://help.autodesk.com/cloudhelp/2027/ENU/RevitLT-ArchDes/files/GUID-7EBB3572-176C-4AC4-A841-48CCA7E742F5.htm)
