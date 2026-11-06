# ArchiBIM v0.7.0 SketchUp Desktop Acceptance Checklist

Use **a new empty SKP** first. Back up any existing files. Restart SketchUp after installing the RBZ.

- [ ] UI header and footer show v0.7.0.
- [ ] Create a 4-wall room using `20',70'`. Four walls and their junctions are visible in Properties.
- [ ] Select south wall → Move connected wall. Click base point, move perpendicular, enter `10'` in Measurements. East/west stretch, north stays put.
- [ ] Wall thickness remains exactly the stored value (e.g., 150 mm), and wall height stays unchanged.
- [ ] Add door and window before connected move. Their widths, sill heights, frames, 2D markers and visual world positions are preserved.
- [ ] Shorten a wall until a hosted opening would leave it: red/invalid preview and no partial edit.
- [ ] Undo once: wall positions, openings and joins revert. Redo restores them.
- [ ] Change a south-east junction to Join Only: the east neighbor no longer stretches.
- [ ] Change that junction to Unlinked: the joint stops cleaning up and does not silently reconnect when nearby.
- [ ] Unlink Entire Wall, then create another touching wall: no new automatic link to the disabled wall.
- [ ] Click Detect / reconnect nearby: touching geometry joins can be restored explicitly.
- [ ] Create a perpendicular internal partition touching another wall's middle: one T-join, default Join Only.
- [ ] Toggle the global Auto-Join checkbox OFF. Create a new touching wall: no new graph link.
- [ ] Save and reopen SKP: junction modes (including unlinked state) persist.
- [ ] Confirm existing v0.6.0 sliding doors, stair cutouts, camera reset and levels still work.
- [ ] Export **Diagnostics → Export ArchiBIM testing log** if anything fails, with a screenshot and steps.

**Known initial scope:** Straight axis-aligned or rotated plan walls, one-hop links, perpendicular displacement. Roofs/slabs/rooms/beams do not yet follow the wall edit, and native Move does not automatically propagate other walls.
