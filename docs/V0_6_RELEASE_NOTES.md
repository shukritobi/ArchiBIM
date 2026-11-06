# ArchiBIM v0.6.0 · BIM editing workflow release

5 November 2026 · SketchUp Desktop 2024–2026 (target, desktop acceptance pending)

## Added

- **Auto stairwell opening**: a stair with `cut_slab=true` regenerates associated ArchiBIM slabs at its upper landing elevation (±150 mm), using its parametric run, clear width and configurable clearance. Works if stair or slab is created first. Cutouts persist as `source_stair_id` records in slab BIM attributes; editing either element resynchronises. The explicit Diagnostics **Sync stairwell holes** button supports existing v0.5.1 stairs and native Move operations. Slab net area, volume and cost now deduct these generated openings.
- **Reposition hosted openings in viewport**: on a selected wall, Properties → Hosted components → **Move on wall** starts a mouse tool. The ghost preview follows the host wall and shows offsets to both ends, clamped to valid wall extents. Green previews commit on click, red ones are rejected on overlap. Alternatively Extensions → ArchiBIM → Move hosted opening lets you click a hosted frame first, then click the new position.
- **Sliding doors**: new hosted `sliding_door` object with 2–4 glazed panels, dual track, plan/elevation linework, direction and frame positioning, and `IfcDoor` classification label. Quantities count as a separately rated opening.
- **Flush mounting**: wall `exterior_side` field and per-opening `mount` field (`center`, `exterior`, `interior`). Changes retain the host wall opening and regenerate frames at the relevant face. Exterior is relative to wall drawing direction (left/right).
- **Room walls**: Build → Four-wall room, click two corners or enter width/depth in the VCB. Creates 4 independent parametric wall groups with common `room_group_id`, optionally a room zone. Rectangle describes exterior wall boundaries; 4 side walls receive junction treatment.
- **Camera**: Build → Fit whole house · Perspective restores a 35-degree three-quarter view and frames the ArchiBIM groups only.

## Upgrade and manual validation

Install the .rbz through Extensions → Extension Manager, fully restart SketchUp, back up important SKP files. Legacy 0.5.1 walls, openings and stairs keep their data: missing fields fall back to defaults. Existing stairs are eligible for auto cut after pressing Sync stairwell holes.

Before using on client work, verify in SketchUp that upper slab voids survive save/reopen, stair updates and Undo; frame flush behaviour works on walls drawn both directions; opening drag does not overlap others; sliding door glass and track geometry is visible; rectangular room creation and camera reset are correct.

## Known limitations

- Automatic cutouts apply **only to ArchiBIM rectangular slab elements**, not arbitrary raw SketchUp floor groups or external BIM families. For rotated stair/slab combinations, a conservative local-axis bounding rectangle is used for the opening; verify actual required clearance and avoid over-cutting at angles. This is a prototype, not a general 3D boolean solver.
- The **Move on wall** command uses mouse-hover followed by click to confirm, not native drag-and-hold. It does not automatically transfer an opening from one wall to another.
- Sliding doors use conceptual parametric frames/tracks, not manufacturer-specific details or pocket/hardware scheduling.
- Four-wall room uses an axis-aligned rectangle and creates four independent walls; editing the room zone later does **not** automatically drive associated wall positions. Four-wall joins remain subject to the current junction solver.
- Pure Ruby tests cannot confirm actual SketchUp face/solid validity, click inference or persisted IFC semantics. End-to-end SketchUp 2026 desktop testing is mandatory.
- Native Move may not immediately trigger a slab resynchronisation; use Diagnostics → Sync stairwell holes after such operations.

## Tested in this build

Pure-Ruby tests exercise slab boolean-area union/clipping, net quantities, opening clamping, mounting geometry, settings migration and existing 0.5.1 functionality. Ruby and embedded JavaScript syntax are checked. No live SketchUp Desktop runtime was available during assembly.
