# ArchiBIM 0.4.0

**A practical parametric architecture/BIM extension for SketchUp Desktop**  
Built by SS Digital Lab · 5 November 2026

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
| Straight walls | Left, center or right reference lines; automatically calculate two-wall miters and tee butt joins on plugin changes |
| Hosted doors and windows | Green/red placement preview in plan and elevation, hinge/swing settings, separate 2D plan/elevation symbols and Tags |
| Slabs | Rectangular slabs, typed VCB dimensions such as `20',70'`, with computed area in SketchUp model units |
| Columns | Ghost-preview column placement with center, left or right reference anchors |
| Beams | Draw straight beams with selectable left/center/right reference lines, width/depth and elevation offset |
| Stairs | Straight or U-return flights with adjustable total rise, risers, landing and flight gap |
| Room zones | User-drawn rectangular area zone with label and floor-area schedule |
| Roofs | Rectangular gable/hip roof families; pitch, eaves, thickness, optional gable-end wall infill |
| Pad footings | Parametric rectangular concrete pad footing |
| Stories / levels | Add, rename, raise/lower levels; associated model objects move with changed elevation |
| BIM metadata | Persistent IDs, labels, codes, notes, type, level, dimension parameters and native Tags |
| Cut plan scenes | Create named orthographic scenes using a SketchUp section plane at level +1200 mm |
| Quantity schedules | Length, gross/net wall areas, floor/roof areas, volumes, hosted opening counts, editable example cost rates |
| Export | CSV schedule, JSON model data, SketchUp native IFC export where supported |
| Undo / diagnostics | Undoable BIM edits, model transaction logs, exportable local testing report |

Each model object is a SketchUp group with an `SSDigitalLab_ArchiBIM` attribute dictionary, plus a tag named `AB | ...`. All stored geometry dimensions are **millimetres**; quantities report metres/m²/m³. Costs in the UI are **illustrative RM estimates**, not verified material or construction prices.

## 0.4 updates and limitations

**[Read v0.4 release notes](docs/V0_4_RELEASE_NOTES.md).** Includes double-casement windows, wedge elevation markers, center/left/right structural placement previews, two staircase families, hip roofs, gable-end infill, inspector auto-focus, scaled-group repair and diagnostics. The geometry join solver is still limited and desktop validation remains required. The stable direct RBZ URL after GitHub deployment is `https://raw.githubusercontent.com/shukritobi/ArchiBIM/main/dist/ArchiBIM_latest.rbz`.

## Getting started

1. **Draw walls:** In Build, choose `Wall`; click first and second points. Connected wall lines continue from the last endpoint. Change height/thickness under Build presets before drawing, or select a wall and edit those fields in Properties afterward.
2. **Insert door/window:** Choose `Door` or `Window` and hover a wall and click once the green ghost preview is valid, including in top/plan views. The plugin finds the host wall and creates a rectangular void. To specify precise offsets and widths, select the wall and edit Hosted Components in Properties.
3. **Levels:** Add stories in the Levels tab. Select the target story from Build; new geometry is created at that level's elevation. Updating a level height moves its assigned ArchiBIM groups.
4. **Other geometry:** Slab, room, footing, gable roof and rectangular hip roof use two diagonal footprint corners. Beam and stair use two points along their run. Column follows the cursor with a live ghost preview and inserts at the clicked position.
5. **Schedules:** Quantities show a model summary and per-element breakdown. Export CSV / JSON in Export.
6. **Drawings:** Use **Create +1200 mm cut plan scene**. You can refine the scene styles, section fills and annotate in SketchUp/LayOut.
7. **IFC:** Load the appropriate IFC classification schema for SketchUp if available. Export from the panel and validate **all classes, property values, and geometry** in an independent IFC viewer.

## Editing rules

- To change parameters (size, pitch, story, height), use **ArchiBIM → Properties**. To resize a full house footprint without altering wall thickness or hosted opening size, use **Resize BIM footprint** in Export. After native SketchUp Scale, run **Repair selected after Scale** in Diagnostics to adopt the new footprint without scaling thickness, frames or openings; **Rebuild selected** restores saved dimensions.
- Native SketchUp Move/Rotate preserve most element transformations but junctions need manual **Recalculate wall junctions** after a Move. **Explode and direct vertex edits** sever the intended parametric workflow; after native Scale, explicitly repair the group in Diagnostics.
- Editing a hosted wall regenerates its child door/window graphics. Do not manually add valuable geometry inside the BIM wall group; these child entities are replaced on regeneration.
- Creating BIM elements while inside a nested group is not supported by the drawing tools. Work at the model root, or move the finished groups afterward.
- When level names change, ArchiBIM retags only its own elements. Empty prior Tags may remain in SketchUp and may be removed manually.
- A placed wall uses a **left/center/right reference baseline**. Basic two-wall miters and single-branch T-junction trims are automatically calculated on plugin edits. Multi-way and collinear junctions remain unsupported.

## Limits and known gaps

**This is not yet a full commercial BIM product**. The following are NOT implemented: generalized/multi-way wall joins, multilayer / curved walls; compound sections/material assemblies; native family editor and constraints engine; hosted MEP; slab/roof holes; true georeferenced site modeling; ceiling objects; automatic room boundary detection; automatic stair railings and complex stair types; curtain walls; linked dimensions and construction documentation; native `.rvt` or `.pln` import/export; lossless IFC round-tripping; automatic real-time synchronization after arbitrary native SketchUp Scale or mesh edits; multiuser collaboration; clash detection; and performance optimization for very large projects.

Native IFC export is **edition-, version- and schema-dependent**. An `IfcWall` label in the plugin's attributes is not proof that a third-party BIM application will read the same semantic or parameter structure. IFC export requires independent validation.

## Package layout

```text
ArchiBIM.rb              SketchUp Extension Manager entrypoint
archibim/main.rb         commands, model storage, parameter edit, schedules, export
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

These tests cover default values, wall/opening geometry area, overlap restrictions, dimensions, stairs, slab, roof, footing, cost rules. SketchUp viewport geometry and IFC export require **manual testing in SketchUp**. For regression tests inside SketchUp consider [SketchUp TestUp](https://github.com/SketchUp/testup-2).

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
