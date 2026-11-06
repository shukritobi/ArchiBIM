# ArchiBIM 0.7.0

**A practical parametric architecture/BIM extension for SketchUp Desktop**  
Built by SS Digital Lab · 6 November 2026

ArchiBIM makes architectural objects editable in SketchUp and stores BIM properties on the model. It is **an early functional prototype**, **not complete Revit or Archicad feature parity**, and has **not yet been runtime-tested inside SketchUp Desktop**. Make a backup before installing or testing on a real project.

## Install

1. Open **SketchUp Desktop** (recommended: SketchUp Pro 2024–2026 on Windows; other recent desktop versions may work but have not been tested). The SketchUp web version cannot run Ruby extensions.
2. Go to **Extensions → Extension Manager → Install Extension**.
3. Select `ArchiBIM_latest.rbz`.
4. Find **Extensions → ArchiBIM → ArchiBIM BIM Manager** or the **ArchiBIM** toolbar button.
5. Start in a new test model and choose **Create demo model**, then select a wall and visit the **Properties** tab.

If SketchUp disallows the unsigned extension, review your Extension Manager loading policy. Only relax it for software you trust. You can inspect all the supplied Ruby and HTML source first.

## What is implemented

| Feature | What it does |
|---|---|
| Straight walls | Left, center or right reference lines; graph-backed linked corners / T intersections and selectively enabled miter/butt cleanup |
| Associative wall moves | One-hop Move Connected Wall tool with a ghost preview and exact VCB displacement, no wall thickness or height scaling |
| Link / Join only / Unlink | Per-junction connection mode, Unlink Entire Wall, Reconnect nearby, auto-join toggle and persistent disabled state |
| Hosted doors and windows | Hinged doors, casement windows and 2–4 panel sliding doors, with live cursor previews, inspector-driven mouse repositioning and exterior/interior flush mounting |
| Slabs | Rectangular slabs, typed VCB dimensions, automatically linked stairwell cutouts when the stair lands on the slab level, with net area and volume |
| Columns | Ghost-preview column placement with center, left or right reference anchors |
| Beams | Draw straight beams with selectable left/center/right reference lines, width/depth and elevation offset |
| Stairs | Straight or U-return flights with adjustable rise, risers, landing, handrails and an upper-slab auto-cut option |
| Room zones / four-wall room | Area-only zones, plus a two-corner tool that creates four individually editable BIM walls and optional room-area zone |
| Roofs | Rectangular gable/hip roof families; pitch, eaves, thickness, optional gable-end wall infill |
| Pad footings | Parametric rectangular concrete pad footing |
| Stories / levels | Add, rename, raise/lower levels; associated model objects move with changed elevation |
| BIM metadata | Persistent IDs, labels, codes, notes, type, level, dimension parameters and native Tags |
| Cut plan scenes | Create named orthographic scenes using a SketchUp section plane at level +1200 mm |
| Quantity schedules | Length, gross/net wall areas, floor/roof areas, volumes, hosted opening counts, editable example cost rates |
| Export | CSV schedule, JSON model data, SketchUp native IFC export where supported |
| View controls | One-click perspective reset fitted to all ArchiBIM elements |
| Undo / diagnostics | Undoable BIM edits, model transaction logs, exportable local testing report |

Each model object is a SketchUp group with an `SSDigitalLab_ArchiBIM` attribute dictionary, plus a tag named `AB | ...`. All stored geometry dimensions are **millimetres**; quantities report metres/m²/m³. Costs in the UI are **illustrative RM estimates**, not verified material or construction prices.

## 0.7.0 associative wall connections

**[v0.7 release notes](docs/V0_7_RELEASE_NOTES.md)** · **[SketchUp test checklist](docs/V0_7_TEST_CHECKLIST.md)** · [v0.6 release notes](docs/V0_6_RELEASE_NOTES.md)

A 20 × 70 ft rectangular room can become 20 × 80 ft by moving the south wall 10 ft with the new connected-move tool. Directly linked east/west walls extend while keeping thickness, height, door/window sizes and BIM identities. Links are persisted in SKP model attributes. Each connection can be Linked, Join Only or Unlinked; unlinking an entire wall also suppresses future automatic connections until manually re-enabled. **Native SketchUp Move still does not propagate these links**. Only this dedicated tool updates wall reference lines atomically. Slabs, roofs and rooms do not follow yet.

This build passed automated pure-Ruby tests but still requires SketchUp desktop acceptance testing.

## Getting started

1. **Draw walls:** In Build, choose `Wall`; click first and second points. Connected wall lines continue from the last endpoint. Choose Wall to open its dedicated creation parameters and change height/thickness before drawing, or select a wall and edit those fields in Properties afterward.
2. **Move connected walls:** Select a wall → Properties → **Move connected wall**. Click a reference point, move perpendicular to the wall and click to confirm, or type `10'`, `3048mm`, `-10'` in SketchUp Measurements. Linked neighboring wall endpoints follow. Set each junction in the **Associative Wall Connections** section to Linked / Join Only / Unlinked, or use **Unlink entire wall** and **Detect / reconnect nearby**. The Build panel has an Auto-Join checkbox.
3. **Insert door/window/sliding door:** Choose a hosted opening and hover a wall; click when the green ghost preview is valid. The plugin clamps at wall endpoints and checks overlaps. Select the wall in **Properties → Hosted Components → Move on wall** to position an existing opening interactively (click to confirm). Choose frame placement: Center, Flush exterior or Flush interior; assign the wall exterior face in Wall Properties.
4. **Levels:** Add stories in the Levels tab. Select the target story from Build; new geometry is created at that level's elevation. Updating a level height moves its assigned ArchiBIM groups.
5. **Other geometry:** Slab, room, 4-wall room, footing, gable roof and rectangular hip roof use two diagonal footprint corners. Beam and stair use two points along their run. Column follows the cursor with a live ghost preview and inserts at the clicked position.
6. **Stairwell:** Select a stair in Properties and check **Automatically cut the upper-floor slab**. The stair endpoint elevation must match the slab top within 150 mm. Optionally set the stairwell clearance. For pre-existing stairs, click **Diagnostics → Sync stairwell holes** once. Native moving may require this sync command.
7. **Camera:** Click **Fit whole house · Perspective** at the top of Build.
8. **Schedules:** Quantities show a model summary and per-element breakdown. Export CSV / JSON in Export.
9. **Drawings:** Use **Create +1200 mm cut plan scene**. You can refine the scene styles, section fills and annotate in SketchUp/LayOut.
10. **IFC:** Load the appropriate IFC classification schema for SketchUp if available. Export from the panel and validate **all classes, property values, and geometry** in an independent IFC viewer.

## Editing rules

- To change parameters (size, pitch, story, height), use **ArchiBIM → Properties**. To resize a full house footprint without altering wall thickness or hosted opening size, use **Resize BIM footprint** in Export. Native SketchUp Scale automatically schedules a **separate repair pass** after mouse release (enabled by default); turn off the protection if needed. You can also run **Repair selected after Scale** in Diagnostics to adopt the new footprint without scaling thickness, frames or openings; **Rebuild selected** restores saved dimensions.
- Native SketchUp Move/Rotate preserve most element transformations but **do not propagate linked walls**. Use Move Connected Wall for associative edits; native edits can break graph junctions. Reconnections are explicit. **Explode and direct vertex edits** sever the intended parametric workflow; after native Scale, verify the auto-repair or repair the group in Diagnostics if unsupported.
- Editing a hosted wall regenerates its child door/window graphics. Do not manually add valuable geometry inside the BIM wall group; these child entities are replaced on regeneration.
- Creating BIM elements while inside a nested group is not supported by the drawing tools. Work at the model root, or move the finished groups afterward.
- When level names change, ArchiBIM retags only its own elements. Empty prior Tags may remain in SketchUp and may be removed manually.
- A placed wall uses a **left/center/right reference baseline**. Corners and single-branch T-junction trims are graph-backed. Multi-way and collinear junctions remain unsupported.

## Limits and known gaps

**This is not yet a full commercial BIM product**. The following are NOT implemented: generalized/multi-way wall joins, multilayer / curved walls; compound sections/material assemblies; native family editor and constraints engine; hosted MEP; arbitrary non-rectangular/manual slab cutouts and roof holes; true georeferenced site modeling; ceiling objects; automatic room boundary detection; production-ready stair railing families and complex stair types; curtain walls; linked dimensions and construction documentation; native `.rvt` or `.pln` import/export; lossless IFC round-tripping; instantaneous correction while SketchUp Scale is being dragged, or automatic repair of arbitrary direct mesh edits; multiuser collaboration; clash detection; and performance optimization for very large projects.

Native IFC export is **edition-, version- and schema-dependent**. An `IfcWall` label in the plugin's attributes is not proof that a third-party BIM application will read the same semantic or parameter structure. IFC export requires independent validation.

## Package layout

```text
ArchiBIM.rb              SketchUp Extension Manager entrypoint
archibim/main.rb         commands, model storage, wall graph integration, editing, schedules, export
archibim/wall_graph.rb   persistent wall constraints, safe associative movement math
archibim/connected_move.rb interactive plan movement / VCB tool
archibim/core.rb         testable pure-Ruby validation and quantities
archibim/geometry.rb     solid geometry generation, hosted cutouts and materials
archibim/tools.rb        viewport drawing, ghost previews and hosted insertion
archibim/repair.rb       native Scale normalization and data reconciliation
archibim/diagnostics.rb  structured local logs and export
archibim/ui/panel.html   HTML/CSS/JS BIM manager
archibim/ui/toolbar_*.png
```

The separate **source archive** contains these files plus `docs/`, test suite and this README.

## Run calculation tests (outside SketchUp)

Requires Ruby with Minitest:

```sh
ruby -e 'Dir["test/test_*.rb"].sort.each { |f| require_relative f }'
```

These tests cover wall connectivity, unlink persistence, shortening validation, world-position opening anchoring, graph-mediated cleanup, geometry areas, stairs, roof, footing and cost rules. SketchUp viewport geometry and IFC export require **manual testing in SketchUp**. For regression tests inside SketchUp consider [SketchUp TestUp](https://github.com/SketchUp/testup-2).

## First acceptance test in SketchUp

Use an empty SKP file. Create the demo. Verify that:

1. Four walls, one slab, a door and window appear and select correctly.
2. Selecting a wall shows its parameters and two hosted opening edits where applicable.
3. Changing wall height from 3000 to 2700 mm rebuilds the group without losing an opening.
4. Repositioning a window from offset 2500 to 2300 mm changes its cutout.
5. Quantities show a wall net area corresponding to its openings.
6. Generating a floor plan scene shows a cut at story +1200 mm.
7. Exports produce CSV and JSON files and IFC if the installed SketchUp edition supports it.
8. Undo and Redo work for changes.

After testing, export **Diagnostics → Export ArchiBIM testing log** and send the generated text file and relevant screenshots. The exact runtime interaction remains unverified until tested in the target program.

## License

The provided original source code is released under the MIT License; see `LICENSE.txt` in the source bundle. There are no third-party plugin dependencies. Research references are used for workflow comparison only; their commercial source code was not copied.
