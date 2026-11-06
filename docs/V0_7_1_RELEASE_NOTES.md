# ArchiBIM v0.7.1 - Interior Wall Join Repair

6 November 2026 | Bug-fix preview for SketchUp 2026

## Why this release exists

The November 6 SketchUp 2026 test log showed that the original four-wall exterior shell moved correctly, but interior partitions did not follow adjoining exterior walls. The log showed **two automatic T-junctions created in `join_only` mode**, while exterior corners were `linked`. Subsequent scans logged only `graph_reconnect` without stating whether anything was found or changed. An existing T link was manually changed to `linked` after it stopped touching, resulting in an invalid connected-move preview.

## Changes

1. **New T-junctions default to `linked`**. Moving the host wall updates the attached partition's reference endpoint. This does not change wall height/thickness or the size of hosted openings.
2. **Detect against host-wall physical faces**. A partition endpoint exactly on a face is recognized regardless of whether the host reference line is left, middle or right. `wall_inventory` now passes alignment to the graph. Join geometry uses the same T contact tolerance.
3. **Legacy join-only T-junctions remain explicit**. Choose **Properties > Detect / link nearby** on an affected wall, or **Build > Link existing T-junctions** to upgrade all touching legacy tees. This operation is undoable. Unlinked joints and intentionally disabled walls are *not* silently re-enabled by the global scan.
4. **New scan results in the UI**. Scan results show counts of detected, upgraded, reconnected and broken junctions. Connected-wall properties show **Touching** or **Broken / not touching** for each association.
5. **Better diagnostics**. The exported log includes each wall's world reference endpoints, thickness, reference-line alignment, full persisted graph, junction modes, relative host-face offsets, linked/broken counts and nearby unconnected endpoints. Scan events now log outcomes even when zero connections were found.
6. **Safe linking validation**. A physically separated T-junction cannot be changed to Linked in the inspector until the endpoints are brought together. Linked T partitions can slide parallel to their host where contact remains valid.

## Known limitations

- This version still does **not** intercept SketchUp's native Move tool. Use **Move connected wall** in ArchiBIM.
- Walls remain separate native SketchUp groups. A "join" is a parametric connection and geometry cleanup, not a SketchUp Boolean union.
- The solver propagates edits through directly linked neighbors; it does not yet resolve arbitrary nested multi-way graphs, curved walls or strongly oblique collisions.
- A gap beyond the 10 mm physical-face tolerance is **not** automatically moved or snapped closed. The new diagnostic audit reports nearby gaps (up to approximately 250 mm) so you can deliberately extend or move the partition to the host face.
- Explicit Join Only keeps a neat intersection but intentionally does not propagate movement. An explicit Unlinked or disabled wall remains isolated.
- Camera/interactive SketchUp viewport tests have not been run in the packaging environment. Make a copy of the model before installing and test with the checklist.

## Test against the supplied failure

1. Copy the model before testing.
2. Select an existing interior partition, open **Properties > Associative wall connections**. Check the T-junction status and mode.
3. Click **Detect / link nearby**. You should see a status message with a count; it may upgrade the previous `join_only` link to `linked` if the walls still touch.
4. If nothing changes, choose **Build > Scan all walls** and then export the Diagnostics log. It now reports unconnected endpoint gaps and broken links.
5. Use **Move connected wall** on the exterior host. Type e.g. `10'`. Attached interior endpoints should follow without changing the thickness or height. A connected partition that slides along its host can also be repositioned without breaking the attachment.
6. Change a T connection to Join Only and verify it stops following. Change it to Unlinked and verify it is not automatically rebuilt.
7. Verify a separated junction cannot be relinked automatically; align the wall endpoint to the wall face, then scan again.
8. Export a new v0.7.1 log and attach it with before/after screenshots for any remaining failure.

## Source validation

Ruby syntax checks and UI JavaScript parsing passed. 76 Ruby tests, 256 assertions, zero failures. Tests cannot validate interactive native SketchUp geometry/rendering.
