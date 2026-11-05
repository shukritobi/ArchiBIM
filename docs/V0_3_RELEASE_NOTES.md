# ArchiBIM 0.3.0 | BIM drawing workflow update

## New features

1. **Left / Center / Right wall reference:** choose the reference line before drawing, or change it in the Properties inspector. Older v0.2 walls use their original left-face baseline.
2. **Basic automatic wall joints:** pairwise miter at two coincident endpoint wall paths; butt-trim where a branch endpoint meets an existing wall. Recalculates on plugin-created or resized walls. Use **Extensions → ArchiBIM → Recalculate wall junctions** after native SketchUp Move.
3. **Hosted opening diagrams:** Door plan swing arc and elevation opening line; window plan projection and elevation opening symbol. Symbols have separate dedicated SketchUp Tags and can be hidden and assigned built-in dashed line styles independently. Openings also store **hinge left/right** and **swing in/out**.
4. **Opening pre-insertion preview:** Green valid outline, red invalid outline when hovering the host wall, in both top plan and perspective/elevation. Use **H** for hinge and **F** for swing, then click to commit. Existing openings prevent overlap.
5. **Tag management:** 2D / elevation / structural Tags separated and collected into native SketchUp Tag folders (where supported). The Tags tab supports visibility and line-style changes. Once customized, Tags keep the existing line style on regeneration.
6. **Typed Measurements:** After clicking start corner, enter `20',70'` to create a 20 by 70 foot rectangular slab, room or roof footprint; enter `20'` after a wall start point for a 20-foot wall. Supports `mm`, `m`, inches and feet via SketchUp's length parser.
7. **Unit-aware inspector:** Dimensions, levels, sills and presets use SketchUp's active model unit display and parser. Slab properties display the formatted floor area and metric area.
8. **Resize BIM footprint:** Explicit horizontal resizing under Export preserves wall thicknesses, door/window physical size and structural heights; moves hosted opening centers proportionally. Fails validation rather than crushing an opening when a house shrinks too far.

## Constraints and safeguards

- **Automatic joins are limited** to straight, same-story wall pairs at coincident path endpoints and single branch tees. They are not a general topology/Boolean wall solver; three-way joins, coplanar overlap, wall stacks and different level/height conditions require more work.
- A **wall's path endpoints** are computed from the group's current transform; using the native SketchUp Scale tool to resize a whole building still scales actual geometry. Use *Resize BIM footprint* instead; automatic scale interception is planned.
- New walls default to **centerline**. Existing v0.2 walls without an `alignment` attribute remain **left-reference**, preventing unintended geometry shifts on upgrade.
- All local element parameters are stored as **millimetres** for calculation reliability; only input/output is unit-aware. The exported quantity schedule intentionally uses m² and m³.
- Native SketchUp Tags provide dashed line styles. Global SketchUp **View → Edge Style → Dashes** must be enabled to see dashed styles on versions that require this setting.
- Opening graphics are simplified symbolic conventions, not a complete manufacturer-grade family library. Scene-specific drawing representation and automatic hiding of 3D door panels are future work.
- Geometric calculations and UI syntax can be tested without SketchUp. **Desktop interaction, model geometry and plan scene appearance are not verified** in a real SketchUp session yet.

## Quick test

1. New SKP in mm, draw three walls: East, North, interior T. Confirm the first two mitre and the tee branch ends at the main wall face.
2. Set reference Left, Right, Center and draw three short parallel walls. Confirm reference dashed line positions.
3. Change model units to Architectural. In Build, click Slab corner and type `20',70'` into Measurements. Result should be 6.096 × 21.336 m and area 130.064256 m².
4. Switch to Top and activate Door. Hover wall and check green outline. Press H, F; click; verify door arc and elevation marker. In Tags hide plan swing, ensure it disappears without hiding wall.
5. Select wall and edit length with `18'`, set window sill to `3'`; geometry should rebuild and keep physical sizes.
6. Resize footprint 80% on a backup model and verify wall thickness and window dimensions unchanged.
7. Export schedules and inspect each slab area. Use Undo/Redo after edits.

### References informing the design

- Autodesk Revit location line and wall joins: https://help.autodesk.com/cloudhelp/2025/ENU/RevitLT-ArchDes/files/GUID-F26DB6DA-A0EC-424D-B656-3BDF47607F4F.htm and https://help.autodesk.com/cloudhelp/2026/ENU/Revit-ArchDesign/files/GUID-E8B292F4-D056-4228-BD99-2CC99EBA4F58.htm
- Graphisoft Archicad 29 wall-hosted door and window preview: https://help.graphisoft.com/AC/29/INT/_AC29_Help/040_ElementsVB/040_ElementsVB-306.htm
- Vectorworks 2026 plan/3D wall insertion preview: https://app-help.vectorworks.net/2026/eng/VW2026_Guide/DoorWindow/Drawing_DoorWinAssembly.htm
- SketchUp Ruby layer line-style API: https://ruby.sketchup.com/Sketchup/Layer.html
