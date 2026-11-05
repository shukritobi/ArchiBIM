# ArchiBIM v0.5.1 | Geometry repair hotfix

5 November 2026. Based on the SketchUp 2026 screenshots and ArchiBIM_Testing_Log(1).txt.

## Confirmed cause

Doors, windows, Properties updates and Scale repair all raise the same error:
ArgumentError: Cannot convert argument to Geom::Vector3d (archibim/repair.rb:42).

In SketchUp, Vector3d#* is cross product, not multiplication by a scalar.
The expression x * y.dot(x) therefore fails. We now orthogonalize with
Geom::Vector3d.linear_combination(1.0, y, -projection, x).

## Hotfix

- Recover unit, perpendicular local axes for normal, scaled and sheared BIM groups.
- Preserve stored thickness, height, hosted opening dimensions during rebuild.
- Reject collapsed and parallel transforms with a clear exception.
- Fix the HTML manager's stale v0.4.0 footer to display v0.5.1.
- No migration: existing ArchiBIM group metadata stays compatible.
- Add tests with a SketchUp-compatible vector double that intentionally rejects Vector3d * Float.

41 tests and 131 assertions pass locally. Ruby and HTML-JS syntax passed.
The source tests are not a replacement for live SketchUp geometry verification.

## Test in SketchUp

1. Install new RBZ and fully restart SketchUp; check v0.5.1 badge and footer.
2. Select a wall and edit thickness in Properties. Click Apply.
3. Place a door and a window on the wall and verify the opening cutouts.
4. Scale wall length 0.5 with native SketchUp Scale, release, confirm
   thickness and height remain unchanged after the repair operation.
5. Run Repair selected after Scale and Rebuild selected; both should work.
6. Export the diagnostics log if any error still occurs.
