# ArchiBIM 0.2.0

**A practical parametric architecture/BIM extension for SketchUp Desktop**  
Built by SS Digital Lab · 4 November 2026

ArchiBIM makes architectural objects editable in SketchUp and stores BIM properties on the model. It is **an early functional prototype**, **not complete Revit or Archicad feature parity**, and has **not yet been runtime-tested inside SketchUp Desktop**. Make a backup before installing or testing on a real project.

## Install

1. Open **SketchUp Desktop** (recommended: SketchUp Pro 2024–2026 on Windows; other recent desktop versions may work but have not been tested). The SketchUp web version cannot run Ruby extensions.
2. Go to **Extensions → Extension Manager → Install Extension**.
3. Select `ArchiBIM_v0.2.0.rbz`.
4. Find **Extensions → ArchiBIM → ArchiBIM BIM Manager** or the **ArchiBIM** toolbar button.
5. Start in a new test model and choose **Create demo model**, then select a wall and visit the **Properties** tab.

If SketchUp disallows the unsigned extension, review your Extension Manager loading policy. Only relax it for software you trust. You can inspect all the supplied Ruby and HTML source first.

## What is implemented

| Feature | What it does |
|---|---|
| Straight walls | Draw center-to-side wall volumes in two clicks, edit length/height/thickness, geometry rebuilds |
| Hosted doors and windows | Click an ArchiBIM wall, create a rectangular void with frame + slab/glass visual, update offset/sill/width/height, rebuild host |
| Slabs | Rectangular parametric concrete slabs |
| Columns | Place vertical rectangular columns at the view target |
| Beams | Draw straight beams with adjustable width/depth/elevation offset |
| Stairs | Straight-run staircase profiles, adjustable run/width/rise/step count |
| Room zones | User-drawn rectangular area zone with label and floor-area schedule |
| Gable roofs | Simple two-slope parametric roof, pitch, thickness, offset and overhang |
| Pad footings | Parametric rectangular concrete pad footing |
| Stories / levels | Add, rename, raise/lower levels; associated model objects move with changed elevation |
| BIM metadata | Persistent IDs, labels, codes, notes, type, level, dimension parameters and native Tags |
| Cut plan scenes | Create named orthographic scenes using a SketchUp section plane at level +1200 mm |
| Quantity schedules | Length, gross/net wall areas, floor/roof areas, volumes, hosted opening counts, editable example cost rates |
| Export | CSV schedule, JSON model data, SketchUp native IFC export where supported |
| Undo | Main geometry edits, hosted openings and level elevation changes use SketchUp undo transactions |

Each model object is a SketchUp group with an `SSDigitalLab_ArchiBIM` attribute dictionary, plus a tag named `AB | ...`. All stored geometry dimensions are **millimetres**; quantities report metres/m²/m³. Costs in the UI are **illustrative RM estimates**, not verified material or construction prices.

## Getting started

1. **Draw walls:** In Build, choose `Wall`; click first and second points. Connected wall lines continue from the last endpoint. Change height/thickness under Build presets before drawing, or select a wall and edit those fields in Properties afterward.
2. **Insert door/window:** Choose `Door` or `Window` and click the face of an ArchiBIM wall. The plugin finds the host wall and creates a rectangular void. To specify precise offsets and widths, select the wall and edit Hosted Components in Properties.
3. **Levels:** Add stories in the Levels tab. Select the target story from Build; new geometry is created at that level's elevation. Updating a level height moves its assigned ArchiBIM groups.
4. **Other geometry:** Slab, room, footing and gable roof use two diagonal footprint corners. Beam and stair use two points along their run. Column currently inserts at the camera target, then can be moved with SketchUp's Move tool.
5. **Schedules:** Quantities show a model summary and per-element breakdown. Export CSV / JSON in Export.
6. **Drawings:** Use **Create +1200 mm cut plan scene**. You can refine the scene styles, section fills and annotate in SketchUp/LayOut.
7. **IFC:** Load the appropriate IFC classification schema for SketchUp if available. Export from the panel and validate **all classes, property values, and geometry** in an independent IFC viewer.

## Editing rules

- To change parameters (size, pitch, story, height), use **ArchiBIM → Properties**, not SketchUp's native Scale tool.
- Native SketchUp Move/Rotate preserve most element transformations. **Explode / vertex edits / nonuniform Scale** sever the intended parametric workflow.
- Editing a hosted wall regenerates its child door/window graphics. Do not manually add valuable geometry inside the BIM wall group; these child entities are replaced on regeneration.
- Creating BIM elements while inside a nested group is not supported by the drawing tools. Work at the model root, or move the finished groups afterward.
- When level names change, ArchiBIM retags only its own elements. Empty prior Tags may remain in SketchUp and may be removed manually.
- A placed wall is defined by a **straight center baseline**. **Automatic junction trimming** is not yet implemented; two walls can overlap at corner intersections.

## Limits and known gaps

**This is not yet a full commercial BIM product**. The following are NOT implemented: automatically joined / multilayer / curved walls; compound sections/material assemblies; native family editor and constraints engine; hosted MEP; slab/roof holes; true georeferenced site modeling; ceiling objects; automatic room boundary detection; stair landings/railings; curtain walls; linked dimensions and construction documentation; native `.rvt` or `.pln` import/export; lossless IFC round-tripping; synchronized quantity reporting after arbitrary native SketchUp Scale or mesh edits; multiuser collaboration; clash detection; and performance optimization for very large projects.

Native IFC export is **edition-, version- and schema-dependent**. An `IfcWall` label in the plugin's attributes is not proof that a third-party BIM application will read the same semantic or parameter structure. IFC export requires independent validation.

## Package layout

```text
ArchiBIM.rb              SketchUp Extension Manager entrypoint
archibim/main.rb         commands, model storage, parameter edit, schedules, export
archibim/core.rb         testable pure-Ruby validation and quantities
archibim/geometry.rb     solid geometry generation, hosted cutouts and materials
archibim/tools.rb        viewport drawing and opening insertion tools
archibim/ui/panel.html   HTML/CSS/JS BIM manager
archibim/ui/toolbar_*.png
```

The separate **source archive** contains these files plus `docs/`, test suite and this README.

## Run calculation tests (outside SketchUp)

Requires Ruby with Minitest:

```sh
ruby test/test_core.rb
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

Please send the first SketchUp error, if one appears, along with your SketchUp version. The exact runtime interaction remains unverified until tested in the target program.

## License

The provided original source code is released under the MIT License; see `LICENSE.txt` in the source bundle. There are no third-party plugin dependencies. Research references are used for workflow comparison only; their commercial source code was not copied.
