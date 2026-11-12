# ArchiBIM

### [⬇️ Download the latest ArchiBIM RBZ](https://github.com/shukritobi/ArchiBIM/releases/latest/download/ArchiBIM_latest.rbz)

**[All releases and older versions](https://github.com/shukritobi/ArchiBIM/releases)** · **[v0.8.1 wall/Scale/passage fixes](docs/V0_8_1_RELEASE_NOTES.md)** · **[Report an issue](https://github.com/shukritobi/ArchiBIM/issues)**

> **Latest download policy:** `ArchiBIM_latest.rbz` always points to the asset in the most recent successful GitHub Release. Whenever changes land on `main`, the [release workflow](.github/workflows/release-rbz.yml) checks the extension, runs tests, packages a new RBZ and publishes it. **The button becomes usable when the first automated release succeeds.** Preview branches and untested changes do not silently replace a release.

**Parametric architectural BIM for SketchUp Desktop.** Design building elements, edit parameters without losing wall or window dimensions, and develop drawing views, CAD handoffs and AI-readable project data in one open-source workflow.

[![GitHub latest release](https://img.shields.io/github/v/release/shukritobi/ArchiBIM?display_name=tag&label=latest%20release)](https://github.com/shukritobi/ArchiBIM/releases/latest) [![Source code](https://img.shields.io/badge/source-GitHub-181717?logo=github)](https://github.com/shukritobi/ArchiBIM) [![License MIT](https://img.shields.io/badge/license-MIT-teal)](LICENSE.txt)

**Current development version:** 0.8.1 repair preview (12 November 2026)  
**Built by:** SS Digital Lab  
**Compatibility:** Designed for SketchUp Desktop; recommended initial testing on SketchUp Pro 2024–2026. SketchUp 2027 and other versions need independent acceptance tests. SketchUp Web does not run Ruby extensions.

---

## Start here

| I want to… | Go to… |
|---|---|
| **Install the plugin** | [Latest RBZ download](https://github.com/shukritobi/ArchiBIM/releases/latest/download/ArchiBIM_latest.rbz) |
| See the newest changes and limitations | [v0.8.0 preview notes](docs/V0_8_0_PREVIEW.md) |
| Learn the existing wall-junction repair | [v0.7.1 release notes](docs/V0_7_1_RELEASE_NOTES.md) |
| Generate floor plans, elevations and sections | [Drawing-set workflow](#architectural-drawing-sets) |
| Work with AutoCAD or LayOut | [2D DXF and LayOut handoff](#cad-and-layout-workflow) |
| Give ChatGPT, Claude or an MCP client access to BIM data | [AI and MCP setup](ai/README.md) |
| Review 11 established BIM/CAD applications | [Research and roadmap](docs/RESEARCH_DRAWINGS_ROOFS_MCP.md) |
| Understand known issues before production use | [Known limitations](#status-and-limitations) |

### Install in SketchUp

1. **Download** `ArchiBIM_latest.rbz` using the link at the top. If no release asset exists yet, visit [Releases](https://github.com/shukritobi/ArchiBIM/releases); do not mistake a source-code ZIP for an installable RBZ.
2. Open **SketchUp Desktop → Extensions → Extension Manager → Install Extension**.
3. Select the downloaded `.rbz`.
4. Open **Extensions → ArchiBIM → ArchiBIM BIM Manager**, or use the ArchiBIM toolbar.
5. Start with a **new test model**, click **Create demo model**, and inspect the wall in **Properties**.

Back up any working `.skp` before trying a preview. The extension is a developing parametric tool, not a certified building documentation or structural engineering solution.

## What's new

<details open>
<summary><strong>v0.8.1 · Wall connection, Scale and doorless opening repair</strong></summary>

- Fixed **Invalid auto_wall_join**: a Boolean model preference was incorrectly interpreted as a number, stopping wall T-junction scans and interfering with repair workflows.
- Improved native SketchUp **Scale** handling via both model transaction and Scale Tool event observers. Handles transformations encoded using the homogeneous matrix scale component and logs detected/rejected repairs.
- **Door → Open passage**: select a hosted door under Properties, enable **Open passage: no frame / no leaf** and update; the wall void remains, but the 3D door/frame/swing disappears. New empty openings can be created from the Door tool preset or the **Add opening** menu.
- Separate **dashed 2D plan and elevation opening outlines** and a corresponding dashed **DXF passage footprint** instead of a door leaf/swing. Quantity takeoffs do not add a door-leaf allowance for an empty passage.
- Diagnostics export full group transformation matrices, accurate Scale factors, element world origin and doorless-opening counts.

**Recommended SketchUp 2026 verification:** Back up your model. Restart SketchUp after installing a new RBZ so stale plugin Ruby is unloaded. Use **Build → Scan all walls** and inspect **Properties → Associative Wall Connections**. Scale a single wall in its length direction, confirm wall thickness and opening width stay unchanged, then test Scale on a copied floor plan. Finally convert an existing door to a passage and check its plan/elevation/DXF representation. If an operation still fails, export **Diagnostics → ArchiBIM testing log** and include the original SKP reference geometry or screenshots.

[Read the failure analysis and acceptance test](docs/V0_8_1_RELEASE_NOTES.md)

</details>

<details open>
<summary><strong>v0.8.0 preview · Drawings, roof choices, CAD and AI integration</strong></summary>

| Area | New capability | Maturity |
|---|---|---|
| **Drawing scenes** | One command creates or updates two floor plans, a roof plan, four elevations, two central sections and two RCP preview scenes when two levels exist | **Preliminary; SketchUp validation required** |
| **2D CAD** | Separate millimetre DXF line drawings for those views with named cut, opening, roof and visible-outline layers | **Prototype; CAD cleanup required** |
| **Roof forms** | Gable, hip, shed/mono-pitch, low-slope/flat, butterfly, saltbox and steel awning roof | **Parametric geometry preview** |
| **Roof structure** | Optional conceptual king-post or Fink steel trusses and steel awning posts | **Non-engineered geometry** |
| **Roof drainage** | Optional box gutters and circular downpipes | **Conceptual geometry; not hydraulically sized** |
| **AI interoperability** | Export a schema-versioned BIM JSON snapshot with stable IDs; optional local, read-only stdio MCP server | **Offline data bridge** |
| **Release downloads** | CI tests the branch and publishes the latest RBZ when changes merge to `main` | **Automated workflow** |

See the **[full v0.8.0 changelog and acceptance checklist](docs/V0_8_0_PREVIEW.md)**.

</details>

<details>
<summary><strong>v0.7.1 · Interior wall connection improvements</strong></summary>

- New T-junctions default to **Linked**, rather than Join Only.
- Host wall-face contact detection respects Left / Center / Right location lines.
- The manager reports touching/broken junctions and exact scan outcomes.
- Existing Join Only connections are **not silently upgraded**; use **Detect / link nearby** or **Link existing T-junctions** explicitly.
- Diagnostics include world coordinates, wall thickness, host-face offsets and scan results.

Read the [v0.7.1 release notes](docs/V0_7_1_RELEASE_NOTES.md), [v0.7 release notes](docs/V0_7_RELEASE_NOTES.md) and [wall test checklist](docs/V0_7_TEST_CHECKLIST.md).

</details>

## Main BIM tools

| Build | Modify / coordinate |
|---|---|
| **Walls** | Reference lines (Left / Center / Right), corners, T-junctions, wall graph and linked moves |
| **Doors & windows** | Hosted casement windows, hinged and sliding doors; editable width, sill, position, frame and swing symbols |
| **Slabs & footings** | Rectangular slabs, stairwell cutouts and parametric concrete pad footings |
| **Beams & columns** | Adjustable dimensions, alignment and elevation offsets |
| **Stairs** | Straight/U-return stairs, landings, handrails and optional upper-slab opening coordination |
| **Roofs & awnings** | Multiple rectangular roof types with pitch, overhang and optional structural/drainage geometry |
| **Levels & rooms** | Floor elevations, level reassignment, room area zones and four-wall room creation |
| **Schedules & exchange** | CSV quantity/cost summaries, JSON export, IFC handoff where SketchUp supports it |

BIM groups carry a persistent `SSDigitalLab_ArchiBIM` attribute dictionary, a stable element ID, dimensions in **millimetres**, and native `AB | ...` tags. Quantities are reported in metres, m² and m³. Cost rates in RM are examples only.

## Architectural drawing sets

Go to **BIM Manager → Export → Generate complete architectural scene set**. ArchiBIM creates or updates named SketchUp scenes that can be placed into **LayOut** as linked viewports.

| Drawing | Code | Two-storey deliverable |
|---|---|---|
| Ground-floor plan | A-101 | Plan cut 1,200 mm above ground-floor level |
| First-floor plan | A-102 | Plan cut 1,200 mm above first-floor level |
| Roof plan | A-103 | Top orthographic roof view |
| North, South, East, West elevations | A-201 to A-204 | Four orthographic building elevations |
| Section A-A, B-B | A-301 and A-302 | Two perpendicular central section cuts |
| Ground-floor reflected ceiling plan | A-401 | Upward-looking **RCP preview** |
| First-floor reflected ceiling plan | A-402 | Upward-looking **RCP preview** |

**Two-storey projects get 11 scenes.** Single-storey projects get 9 scenes: ArchiBIM does not invent an upper floor. Sections initially cut through the building centre and must be positioned to suit the design. **RCP previews do not create ceilings, grids, lights or MEP components**; those still need modeling and documentation.

### CAD and LayOut workflow

- **For LayOut:** Generate the drawing scenes in SketchUp, save the `.skp`, add model viewports in LayOut, set intended drawing scales, and add annotations, hatches, dimensions, section references and title blocks.
- **For AutoCAD / QCAD:** Select **Export → Export 2D drawing set (DXF)**. Each drawing is saved as a separate `.dxf` with **millimetres at 1:1**, using layers such as `AB_2D_CUT`, `AB_2D_VISIBLE`, `AB_2D_OPENINGS`, and `AB_2D_ROOF`.
- **Before issuing drawings:** Verify section locations, obscured lines, levels, dimension strings, dashed-line types, floor/ceiling heights, drawing scale, edge overlaps and roof connections in the target CAD app.

**Important:** DXF export currently projects model faces and computes basic section intersections. It does **not** yet provide production-grade hidden-line removal, fully associative dimensions, elevations with automatic annotations, accurate fixture-based RCPs or polished title blocks. The 2D drawing system is an editable starting point.

## Roofs, steelwork and drainage

The Roof tool supports a rectangular footprint with editable dimensions, pitch, buildup thickness, overhang and eave offset.

| Roof family | Included in v0.8 preview | Future work |
|---|---|---|
| Gable and hip | Existing parametric baseline | Better ridge/hip edge detailing |
| Shed / mono-pitch | New | Independent wall-attached / freestanding variants |
| Low-slope / flat | New | Per-edge drainage falls and parapets |
| Butterfly / inverted gable | New | Proper internal valley gutter and outlets |
| Saltbox / asymmetric gable | New | Per-plane independent pitches |
| Steel awning | New basic posts and steel framing | Brackets, purlins, connection types, supports |
| King-post and Fink truss | New conceptual geometry | Member families, gussets, bracing, structural analysis |
| Box gutter and circular downpipe | New optional geometry | Variable falls, elbows, connection to eave, sizing |
| Mansard, gambrel, cross-gable, curved roofs, dormers | **Research/roadmap only** | Polygonal roof solver and multi-plane intersection |

Roof truss sizes, post spacing and gutter/downpipe options are illustrative, **not structural or drainage designs certified against local requirements**. The [roof research document](docs/RESEARCH_DRAWINGS_ROOFS_MCP.md) covers the full taxonomy and architecture for future modeling.

## AI-ready: ChatGPT, Claude, Gemini and MCP

**Easiest option:** In **Export**, click **Export AI-readable JSON**. Give the `ArchiBIM_AI.json` file to ChatGPT or another AI model. The file includes level IDs/elevations, element IDs, BIM parameters, world positions, and drawing references. Example prompts:

- “List all first-floor walls, thicknesses, windows and hosted doors.”
- “Identify roof settings and downpipe sizes and list anything that requires engineering review.”
- “Check whether my drawing manifest includes A-101 through A-402.”

For AI applications supporting **local Model Context Protocol clients**, see the [offline read-only MCP server](ai/README.md) in `ai/mcp_server.py`. It offers tools for model summary, levels, elements, element lookup and drawings. It reads one exported JSON file; **it does not control a live SketchUp model, make writes or transmit data automatically**.

Schema: [`ai/archibim-snapshot.schema.json`](ai/archibim-snapshot.schema.json). Future improvements include an optional local-only live bridge with explicit user approval and Undo-safe operations.

## Editing and wall-connectivity rules

- Select an ArchiBIM element and change parameters through **Properties** to keep thickness and hosted geometry correct.
- For associative wall movement, use **Move connected wall**. Direct SketchUp Move does **not** propagate the linked wall graph.
- Native SketchUp Scale can initiate a separate automatic **Repair after Scale** operation. Confirm the result before continuing; do not explode parametric groups.
- Wall joints have **Linked / Join Only / Unlinked** modes. Older explicitly Join Only and Unlinked objects are not silently changed.
- Edit or move hosted openings through their parent wall properties; manually placed geometry inside a wall group may be replaced during regeneration.
- Revisit **Diagnostics → Export ArchiBIM testing log** after unexpected edits, gap detection, incorrect roof faces or drawing exports.

## Tests and source layout

```text
ArchiBIM.rb                    SketchUp Ruby extension loader
archibim/main.rb               BIM model, settings, inspector callbacks and exports
archibim/core.rb               Pure Ruby dimensions and validation
archibim/geometry.rb           3D solids, roofs, doors, windows and detailing
archibim/documentation.rb      Floor plans, elevations, sections and RCP scenes
archibim/dxf_export.rb         Layered preliminary 2D CAD drawings
archibim/wall_graph.rb         Associative wall constraints and junctions
archibim/connected_move.rb     Safe connected-wall interaction
archibim/repair.rb             Native Scale normalization
archibim/diagnostics.rb        Detailed local log export
archibim/ui/panel.html         Interactive BIM Manager
ai/mcp_server.py               Offline read-only MCP server
ai/archibim-snapshot.schema.json
test/                          Pure Ruby regression tests
.github/workflows/release-rbz.yml
```

Run local calculation tests with Ruby and Python installed:

```sh
ruby -e 'Dir["test/test_*.rb"].sort.each { |f| require_relative f }'
python3 -m unittest discover -s ai -p 'test_*.py'
```

CI performs Ruby syntax checks, tests, installer ZIP validation and release packaging. Geometry rendering, UI actions, DXF accuracy and IFC exchange still require testing **inside SketchUp Desktop** and independent CAD verification.

## Status and limitations

ArchiBIM is an **early working prototype**. There is no claim of full Revit/Archicad parity. Important outstanding features include full multi-way wall joins; general polygon roof plane/valley solving; dormers and curved roofs; ceiling families and reliable RCP linework; mature hatching/hidden-line CAD extraction; linked dimensions and professional drawing sheets; structural/drainage sizing; hosted MEP; native RVT/PLN exchange; lossless IFC roundtrips; and a permissioned live SketchUp MCP editing bridge.

**Do not use preliminary exports or roof/steel geometry as construction documentation without independent checking.**

## License and contributions

Original code is released under the [MIT License](LICENSE.txt). Research references are for workflow comparison, not copied proprietary code.

Use [GitHub Issues](https://github.com/shukritobi/ArchiBIM/issues) for logs, screenshots and reproducible examples. For every update to `main`, the latest passing build is intended to appear at the **download button at the top of this README**.
