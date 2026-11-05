# ArchiBIM v0.5.0 | SketchUp 2026 QA release

**5 November 2026.** Based on user screenshots and the `ArchiBIM_Testing_Log.txt` session report from SketchUp 26.0.429.

## Primary regression fix: Properties and Levels

The exported log repeatedly recorded `NoMethodError: undefined method 'to_f' for true:TrueClass` from `main.rb:882` inside `panel_payload`. An unrelated Boolean family setting entered the list of formatted dimensions, preventing *all* UI refreshes. The revised payload formats numeric dimensions only. A selected BIM element now sends its data to the inspector; levels are populated from model attributes and the active story ID is persisted on the model.

Adding a level selects the new level, updating the working-level selector. Updating a level elevation moves the assigned ArchiBIM group origins. Changing an element's assigned level from Properties moves it to the selected elevation and retags it. Level changes are logged in the testing report. This is not the same as Revit's fully constrained top/bottom level association; connected wall top constraints remain a future feature.

## Parametric creation palette

The Build tab now changes to a dedicated element creation inspector when a tool is selected. Each family (wall, door, window, slab, column, beam, stair, roof, pad footing, room) has separate fields. A `change` event persists the field to model-level defaults through SketchUp's HTML-to-Ruby bridge. Viewport ghost previews are invalidated when settings update. `All tools` returns to the tool picker and `Start placing this element` restarts the current tool.

Window panels, roof shape, roof pitch, eave offset, gable closure, stairs/landing/railings and wall alignment are no longer one large family preset form. Existing placed elements retain their instance parameters unless edited explicitly.

## After-Scale shape protection

A model transaction observer schedules a **separate, undoable repair** after native SketchUp Scale commits. It reads per-group local scale factors and reconstructs the BIM shape from metadata, adopting new wall/beam lengths or slab/roof footprints while maintaining wall thickness, floor-to-floor height, glazing, door/window sizes and structural sections. It cannot change SketchUp Scale's live drag (temporary deformation is visible until mouse release), and very heavy shears/collapsed geometry are logged rather than forced. `Auto repair after Scale` is enabled by default and can be disabled in Build. Native Undo/Redo callbacks do not force repair, preserving Undo control.

If a wall becomes shorter than a hosted opening can fit, auto repair declines that element and records a diagnostic error rather than silently clipping a door/window. `Diagnostics → Repair selected after Scale` remains available.

## Architectural elements

- Stairs use an actual 2D flight profile extruded to width, with horizontal treads, vertical risers and **continuous inclined structural underside** (rather than full-height cuboid steps). For an N-riser flight, the stair uses N-1 independent treads and assumes the upper floor is the final walking surface. Adjustable straight and U-turn modes, landing, 150 mm waist (default), or open treads. Simple 3D handrails and posts can be set left, right, both or none. Riser/tread warning calculations are advisory, **not Malaysian building code sign-off**.
- Roof type now selects hip or gable immediately through the active roof-tool panel. Rectangular hips produce four pitched roof faces, including short hips or a central ridge depending on aspect ratio. Live preview shows ridge and hip lines before placement. Complex roof footprints remain unsupported.
- Window elevation dashed lines follow the actual computed **glazing clear area** after outer/sash frame clamping. On double casements, each marker is contained within its own pane instead of extending past it.
- Column, beam, wall, stair and roof previews use current tool settings and the active level.

## Testing performed outside SketchUp

Ruby syntax checks, HTML embedded JavaScript parsing, and **35 Ruby tests / 101 assertions** pass locally. Includes 5 new tests for stair profiles, riser/tread calculations, U layouts, and Boolean settings. GitHub Actions tests the same suite and repackages the RBZ.

**Not tested yet:** interactions in a live SketchUp 2026 session; handrail visual proportions at every stair configuration; complex simultaneous native Scale with rotated and sheared objects; irregular multi-wall junctions; independent IFC interoperability. Back up SKP files and test on a duplicate.

## Acceptance checklist

1. Open `ArchiBIM BIM Manager` and verify `v0.5.0` in the header.
2. Create a second level (e.g. `First Floor` 3000mm or another unique level), select it in Build, and draw a slab; its base should be at the chosen elevation.
3. Select an old wall. Properties should appear immediately with length, height, thickness and assigned level. Switch its level and apply.
4. Draw a wall, Scale it shorter with SketchUp's native Scale, release the mouse, and verify thickness/height return to original specification while length changes.
5. Select the stair tool, choose a straight 18-riser layout, 3000 mm rise, 4500 mm run; verify the soffit is inclined, not a full-height wall. Test handrails and U-return separately.
6. Select Roof and switch to Hip without leaving the tool panel. Observe a four-slope roof preview and place it on a rectangular footprint.
7. Create a double window and view from elevation. Dashed markers should sit inside each clear glass pane.
8. Export a testing log if any discrepancy remains. The log now includes active level and level records.

Direct latest RBZ (when GitHub is updated): https://raw.githubusercontent.com/shukritobi/ArchiBIM/main/dist/ArchiBIM_latest.rbz
