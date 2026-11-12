# ArchiBIM v0.8.1 · Wall joints, SketchUp Scale and doorless passages

**12 November 2026** · Bug-fix preview for SketchUp 2026. After merge, this build is published through the automated latest-RBZ workflow.

## What failed in the screenshot

The screenshot error **`ArchiBIM error: Invalid auto_wall_join`** is reproducible in the code. `Core::DEFAULTS` declared `auto_wall_join = true`, but `Core.settings` forgot to include `auto_wall_join` among Boolean keys. When ArchiBIM checked its connection settings, it called `Float(true)`, which raised an argument error and prevented the rest of the join scan from running. Because the ModelObserver also checks settings before scheduling repair, this could also disrupt Scale repairs. This is fixed and has a regression test with the normal saved Boolean forms.

### Wall contacts and junctions

ArchiBIM already has a graph-based corner/T-junction detector. Its T-junction scanner considers the *physical face* of the host wall according to the host alignment (Left/Center/Right) rather than only its construction reference line. A regression test covers an external wall aligned at its left face and a later interior wall endpoint stopping at its physical wall face (150 mm offset).

**What it does not do:** Automatic detection tolerates small geometric gaps only (approximately 10 mm), avoids ambiguous multiple matches and does not extend/snap a wall through an arbitrary gap or connect across levels. These exclusions protect the drawing from unexpected wall movement. The diagnostics graph audit includes near misses, as well as intentional Unlinked and Join Only states.

**Test in SketchUp Desktop**: Draw one 8000 mm external wall, 150 mm thick, Left face aligned. Draw an internal 4000 mm wall ending on either physical side face of the external wall, using the same floor level. Press **Build → Scan all walls**. Select the interior wall and check Properties to confirm `Linked` and `Touching`. Try **Move connected wall** on a test copy. If the walls merely appear to intersect in 3D while the actual reference endpoint is more than the tolerance away, inspect the diagnostics world coordinates, alignments and nearby gap entries.

## Native Scale repair

The [SketchUp developer guide to parametric objects](https://developer.sketchup.com/article-making-a-parametric-object) recommends reading a group's 4×4 transformation, retaining its translation/rotation, extracting Scale from both axis vector magnitudes and the homogeneous matrix term, and rebuilding parametric geometry after Scale ends. A model transaction observer is also documented to fire *after commit*, not during the gesture: [Sketchup::ModelObserver](https://ruby.sketchup.com/Sketchup/ModelObserver.html).

v0.8.1 now:
- Uses the full matrix when supported to extract Scale, with a fallback for test doubles;
- Registers a Scale Tool state observer alongside the existing model-transaction callback;
- Performs repair in a deferred operation, never mutating inside `onTransactionCommit`;
- Preserves wall thickness, hosted opening sizes and other parameter-dependent dimensions;
- Logs each chosen repair plan and rejected candidate so failed repairs are not silent;
- Exports full model element transformation matrices and extracted Scale factors in the local testing log.

**Known constraints**: Directly scaling a nested wall's *raw edges* is not a parametric operation and can be undone by later rebuild. Unsupported collapsed/near-singular transforms are rejected instead of reshaped. Freehand 3D group edits and multi-wall constraints still need geometric acceptance tests. Use **Export → Resize BIM footprint** for proportional complete-building resizing where preserving wall widths and hosted opening sizes is important.

### Manual Scale test

1. Make a **copy** of a SKP model. Restart SketchUp after updating the RBZ.
2. Select one ArchiBIM wall **group** (not its internal faces/edges). Switch to SketchUp's native Scale tool.
3. Drag only along wall length (local X). Verify the group is automatically regenerated once you release the handle. Check new length, old 150 mm thickness, unchanged door/window width and saved opening offsets.
4. Undo and Redo once and recheck the dimensions. Repeat on a slab, a rotated wall, a roof and a copied two-storey test model.
5. If nothing changes, choose **Diagnostics → Repair selected after Scale** or export the full testing log. It includes each group matrix and both the current and rejected repair decisions.

## Doorless opening / passage

A door's stored opening has an optional `leafless` Boolean, default `false` for backwards compatibility. The wall cutout is driven by the same validated opening width, height, offset and sill as a regular door. Switching `leafless` on leaves those properties and the persistent opening ID intact.

- **Create**: select Door tool, enable `Open passage (no door or frame)`; or select a wall in Properties and choose `Add opening → Open passage (no door)`.
- **Convert**: select the parent wall → Properties → Hosted components → door → `Open passage: no frame / no leaf` → `Update opening`. Uncheck the same toggle to rebuild the door.
- **3D**: only the opening remains, no door leaf, outer frame, head, jambs or threshold profile.
- **SketchUp 2D**: dashed plan opening rectangle spanning the actual wall face thickness and a dashed elevation opening rectangle, tagged separately as `AB | 2D | ... | Open Passage | <level>`.
- **DXF**: the existing opening layer `AB_2D_OPENINGS` receives the dashed four-edge footprint instead of a door swing polyline.
- **Quantities**: a doorless opening reduces wall net area in the same way as a regular opening, but contributes no door unit rate.
- **IFC**: `IfcOpeningElement` is written as the nested opening hint where the model's IFC schema supports it. IFC exports still require independent validation.

## Test status and limits

Ruby tests check the exact Boolean settings regression, host-face T-junction geometry, matrix-based Scale factor extraction and cost/cutout consistency for doorless passages. CI also checks Ruby syntax, basic UI JavaScript syntax, and installer packaging. **No assertion is made that CI executes SketchUp's 3D viewport or its native Scale interaction.** This requires testing in SketchUp Desktop 2026.

After test results, use **Diagnostics → Export ArchiBIM testing log** and attach the exported TXT, relevant screenshots, and a minimal reproducible model to an issue. That log includes model levels, wall reference lines, graph relations, raw transformation matrices and session events.
