# Native SketchUp lines → ArchiBIM walls

**Version:** 0.8.2 (12 November 2026)  
**Status:** Pure Ruby geometry tests pass. SketchUp 2026 desktop acceptance pending.

## Research: how other BIM software converts lines

| Software | Native workflow | Design adopted |
|---|---|---|
| [Autodesk Revit](https://help.autodesk.com/cloudhelp/2027/ENU/RevitLT-ArchDes/files/GUID-05BAFEAA-5186-484E-80F4-8D900C454748.htm) | Wall **Pick Lines** creates walls along existing model lines, edges and references. Tab picks a connected line chain. | Reuse existing sketch lines and wall type/height/alignment |
| [Graphisoft Archicad](https://support.graphisoft.com/hc/en-us/articles/23126601413649-How-to-model-wall-from-a-2D-line) | **Magic Wand** traces line/edge chains or polygon boundaries to create BIM elements. | Convert a complete connected 2D network with one command |
| [SketchUp Ruby API](https://ruby.sketchup.com/Sketchup/Entities) | Edge vertices and active model entity collections provide native source geometry. | Pure Ruby topology solver with thin SketchUp adapter |

These are independent workflow references, not copies of proprietary code.

## User workflow

1. Select the correct **active level**, wall thickness, wall height and wall alignment.
2. Draw on one flat horizontal plane with SketchUp's native **Line (L)** tool.
3. Select **one edge** in the chain, multiple selected edges, or a bounded face.
4. Click **BIM Manager → Build → Convert connected lines to walls**, or **Extensions → ArchiBIM → Convert connected lines to BIM walls**.
5. Inspect linked walls in Properties and the Diagnostics event.

The converter discovers all connected edges **within the current SketchUp editing context**, not edges hidden inside unopened groups. To use a group's lines, open the group for editing and select one line. Maximum network size is 500 edges. Source edges remain unchanged.

## Single plane and junction rules

| Input | Behaviour |
|---|---|
| Multiple endpoints on a single horizontal Z plane | Allowed when that plane matches the active level within 1 mm |
| Sloping line / endpoints on different Z planes | Rejected before model mutation |
| Endpoints within 1 mm | Snapped in calculated graph, without changing native input |
| Collinear joined segments | Merged into one long parametric wall |
| L / corner | Normal existing linked WallGraph corner, miter cap |
| T: branch endpoint on host interior | Existing linked WallGraph T junction and host-face termination |
| X / plus: two lines cross | Keep longer host continuous, split other into two connected T branches |
| Three-ray Y / star with no clear through-wall | Mark unresolved multiway for review; do not claim a verified solid union |
| Collinear overlap / wall below 50 mm | Rejected before model mutation |
| Exact duplicate source edges | Deduplicated |
| Repeated conversion of existing BIM walls | Blocked to avoid duplicate walls |

The new wall objects retain the active level, height, thickness, alignment and unique stable BIM IDs. Graph linking and wall rebuilding are completed in **one Undo transaction**. User-customized unlinked connections remain unlinked.

## Architecture

- **archibim/line_wall_import.rb**: pure Ruby planar graph, node snapping, straight-chain merging, crossing splitting, topology classification.
- **archibim/line_wall_adapter.rb**: native SketchUp edge selection, current edit transform, active-level verification, parametric creation and log emission.
- **archibim/wall_graph.rb**: existing persistent corner/T junction graph and linked movement.
- **archibim/junctions.rb**: existing miter and T termination mesh calculation.
- **test/test_line_wall_import.rb**: geometry regression tests.

## QA log and acceptance

**Automated regression tests**

- [x] Four-corner rectangle
- [x] T branch without cutting its host
- [x] X crossing and four-arm plus composed of separate native lines
- [x] Collinear merge and diagonal corner
- [x] Z mismatch and sloping line errors
- [x] Exact duplicate deduplication
- [x] Overlapping line rejection and sub-50 mm error
- [x] Ambiguous Y junction classification

**Pending SketchUp 2026 desktop QA**

- [ ] Draw with native Line (L), select one edge and generate full network; inspect properties, tags and orientation.
- [ ] Test selected face and two disconnected selected chains.
- [ ] Compare joins for rectangle, T, multiple Ts, X, plus, Y, diagonal and offset cases.
- [ ] Test nested group editing and model-to-world coordinate transform.
- [ ] Validate error handling for mixed Z values, slopes, overlap, too-short lines and mismatched active floor.
- [ ] Confirm source edges survive, repeated conversion is blocked, and one Undo removes the new walls and links.
- [ ] Save/reopen project; check connected wall move, adding hosted door/window and quantity reports.
- [ ] Export detailed diagnostics and screenshots into the ArchiBIM QA Lab.

**Current limitations:** Y/star full solid union and associative constraint graph, curved/arc walls, non-horizontal line planes, unexploded component selection, source-line hiding, and desktop runtime testing are outside this release. Standalone Ruby test results are not a claim of successful rendering in SketchUp.
