# Architectural drawing, roof and AI interoperability research

Research date: 12 November 2026. This is a design study, **not** a claim that ArchiBIM has already achieved feature parity with these applications.

## Ten comparable BIM/CAD platforms, plus SketchUp/LayOut

| Platform | Verified workflow | Adaptation for ArchiBIM |
|---|---|---|
| [Autodesk Revit](https://help.autodesk.com/cloudhelp/2026/ENU/Revit-DocumentPresent/files/GUID-8B1294DC-617E-48F9-AC18-A998F43384C9.htm) | Model-backed plan, RCP, section, elevation, callout and sheets; roof from footprint, extrusion or mass | Named views keyed to level and section reference; separate view range, line visibility and sheet data |
| [Graphisoft Archicad](https://help.graphisoft.com/AC/30/INT/Topics/150_UserInterfaceToolSettings/150_UserInterfaceToolSettings-4.html) | Single-/multi-plane roofs with multiple pitch tiers and individual-plane overrides; projected roof outlines | Explicit roof plane graph, hips/ridges/valleys and per-edge slope attributes |
| [Vectorworks Architect](https://app-help.vectorworks.net/2026/eng/VW2026_Guide/Roofs/Creating_roof_objects.htm) | Roofs generated from walls/polygons, editable eave profile and roof framing; horizontal/vertical section viewports | Separate roof outline, panel composition, eaves, rafter/purlin parts, and independently styled viewports |
| [Chief Architect](https://www.chiefarchitect.com/products/features/) | Auto-rebuild gable, hip, shed, Dutch gable, gambrel and mansard roofs; fascia/gutters/trusses | Optional regeneration triggered by source wall footprint changes; mark user overrides as locked |
| [ALLPLAN](https://help.allplan.com/Allplan/2027-0/1033/Allplan/6494.htm) | Roof reference planes for shed, gable, mansard, barrel and combined roof forms | Use datum-based roof profiles and elevations rather than hard-coded disconnected meshes |
| [BricsCAD BIM](https://helpcenter.bricsys.com/en-us/document/command-reference/b/bimsection-command?version=V26) | Plan, elevation, section, detail and **reflected ceiling** section entities; generated DWG drawings | Drawing-set manifest and repeatable layers; selectable cutting plane; update instead of duplicating |
| [FreeCAD BIM + TechDraw](https://github.com/FreeCAD/FreeCAD-documentation/blob/main/wiki/BIM_Workbench.md) | Section planes, projected shape views, annotated sheets; DXF/SVG/PDF via TechDraw | CAD-friendly line geometry with separate object IDs and view projections |
| [Bonsai / IfcOpenShell](https://docs.bonsaibim.org/studio/guides/drawings/index.html) | IFC-native models linked to SVG-based architectural drawings and annotation | Open structured BIM JSON and IFC-aligned identity; no plugin lock-in |
| [VisualARQ](https://www.visualarq.com/feature/documentation/) | Linked 2D plans/sections/elevations, RCP and DWG export; refresh after model changes | Keep generated views distinct and refreshable, not copied loose lines |
| [Tekla Structures](https://help.trimble.com/doc/tekla-structures/2026/dra_drawing_contents) | Model-dependent structural and fabrication drawings with mark/dimension settings | Truss member IDs, assembly marks, shop-drawing schema and change tracking |
| [SketchUp + LayOut](https://sketchup.trimble.com/en/products/layout) | Orthographic scenes, section cuts, scaled viewports, associative annotations, DWG/DXF/PDF outputs | Native scene-first documentation and DWG/DXF/PDF handoff using LayOut |

Additional reference: [Graphisoft RoofMaker](https://support.graphisoft.com/hc/en-us/articles/29112701654417-How-do-I-model-the-structures-within-a-roof) automates rafters/purlins, and [Vectorworks Roof Framer](https://app-help.vectorworks.net/2026/eng/VW2026_Guide/Structural/Framing%20a_roof.htm) distinguishes framing members from roof finishes.

## Architectural drawing deliverables

Target starting set (two-storey house):

| Drawing | Suggested code | Cut/view logic | Required annotation |
|---|---|---|---|
| Ground-floor plan | A-101 | Ground level +1,200 mm cutting plane, look down | Walls, doors, swings, windows, stair, grids, dimensions, levels |
| First-floor plan | A-102 | First level +1,200 mm, look down | Above/below line-type rules, openings, stairs, dimensions |
| Roof plan | A-103 | Top-down roof projection | Ridges, hips, valleys, pitch arrows, gutters, outlets |
| North/South/East/West elevations | A-201 to A-204 | Ortho vertical view with consistent facade orientation | Ground line, materials, building heights, levels, opening graphics |
| Section A-A / B-B | A-301 / A-302 | Two perpendicular vertical cuts, deterministic section markers | Slab depths, walls, stairs, roof buildup, headroom |
| Ground-floor RCP | A-401 | Reflected soffit/ceiling view from ground level | Ceiling boundaries/heights, luminaires, grids, diffusers |
| First-floor RCP | A-402 | Reflected soffit/ceiling view from first level | Same, with roof/ceiling conditions |

**Important limitations:** A scene without ceiling components is not an accurate RCP. A simple section scene is not a linework extraction engine. Never label placeholder ceiling fixtures, line hatches, or dimensions as construction-ready automatically. Plans for a missing second level must be labeled as unavailable rather than fabricated.

### CAD line hierarchy

- `AB_2D_CUT`: heavy elements intersected by cut plane
- `AB_2D_VISIBLE`: medium visible outlines
- `AB_2D_OVERHEAD`: dashed above-cut geometry
- `AB_2D_HIDDEN`: dashed obscured geometry
- `AB_2D_OPENINGS`: door leaves/arcs and window markers
- `AB_2D_ROOF`: roof outlines/ridges/pitch symbols
- `AB_2D_DRAINAGE`: gutter/downpipe runs and outlets
- `AB_2D_STRUCTURE`: steel members/columns and trusses
- `AB_2D_GRID`, `AB_2D_DIM`, `AB_2D_TEXT`, `AB_2D_SECTION`: annotations

Use mm at 1:1 in model space, distinct reference levels and IDs, and layer-by-layer visibility in both LayOut and CAD. DXF should preserve line type and coordinates where supported; fit/print scales belong to viewports, not rescaling model elements.

## Roof form family taxonomy

- **Starter planar forms**: flat/low-slope (drain falls required), shed/mono-pitch, gable, hip, pyramid hip, butterfly/inverted gable
- **Asymmetrical and compound**: saltbox, Dutch gable, cross-gable, cross-hip, L-hip, intersecting roofs with valleys, clerestory
- **Multi-pitch**: gambrel, mansard, bonnet, jerkinhead/half-hip, raised heel
- **Curved/special**: barrel vault, sawtooth, butterfly with internal valley, curved/arched roof, conical, folded plate, green roofs
- **Accessories**: fascia, soffit, ridge caps, flashing, insulation assembly, rooflights, dormers, parapets

**Algorithmic approach:** start from a closed plan polygon with constraints. Construct topological roof edges, assign slopes and edge types, intersect 3D roof planes, trim to ridges/hips/valleys, and compute buildable planar faces. Avoid generating each panel independently without topological adjacency: duplicated seams, broken normals and overlaps will result. For clipped/non-orthogonal footprints support manual roof-plane overrides before automatic roof solving.

## Steel awnings and trusses

Steel awning should be a separate parametric assembly, not simply a slab material switch. Properties: wall-attached/freestanding, length, projection, elevation, slope, support posts, support brackets, steel profiles (SHS/RHS/CHS/I/H), purlin spacing, panel buildup, flashing, gutters and outlets. Treat cantilevered brackets as conceptual geometry until structural checks are done.

Truss families: king post, queen post, Fink/W, Howe, Pratt, Warren, fan, mono-pitch, scissor, parallel chord, bowstring. Define support nodes, panel-point spacing, chords, web topology, member section and orientation. Use structural centerline math, not freehand extrusion. Deduplicate gusset plates and avoid collisions. Geometry does **not** establish member capacity: engineering/connection design remains separate.

## Rainwater collection

Gutter systems must be attached to roof eave edges, not arbitrary world XYZ lines. Options: half round, box, quad, concealed/valley gutter. Parameters: width/depth, material thickness, fall (mm/m), flow direction, outlet count and coordinates, brackets, end caps, expansion joints. Downpipes: round/rectangular profile, diameter, wall clearance, bends, shoe/discharge elevation and alignment to selected outlet. Validate drainage capacity and slopes against applicable local standards (do not invent design compliance).

## AI and MCP architecture

**Stage 1 (safe read-only, portable):** Stable machine-readable JSON schema with `schema_version`, model and units, level IDs/elevations, elements with persistent IDs/type/parameters, openings, roof systems, drawings, warnings and source-model revision. Ship a JSON Schema and examples. A GPT/Claude/Gemini integration can ingest this exported file with no live model access.

**Stage 2 (local MCP bridge):** Standard MCP tools such as `list_levels`, `list_elements`, `get_element`, `get_drawings`, `validate_model` and `export_drawing_set`. Start read-only over stdio with a user-selected file, not a publicly exposed TCP endpoint. For write methods, require a model-backed transaction, explicit user approval, whitelist of parameters, strict validation, local-only transport and undo support. Every write must be logged with AI agent and before/after values. See [MCP tool specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

**Stage 3 (live SketchUp adapter):** Local tool dispatcher with authentication and nonblocking main-thread execution. An independent MCP client/server can request queued operations while SketchUp pumps the Ruby UI event loop. Do not run a network listener inside an extension as a default or silently expose a model.

## Definition of done and tests

1. **Drawings:** All eleven views regenerate without duplicate pages or section-plane corruption; verify both levels independently, orientation and line weights, hatches and dimensions.
2. **Roofing:** Exact footprint/eaves under parameter edits; solid faces with correct normals; no gaps at ridge/hip/valley; plan/section representations match 3D.
3. **Structure/drainage:** Instance IDs persist through regeneration and scaling; gutters follow roof eaves; truss node geometry stays attached.
4. **CAD export:** Import exported DXF into AutoCAD/QCAD, verify millimetre scale, 1:1 dimensions, layer names and dashes, visible roof detail and section outlines.
5. **MCP:** Validate JSON schema, hostile payloads, permission gates, undo/redo and read-only mode; confirm no data leaves computer without requested export.
6. **Release:** Ruby syntax, tests, package structure, RBZ install/uninstall in supported SketchUp versions, and latest release download link.
7. **Compatibility:** SketchUp 2024–2027 and LayOut where available, using explicit runtime validation rather than assuming compatibility.

## Recommended sequencing

**P0:** Trusted latest-RBZ publication, release notes, repeatable tests and accessible documentation.  
**P1:** Coordinated scene-set generator (2 plans, roof, 4 elevations, 2 sections, 2 RCP previews), with a clearly documented lack of ceiling families.  
**P2:** Native layered DXF linework generated from model semantics including cut graphics, true section clipping and SVG previews.  
**P3:** Polygon roof plane solver; slope override; hip/valley adjacency; edge-driven fascia/gutters/downpipes.  
**P4:** Parametric steel awnings/trusses; capacity and collision validation; structural exports.  
**P5:** MCP read bridge, then opt-in transactional modification commands.  

These stages separate verified functionality from prototypes and protect existing ArchiBIM wall, opening and Scale repair behavior.
