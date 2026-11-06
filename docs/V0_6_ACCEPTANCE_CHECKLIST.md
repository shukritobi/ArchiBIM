# ArchiBIM v0.6.0 SketchUp 2026 acceptance checklist

Use a fresh SKP file. Make sure all input dimensions are metric mm, and fully restart SketchUp after installing this RBZ.

1. **Rectangular room:** On Ground Floor, choose **4-wall room**. Draw an 8000 × 6000 mm footprint, or enter `8000mm,6000mm` in Measurements after first click. Verify four independent wall groups and an inner room zone. Click each wall and edit its height.
2. **Second-floor stair opening:** Ground Floor at 0 mm, First Floor at 3000 mm. Create a Ground Floor stair (Rise 3000 mm, Width 1100 mm, clearance 50 mm, auto cut checked). Select First Floor and create an 8000 × 6000 mm slab encompassing the stair. Inspect from above: there should be a real void in the slab directly above the stair. Check net slab quantities are reduced.
3. **Retroactive sync:** Undo/remove the First Floor slab, recreate it before the stair, then create the stair. The cutout should appear again. Change stair width to 1200 mm in Properties, Apply, then inspect the slab. Also test **Diagnostics → Sync stairwell holes**.
4. **Opening position:** On a wall longer than 4000 mm, insert a 900 mm door and a 1200 mm window. Select the wall, then Hosted Components → **Move on wall** for the window. Move mouse toward each wall end and confirm the preview stops at the valid edge. A move over the door must show red and be rejected. Click valid green preview to commit. Check Undo.
5. **Existing-opening selection:** Extensions → ArchiBIM → Move hosted opening. Click directly on a hosted window/door geometry, hover a second position, click. Verify its wall void follows its new position.
6. **Sliding door:** Choose Sliding door, width 2400 mm, height 2100 mm, 2 panels. Place on long wall; inspect aluminium frames, two glazing panels, two tracks. Select the host wall and change to four panels, flush exterior, then Apply.
7. **Flush alignment:** Select a wall, set Exterior face to Right/Left relative to drawn direction. For a window/door, change Frame Position from Center to Flush exterior. Inspect in top view, ensuring the outer frame surface coincides with the chosen wall face.
8. **Camera reset:** Move camera far away, switch to Top/Parallel Projection. Click **Fit whole house · Perspective**. Confirm the complete BIM model is visible in perspective, not parallel.
9. **Persistence:** Save file, reopen, and ensure stair holes and all opening placements remain correct. Undo/Redo should restore pre-edit values. Export Diagnostics testing log and retain it for bug reporting.

Known prototype limitations: only native ArchiBIM rectangular slabs receive stair holes, rotated stair footprints use bounding rectangles, and mouse repositioning is two-click select/confirm rather than drag-hold.
