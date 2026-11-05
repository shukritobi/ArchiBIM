# ArchiBIM v0.3.0

**Parametric architecture and BIM modeling for SketchUp Desktop.** An original, experimental Ruby extension providing editable walls, hosted door and window openings, slabs, structural elements, stories, quantity takeoff, and BIM properties.

> **Development preview, not a Revit/Archicad replacement.** Core calculations and packaging are tested automatically, but wall geometry, views, insertion behaviors, and native SketchUp interactions have not yet been validated in an actual SketchUp Desktop session. Test on a backup or new model.

## Install ArchiBIM

**[⬇ Direct download: latest RBZ](https://raw.githubusercontent.com/shukritobi/ArchiBIM/main/dist/ArchiBIM_latest.rbz)**

Alternative version-pinned download: [ArchiBIM_v0.3.0.rbz](https://raw.githubusercontent.com/shukritobi/ArchiBIM/main/dist/ArchiBIM_v0.3.0.rbz).

1. Download the .rbz file, keeping the .rbz extension.
2. Open SketchUp **Desktop**. Extensions are unavailable in SketchUp for Web.
3. Go to **Extensions → Extension Manager → Install Extension**, then select the downloaded RBZ.
4. Open **Extensions → ArchiBIM → ArchiBIM BIM Manager** or the ArchiBIM toolbar.
5. Start with a **new test model** or use **Create demo model**.

The plugin has been developed around SketchUp Pro 2024–2026 Ruby APIs; exact supported-version behavior still needs in-application testing.

## What's new in v0.3

| User requirement | Current implementation |
| --- | --- |
| Wall left / middle / right placement | Select **Left, Center, Right** reference in Wall settings. Preview shows the wall thickness relative to its path. Old v0.2 walls retain the original reference setting for compatibility. |
| Wall-to-wall connections | Basic automatic two-wall endpoint miters and T-junction butt trimming within a story. From the Extensions menu select **Recalculate wall junctions** after native SketchUp Move operations. Complex multiparty intersections are not yet handled. |
| Door/window plan and elevation linework | Simplified plan/elevation symbols; door plan swing with hinge side and in/out handing. Tags can independently show/hide the associated 2D graphics. |
| Dashed 2D opening graphics | Native SketchUp Tags and available Tag line styles. Enable **View → Edge Style → Dashes** if dashed edges aren't shown. |
| Managed Tags | Dedicated ArchiBIM building-element and 2D graphics Tags; **Tags** tab controls visibility and line style where supported. |
| Editable dimensions | Select a BIM element, change its parametric measurements in **Properties**, and regenerate it. |
| Typed Measurements | Draw a wall by choosing a start point and typing a length such as `20'`. For slab/room/roof/footing rectangles type `20',70'` after placing the first corner. |
| Unit-aware input/output | Dimensions use `Sketchup.parse_length` and `Sketchup.format_length`, following active model units; explicit `mm`, `m`, feet and inches inputs are supported. Internal geometry and schedules use metric units. |
| Slab areas | Surface area shown in slab Properties and the quantity schedule. |
| Opening placement previews | Hover a valid host wall in Top/Plan or 3D to preview green placement outline, red if invalid. Click to commit. **H** changes hinge side; **F** changes swing orientation. Doors default to floor sill 0; windows default to 900 mm, adjustable in Properties. |
| Resize building without shrinking walls | **Resize BIM footprint** adjusts layout dimensions while keeping wall thickness, opening sizes, and vertical dimensions. This is an explicit ArchiBIM command, **not** automatic handling of native SketchUp Scale. |

## Main BIM tools

- **Architecture:** straight parametric walls; doors and windows hosted by walls; floor slabs; gable roofs; straight staircases; rectangular room zones.
- **Structure:** beams, columns, pad foundations.
- **Levels:** set story elevations and manage levels.
- **Documentation:** generate section-cut plan scenes; export quantity schedules as CSV; export BIM data as JSON.
- **Interoperability:** invoke SketchUp's native IFC export where your SketchUp version and license support it. A validated full IFC authoring pipeline is not yet included.

## How to use

### Model walls and insert openings

1. In the BIM Manager, set **Wall alignment** to Left, Center, or Right. Set the wall thickness and height.
2. Click **Wall** and choose start point. Move along the intended wall direction. Click again, or type a single length in SketchUp's Measurements box.
3. Draw another wall with an endpoint at the first wall's end or within its interior for a T-junction. ArchiBIM recalculates supported junctions automatically.
4. Open **Top** view and select **Door** or **Window**. Hover over the wall to show the placement outline, press **H**/**F** if desired, and click to insert.
5. To edit an opening, select the host wall in SketchUp and edit its openings in the BIM Manager. Change sill, width, height, offset, and handing.

### Model a 20 ft × 70 ft slab

1. Set the active story and select **Slab**.
2. Click the first corner.
3. Type `20',70'` in the SketchUp Measurements field and press Enter.
4. Select the slab to review its area and parametric dimensions in Properties.

### Change units and 2D graphics

- Change **Window → Model Info → Units** in SketchUp. ArchiBIM formats property lengths according to these settings and also accepts explicit units.
- In ArchiBIM **Tags**, toggle opening plan/elevation graphics or choose an available native SketchUp line style.
- Tags default to category-level visibility, so you can suppress plan swing graphics without deleting the door model.

### Resize a BIM footprint

Use the dedicated **Resize BIM footprint** action (in the manager's Export section) with a percentage, such as 80%, on a **backup model**. This changes X/Y layout dimensions, recalculates hosted parametric elements, and preserves physical wall thickness and door/window size. **Do not use SketchUp's native Scale tool for this behavior** yet.

## Known limitations

- Wall intersections beyond simple pairwise corners and a single tee can still overlap; intersections spanning different stories or containing wall-height differences are not fully resolved.
- 2D symbols are schematic and not construction-ready family libraries. Elevation projections, comprehensive cut representations, and associative drawing output need more development.
- Opening previews use pick helper and screen-space inference, so test under your actual cameras and section cuts.
- The native SketchUp Scale tool is not intercepted. Use ArchiBIM's footprint-resize action instead.
- The plugin has not been verified with live desktop SketchUp or production projects. Check backups, Undo/Redo, edge displays, schedules, and exported IFC before relying on outputs.

## Development and CI

Source: [archibim/](archibim/) · Tests: [test/](test/) · [v0.3 release notes](docs/V0_3_RELEASE_NOTES.md).

GitHub Actions validates Ruby syntax, tests pure-Ruby core geometry, validates the embedded JavaScript, packages an installable RBZ, and uploads a CI build artifact. At publication, the v0.3 test suite contains **25 tests, 55 assertions, 0 failures**. Actual SketchUp visual integration testing is still required.

Files:
- `ArchiBIM.rb`: SketchUp extension loader
- `archibim/main.rb`: model editing, BIM properties, tags, levels, schedules, actions
- `archibim/core.rb`: validation, settings, pure computation
- `archibim/junctions.rb`: pure wall junction math
- `archibim/geometry.rb`: generated 3D and symbolic geometry
- `archibim/tools.rb`: interactive placement tools
- `archibim/ui/panel.html`: BIM Manager interface

The v0.2 installer and archive remain in `dist/` as legacy snapshots. The persistent `dist/ArchiBIM_latest.rbz` URL is intended for ongoing updates.

## Background research

The original design was informed by workflows from Autodesk Revit, Graphisoft Archicad, Vectorworks, Medeek, Profile Builder, PlusSpec, and SketchUp's Ruby API. See [v0.3 release notes](docs/V0_3_RELEASE_NOTES.md) for further details and links.
