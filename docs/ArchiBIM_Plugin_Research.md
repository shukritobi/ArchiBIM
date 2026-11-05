# ArchiBIM competitive study and product direction

Research checked: 4 November 2026. The descriptions below are based on public developer listings and official documentation, not inspection of proprietary source code.

## Similar tools investigated

| Tool | Approach / verified capabilities | Architectural principle to apply |
|---|---|---|
| [PlusSpec / PlusDesignBuild](https://plusspec.com/tools/) | Parametric wall tools, redefine/split walls, windows, schedules/estimating, IFC classification | Maintain object identity and linked apertures when editing a wall |
| [Medeek Wall](https://extensions.sketchup.com/extension/e662b5c8-28ec-48e2-b26f-d7f72550787d/medeek-wall) and [Medeek Project](https://extensions.sketchup.com/extension/5d5f9c25-a802-4e04-b2c2-fe724405d302/Medeek-Project) | Structural framing, doors/windows and adjacent trade extensions, project management | Separate trade tools but share a consistent BIM data store |
| [MUZWalls](https://extensions.sketchup.com/extension/6b0b6987-88a7-45e4-a34a-e92ed845aa9e/muzwalls-parametric-wall-design) | 2026 parametric walls, openings, roofs, concrete structures, takeoff reports, various framing/finishing details | Treat generated mesh as a **view** of persistent parameters and regenerate on edit |
| [Profile Builder 4](https://extensions.sketchup.com/extension/b7732b43-9d0f-4c84-9b3c-e1028008936a/Profile-Builder-4) | Parametric repeated profiles and assembly-driven workflows | Create reusable parametric assembly archetypes, not hand-edited loose faces |
| [Quantifier Pro](https://extensions.sketchup.com/extension/d957b024-d6ee-4534-a4d8-194b91ecf8e5/quantifier-pro) | Reports cost, area, length, volume, weight | Independent, deterministic quantity calculation from structured data |
| [Skalp](https://www.skalp4sketchup.com/) | Live section faces, hatching, LayOut/DXF workflows | Section-scenes should be first-class deliverables; hatches and sheet automation are next |
| [Skema](https://extensions.sketchup.com/extension/e12e7dd0-fc92-438d-b605-e78f4ccf28aa/skema-for-sketch-up) | SketchUp / Revit synchronization and BIM handoff | Distinguish basic IFC export from actual bidirectional BIM interoperability |
| [BIM Utilities2026](https://sketchucation.com/plugin/2883-bimutilities2025) | Classification and quantity property sets for IFC and LayOut labels | Use formal IFC property sets / quantity sets in a later release |

## SketchUp official architecture references

- [Ruby API: generating geometry](https://ruby.sketchup.com/file.generating_geometry.html): `Entities#add_face`, `Face#pushpull`, groups.
- [Entity attributes](https://ruby.sketchup.com/Sketchup/Entity.html): persistent attribute dictionaries.
- [HtmlDialog](https://ruby.sketchup.com/UI/HtmlDialog): two-way HTML/JS callbacks.
- [PickHelper](https://ruby.sketchup.com/Sketchup/PickHelper.html): identify clicked nested groups.
- [SectionPlane](https://ruby.sketchup.com/Sketchup/SectionPlane.html) and [Page](https://ruby.sketchup.com/Sketchup/Page.html): section scenes and model documentation.
- [Model#export](https://ruby.sketchup.com/Sketchup/Model.html) and [export options](https://ruby.sketchup.com/file.exporter_options.html): version-dependent IFC support.
- [SketchUp help: IFC import/export](https://help.sketchup.com/en/importing-and-exporting-ifc-files): interoperability caveats. SketchUp 2026 introduced the newer native IFC exporter option set.
- [SketchUp TestUp](https://github.com/SketchUp/testup-2): native host test runner.

## Build design decisions

- **Pure Ruby computational core:** validates dimensions and openings, computes net/gross areas and volumes independent of SketchUp GUI.
- **Geometry as derivative state:** all ArchiBIM shapes are regenerated from parameters stored in attribute dictionaries rather than editing arbitrary native mesh topology.
- **Hosted wall openings:** an x/z cell partition generates front/back faces and aperture returns; child doors/windows are regenerated together with their wall.
- **Units:** parameters stored in mm and converted to SketchUp internal inch values at the geometry boundary; data exports use explicit m/m²/m³.
- **Project state:** story/level registry and unit costs live on SketchUp Model attributes; elements carry level IDs so story name/elevation changes can be reflected.
- **Native SketchUp UX:** HtmlDialog, custom input tools, Toolbar, extensions menu, Scenes and SectionPlanes; no external backend or paid API dependencies.
- **Interoperability:** IFC annotations and exporter hooks are included, but IFC4 property sets, GUID matching and semantic validation are deliberately not claimed as complete.

## Feature status and roadmap

| Capability | 0.2.0 status | Planned next stage |
|---|---|---|
| Walls / rectangular holes | Basic parametric with rebuild | Joined endpoints, joins, curved walls, compound layers and profiles |
| Hosted doors/windows | Rectangular with basic visual leaf/glass | Configurable families, schedules, types, swing and hardware |
| Levels, stairs, structure | Basic | Structural grids, landings, stairs validation, trusses |
| Roof / footings | Gable roof and pad footings | Roof editing by plane, roof holes, hip / valley and engineered footing families |
| Room zones | Manual rectangle | Closed-loop room recognition and finish assignments |
| Drawings | Top-down section cut scenes | Live annotated floor plan/section/elevation sheets, LayOut titleblocks, DXF |
| Cost / schedules | CSV, JSON, simple RM rates | BIM property-set schedules, material layers, cost assemblies, XLSX |
| IFC | Native one-way exporter call | Versioned schema support, property sets, verified classes and robust round-tripping |
| Collaboration | None | Element revisioning, model compare, issue tracker, optional project database |
| Reliability | Core unit tests and static checks | Real SketchUp TestUp suite, UI automation, QA on 2024–2026 and Windows/Mac |

### Recommended implementation sequence for a production-grade release

1. **Host runtime QA and wall join engine**. Confirm solid/manifold geometry, robust holes, and geometry update on native transforms. Solve wall connectivity and adjacent wall trimming before piling on decorative families.
2. **Object and material type system**. Wall types with finish/plaster/core thickness and quantity takeoffs; door and window family definitions with handing and type catalog.
3. **Associative documentation**. Plans, sections, elevations, markers, dimensions and branded A3/A1 LayOut sheets linked to model revisions.
4. **Validated IFC / Revit handoff**. Create correct IFC type mapping + complete quantity and property sets; test IFC4 exchange with BIMvision and other BIM viewers and Revit importer.
5. **Model management**. Phases, design options, assemblies, site, roof solids and MEP coordination.

## Why this is not called 'full Revit in SketchUp'

Revit/Archicad's family engines, systems, drawing/annotation coordination, discipline objects, IFC exchange, linked model management and collaborative revisioning require a much larger tested software ecosystem. A functional single-user foundation can be built as a Ruby extension, but a production-grade substitute is a multi-stage engineering project.
