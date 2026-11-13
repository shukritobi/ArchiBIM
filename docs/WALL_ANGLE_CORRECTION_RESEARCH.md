# Wall angular correction and drawing inference (13 November 2026)

## Verified Setapak input: read-only audit

Uploaded `ArchiBIM_Scan_Audit.json` records SketchUp 2026.0.429, source `Bambulabs_MakerWorld_Setapak_Central_scan.skp`, 157 nested containers and 81 individual RoomPlan `Wall-rp-*` groups across four capture areas:
- `Group#16 / area-setapak-central-1 / RoomPlan / Walls` (20)
- `setapak-central-area-2-bambulabs / RoomPlan / Walls` (21)
- `Group#5 / store-pos-area-setapak-central / RoomPlan / Walls` (14)
- `Group#5 / setapakcentralbambulabs / RoomPlan / Walls` (26)

The audit includes axis-aligned bounding-box spans and face/tag counts but **does not include wall centerline endpoints, vertex coordinates or actual wall bearings**. Thus individual skew angles and accurate junction gaps cannot be derived from the JSON alone. These must be computed from real SketchUp geometry at runtime. The images show irregular near-orthogonal plan angles but do not certify actual survey accuracy.

## Research: production CAD/BIM patterns

1. **Autodesk Revit Align:** reference-first workflow; align walls by selectable faces or centerlines and optionally lock a persistent constraint. Reference wall's orientation matters as much as the target wall's orientation. See https://help.autodesk.com/cloudhelp/2024/ENU/RevitLT-Model/files/GUID-9C867721-1970-4ECC-90F1-3C112B9EC2E6.htm
2. **AutoCAD Ortho / Polar Tracking:** drawing directions can be constrained to 90-degree orthogonal axes or alternative polar angles; `POLARMODE` supports tracking relative to existing objects rather than the absolute UCS alone. See https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DidYouKnow/files/GUID-6FB309A8-2696-4383-8277-950E9E2756A8.htm and https://help.autodesk.com/cloudhelp/2025/ENU/AutoCAD-Core/files/GUID-D91628CC-9975-4DBF-8D02-10B23A6F3ED5.htm
3. **SketchUp drawing inference:** cursor InputPoint is intended for native snapping, while `View#lock_inference` with one/two InputPoints provides Shift/arrow-key style direction constraints. See https://ruby.sketchup.com/Sketchup/InputPoint.html and https://ruby.sketchup.com/Sketchup/View.html
4. **Scan-to-Design:** Apple RoomPlan output offers simplified separate edges and faces, while Canvas can supply dense mesh geometry. The scan's RoomPlan `Wall-rp-*` groups should be preferred for wall reconstruction. See https://help.sketchup.com/en/sketchup-ipad/scan-design-sketchup-labs

## v0.8.4 prototype behaviour

**Wall straightening:** Select one or more individual RoomPlan Wall-rp groups, or top-level ArchiBIM wall groups. Select:
- Orthogonal: near 0/90/180° in model XY coordinates.
- Architectural 15°: near any multiple of 15°, allowing intentional diagonals.
- Relative to reference: select one wall and **Set reference wall**, then other walls to make them parallel/perpendicular to that wall.

Tolerance defaults to 5° and is limited to 0.1–15°. Angle steps 90° or 15° are deliberate, configurable policy, not assumptions about measured geometry. Deviations exceeding tolerance are skipped; no forced corrections.

**Centre pivot:** Derive the wall direction from the longest reliable near-horizontal native edge in the selected scan group (or BIM local X axis). Compute the wall's world midpoint and perform a rotation about the vertical Z axis. Transform group-local instances correctly while editing within nested RoomPlan groups. This changes the **group transformation** while leaving local mesh faces, tags, materials and BIM parametric metadata untouched.

**Connected wall warning:** A centre-pivot rotation moves both endpoints by approximately `L * sin(|correction|/2)`. This can open corner gaps in RoomPlan groups. The current command reports predicted end movement and is undoable, but **does not reconstruct scan wall junctions or automatically heal endpoint gaps**. For existing ArchiBIM parametric wall graphs, reject/undo the operation if it introduces additional broken stored links.

**Native wall drawing:** Use existing `Sketchup::InputPoint` cursor inference plus polar-near-axis projection and explicit Right=X, Left=Y, Down=free and Shift=lock current direction. Avoid changing the existing SketchUp built-in Line tool itself.

## Next iterations (not claimed implemented)

1. Geometric constraint solver for wall intersections: infer a dominant building frame separately for each capture zone, detect 2D centerline endpoints and near-corner/T joins, solve wall layout jointly with weighted least squares and angular priors, then regenerate ArchiBIM wall paths and openings without creating gaps.
2. Non-destructive source scan to BIM wall conversion preserving survey geometry as an overlay reference and reporting max position deviations.
3. Correct joint intersections while preserving wall thickness, opening offsets and semantics across corners, T junctions and local irregularities.
4. Interactive preview geometry highlighting original and target axes, gap/movement warning per selected wall, virtual orthographic corrected plans and QA screenshot evidence.

## Acceptance and safety gates

- Pure Ruby: angles 88/92/-91, midpoint invariance, 15/30/45/60 intent, relative reference, malformed inputs and projection.
- Desktop SketchUp: RoomPlan group world transforms, nested-edit instances, multiple groups, Z and height unchanged, raw tags/faces unchanged, undo/redo; native arrow and Shift key simulation.
- Graph: connected BIM corners/Ts not silently damaged; reconnect options only after geometry is sound.
- Stress: 81 walls from Setapak capture groups without traversing the huge textured mesh.
- Runtime status: **source and pure-Ruby CI tests alone do not confirm actual SketchUp 2026 behaviour**. Real QA bridge tests and screenshots must verify before production acceptance.
