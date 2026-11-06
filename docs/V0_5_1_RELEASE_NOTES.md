# ArchiBIM v0.5.1 | Repair + opening placement hotfix

5 November 2026 · hotfix for SketchUp 2026, following the user's `ArchiBIM_Testing_Log(1).txt` and screenshots.

## Confirmed root cause

All three failed workflows (door/window insertion via the Properties callback, editing an element, and repairing a scaled group) had the exact same exception:

`ArgumentError: Cannot convert argument to Geom::Vector3d`, at `archibim/repair.rb:42` in `normalized_transform`.

In SketchUp Ruby, `Geom::Vector3d#*` is a **cross product**, and `x * y.dot(x)` is not legal scalar multiplication. The former implementation used `y -= x * y.dot(x)` while orthogonalizing scaled and rotated BIM group transformations.

This version uses `Geom::Vector3d.linear_combination(1.0, y, -projection, x)` instead, preserving the intended Gram-Schmidt orthogonalization. The same method is called on *all* property updates and opening insertions, even when no scaling happened, which explains why seemingly unrelated tools failed together.

## Improvements and tests

- Fix `Repair.normalized_transform` for unit, scaled, rotated, and mildly sheared BIM groups. Retains group origin and obtains unit, mutually perpendicular local axes.
- Preserve parametric geometry on regeneration. Length/depth follow the saved or adopted footprint; wall thickness, wall height, and hosted window/door sizes stay fixed.
- Reject collapsed/parallel transforms instead of silently producing invalid geometry.
- Add a SketchUp-API-compatible `Geom` test double that deliberately throws the same error for `Vector3d * Float`, ensuring CI catches a recurrence of this specific mistake.
- Fix stale BIM Manager footer so version shown there matches the loader and header.
- Preserve all BIM model attributes and existing file format. No data migration is needed.

## Local validation

41 Ruby tests / 131 assertions passing, with zero errors or failures. Ruby syntax and embedded HTML/JavaScript parsing passed. **Live SketchUp desktop interaction must still be verified by the user**.

## Acceptance test

1. Restart SketchUp after installing `ArchiBIM_latest.rbz`; header and footer should both say v0.5.1.
2. Select one BIM wall, change its thickness and click Apply. The Properties panel must remain usable and no vector error should appear.
3. Insert a door and a window on that wall. Both cutouts should regenerate, and the green ghost preview should become geometry.
4. Select a wall, native Scale it to 0.5 along its length, and release the mouse. After automatic repair, wall thickness and height must remain unchanged while length adopts the scale.
5. Select and run Diagnostics → Repair selected after Scale and Rebuild selected, checking that there are no `Geom::Vector3d` errors.
6. Export the testing log if any step still fails.

**Limitations:** Only rectangle wall/roof/solid shapes are in the current prototype. Heavy shears, transforms with collapsed axes and native geometric vertex edits are unsupported. The fixes are validated with API-compatible Ruby tests, not live SketchUp.
