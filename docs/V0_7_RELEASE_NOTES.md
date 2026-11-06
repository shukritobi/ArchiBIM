# ArchiBIM v0.7.0 | Associative Wall Connections

**Release scope:** Wall connectivity and non-destructive edits. Builds on the unpublished-in-GitHub v0.6.0 stair/slab, sliding door, opening placement, room-wall and camera features. Existing `SSDigitalLab_ArchiBIM` wall IDs and opening properties remain compatible.

## New

- **Persistent wall graph, schema 1:** model attribute `SSDigitalLab_ArchiBIM/wall_graph_v1` records stable UUIDs for each junction, two wall IDs, connection endpoints / T host station, and `linked`, `join_only` or `unlinked` mode. The graph is saved in the SKP file and participates in Undo.
- **Automatic connection discovery:** same-level perpendicular endpoint-to-endpoint corners within a 10 mm tolerance default to **Linked**. Endpoint-to-interior T-junctions default to **Join only**. Ambiguous, near-parallel and cross-story cases are skipped. Uses existing SketchUp cursor snapping for exact placement; this graph does not force global position corrections.
- **Unlink and reconnect controls:** Wall Properties shows connections by wall name, endpoint and type. Set a single connection to Linked / Join only / Unlinked. **Unlink entire wall** disables existing connections and blocks new automatic associations even for a wall with no current junctions. **Detect / reconnect nearby** explicitly restores touching disabled joins and detects new candidates.
- **Opt-out of auto-join:** the Build panel's **Detect and connect touching wall junctions automatically** checkbox controls new automatic connections. Switching off does not delete existing connections.
- **Move Connected Wall tool:** select a wall → Properties → **Move connected wall**, or Extensions → ArchiBIM → Move connected wall. Click a base point, move perpendicular to the selected wall for a ghost preview, then click to commit. Instead of clicking the second time, enter a length such as `10'`, `-10'` or `3048mm` in the native SketchUp Measurements box. The selected wall moves rigidly; each directly linked neighbor only changes its touching endpoint. **No arbitrary scaling of wall thickness, height or door/window sizes.**
- **Opening anchoring during stretches:** the solver defaults to preserving existing door/window world locations on affected neighboring walls. Widths/heights remain constant. Wall modifications that would push an opening outside the host are rejected before mutation. Other policies supported in the pure solver: `start`, `end`, `proportional`.
- **Junction mesh permissions:** the geometric miter/butt solver receives the relationship state. Unlinked edges are not treated as miters. Wall solids remain separate SketchUp groups with their original BIM IDs.
- **Diagnostic events:** connection created/mode changed/unlinked/reconnected, preview invalid, move committed, with impacted IDs and displacement.

## 20 × 70 ft acceptance example

1. In an empty model, choose **4-wall room**, enter `20',70'` in Measurements. Four individual walls are created, their corners linked.
2. Select the south wall. Use Properties → **Move connected wall**.
3. Click a base point. Move outward; type `10'` (or `-10'`, depending on the wall direction) and press Enter.
4. East and west wall lengths should increase from 70 ft to 80 ft, north wall remains unchanged, and south wall stays 20 ft. Wall heights and thicknesses are unchanged.
5. Undo once. Inspect that all walls, openings and junction states revert together.
6. Unlink the south-east corner in Properties. Repeat the move: only the west side wall stretches. Reconnect touching walls explicitly when they meet again.
7. Add a partition from the middle of an exterior wall. Confirm its T junction shows **Join only**, unless manually changed.

## Deliberate constraints and known limitations

- **Use the dedicated Move Connected Wall tool.** SketchUp's native Move does not propagate graph constraints in real time; native Scale remains a separate compatibility/repair operation. This avoids hidden observer edits and multiple Undo steps.
- Connected Move initially restricts the selected wall to **perpendicular plan displacement**. This retains rectangular geometry in typical four-wall houses; arbitrary multi-axis constraint solving is not implemented.
- Only direct, linked neighbors (one graph hop) stretch. A connection loop is **not** recursively traversed, preventing the whole house from being unintentionally translated.
- T hosts may propagate a linked branch endpoint for basic cases. A T branch moved off its linked host is rejected, because that requires an explicit Slide or Detach workflow. Join-only partitions do not propagate.
- Multi-way corner junctions, X intersections, curved walls, collinear joins, slanted/non-planar walls, nested scaled groups, duplicate wall UUIDs and arbitrary native face edits are not auto-resolved.
- Slabs, roofs, rooms, beams and stairs are **not** automatically extended with connected walls in this release. Check them manually after reshaping the house.
- If native Move already broke a linked junction, connected movement is blocked until the relationship is repaired or unlinked. This prevents arbitrary long-distance snapping.
- Unlinked corners retain existing independent solids, but geometric overlap/adjacency may still need manual inspection where faces are coincident.
- The plugin has been syntax-checked and pure Ruby tests passed, but has **not been executed inside SketchUp 2026 Desktop**. Visual interaction, graph persistence and Undo require desktop acceptance testing before using a client project.

## Technical files

- `archibim/wall_graph.rb` - pure Ruby serialized wall connectivity and preview solver
- `archibim/connected_move.rb` - interactive SketchUp drawing tool (two-click + Measurements)
- `archibim/junctions.rb` - accepts explicit graph permissions for corner/tee cleanup
- `archibim/main.rb` - graph persistence and transactional geometry regeneration
- `archibim/ui/panel.html` - link, join-only, unlink, reconnect, move controls
- `test/test_wall_graph.rb`, `test/test_connection_mesh.rb` - regression tests

Back up your SKP before installing. Use **Diagnostics → Export ArchiBIM testing log** to share any SketchUp-side failures. Never manually edit BIM geometry inside an ArchiBIM group: regeneration replaces internal entities.
