# Scan-to-BIM: iPad Scan-to-Design -> ArchiBIM + ArchiBIM Joinery

Status: **research and read-only discovery implemented on a feature branch; conversion NOT implemented or validated** (13 Nov 2026).

## Reference project

Google Drive: `3DExpress Bambulabs/4 Setapak/3 3D`.

- `Bambulabs_MakerWorld_Setapak_Central_scan.skp` (370,255,524 bytes)
- `Bambulabs_MakerWorld_Setapak_Central_V7.skp` (272,595,982 bytes)
- `Bambulabs_MakerWorld_Setapak_Central_SITE.skp` (141,339 bytes)

The scan SKP has been **located, but its internal geometry and tag structure have not yet been inspected inside SketchUp**. The audit tool produces those observations on a real model. Do not write assumed Setapak tag names, counts, dimensions or conversion success into QA results.

## Source-specific behaviour

SketchUp iPad Scan-to-Design produces:
- **Canvas:** optional simplified planar surfaces plus triangulated and optionally textured meshes; often large, noisy, and unsuitable as parametric walls without geometry fitting.
- **Apple RoomPlan:** orthogonal SketchUp edges/faces; windows and doors represented as cut-outs; output controlled by SketchUp tags. Optional single group for walls and furniture/object detection.

From Apple's RoomPlan model, wall/opening/door/window surfaces have semantic categories, dimensions and transforms in the original captured-room data. **The SketchUp SKP may not retain those original metadata objects.** Use actual SKP tags and geometry, not assumptions about USDZ attributes.

Official references:
- https://help.sketchup.com/en/sketchup-ipad/scan-design-sketchup-labs
- https://machinelearning.apple.com/research/roomplan
- https://developer.apple.com/augmented-reality/roomplan/
- https://ruby.sketchup.com/Sketchup/Face
- https://ruby.sketchup.com/Geom/BoundingBox
- Scan-to-BIM methods: https://www.mdpi.com/2075-5309/15/7/1126 (semantic segmentation + RANSAC)

## Proposed interaction

1. Select a scan group (or nothing for a global scan). Click **Analyze iPad scan (read-only JSON)**.
2. Inspect `ArchiBIM_Scan_Audit.json`: full tag definitions, sampled tags per nested group/component, object names, transforms, world AABB spans and horizontal/vertical/sloping face samples. Large meshes are sampled and must be labelled partial.
3. Once source geometry is characterized, add **Preview Scan-to-BIM**, showing a translucent overlay, candidate types, dimensions, confidence and exclusions.
4. Add **Convert Verified Candidates**, in one undoable operation with a complete per-object report. Originals should remain intact, grouped in a named reference section; do not silently change source tags or visibility.
5. Allow correction of uncertain objects then re-run idempotently. Distinguish new, updated, skipped, ambiguous and failed.

## Conversion strategy

**Wall:** Identify wall planes from RoomPlan tags and planar polygons first, then fit vertical planes via normal/distance clustering on Canvas triangles. Extract 2D wall paths, account for transformed nested groups/components, derive actual base Z/height, estimate thickness only when two parallel faces are observed, otherwise use explicit wall-thickness preset. Feed cleaned paths to the existing `LineWallImport` graph, then create `SSDigitalLab_ArchiBIM` wall groups with valid persisted data. Reconcile T/corners and detect duplicates on repeat import. Preserve partial-height walls and sloping geometry as unsupported, not guessed.

**Openings:** Detect reliable rectangular cutouts in RoomPlan faces and host them on the matching wall as wall `openings[]`. Resolve world-to-wall local X and sill height. Exclude ambiguous holes until reviewed. Opening subtype (door vs window vs open passage) must be grounded by geometry and tags, not area alone.

**Floor/slab:** Identify horizontal surface and elevation. Extract boundary loops, holes and thickness evidence. Current Core slab uses rectangular width/depth with rectangular cutouts: permit a first-pass rectangle only; do not falsely replace an L-shaped/curved footprint with its bounding box. General polygons require an expanded slab core.

**Cabinet:** Identify cabinet-like bounding masses conservatively and hand off to `SSDigitalLab::ArchiBIMJoinery` API using its `Core.normalize` and `create` methods, not a Core generic wall/box. Inferred envelope gives width/depth/height/orientation, not carcass/material/hinge/drawer construction. Only use known defaults for missing data, flagged in the result. Non-parametric display props stay as reference.

**Levels/tags/transforms:** Determine a candidate's true world placement from accumulated group/component transforms, never a raw local bounding box. AABB spans overestimate rotated objects and may not be treated as oriented dimensions. Match established levels using measured base Z within tolerance, never blindly force onto active level. Preserve existing tag folders and old BIM objects.

**Idempotence:** Store source model fingerprint and stable entity instance path/IDs in converted BIM metadata. Keep per-source audit outcomes; avoid creating duplicate walls/cabinets on successive one-click runs.

## Safety and measurable QA gates

- Read-only audit cannot mutate any SketchUp entity or model attribute.
- Do not run destructive test fixtures against the Setapak client model. QA scratch models are separate.
- Nested transforms, rotated/mirrored instances, Canvas large mesh budgets, missing tags, mixed room/furniture, duplicate faces, openings and multiway junctions must have regression fixtures.
- Compare generated walls/floor to source within a configurable tolerance and expose residual errors.
- Source geometry/texture, named tags, saved scenes, camera and original groups remain unmodified.
- Integration acceptance requires **real SketchUp Desktop** runs and evidence logs, not just pure-Ruby CI. Tests should report unsupported or skipped types honestly.

## Current code state

- `archibim/scan_audit.rb`: read-only group/tag/sample inventory, conservative candidate labels, bounded traversal.
- `test/test_scan_audit.rb`: pure Ruby inference regression cases.
- Manager and Extensions menu: **Analyze iPad scan (read-only JSON)**.
- **NOT DONE:** Setapak runtime audit, actual wall/floor/cabinet conversions, visual overlay, performance profiling on 370MB scan, desktop QA.

Next evidence needed: `ArchiBIM_Scan_Audit.json` exported from the Setapak scan on SketchUp 2026 Desktop; this resolves the concrete data structure before the converter modifies geometry.
