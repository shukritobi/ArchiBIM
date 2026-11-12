# ArchiBIM v0.8.0 preview: Documentation, Roofs and AI bridge

**12 November 2026** · Feature branch preview, not yet accepted in SketchUp Desktop.

## New in this preview

- **Drawing set scenes**: the Export panel can create/update eleven named SketchUp/LayOut scenes on a two-level model: ground-floor and first-floor plans, roof plan, four exterior elevations, two perpendicular building sections and two reflected-ceiling previews. A one-level model produces nine scenes; missing levels are never fabricated.
- **Layered DXF baseline**: separate files named A-101 to A-402, exported in millimetres. Uses BIM face mesh sections and orthographic edge projection, with distinct cut/visible/roof/opening layers. Does **not** solve hidden edges, full hatch fills, automatic dimensions, title blocks or production-quality RCP.
- **Roof choices**: existing gable/hip plus shed, low-slope/flat fall, butterfly, saltbox and a steel-framed awning prototype, all edited via the roof inspector.
- **Roof add-ons**: optional square-section gutters and circular downpipes; conceptual king-post or Fink/W steel trusses under gable/saltbox roof; option for awning front posts. Dimensions and regeneration are parametric; **do not treat as engineered drainage or structural design**.
- **AI interoperability**: opt-in export of a versioned, read-only JSON model snapshot including levels, element identity, parameters, world origins and drawing codes. Includes a JSON schema and offline MCP stdio server in `ai/`; no automatic upload or external connection.
- **Installer link**: README top links to `/releases/latest/download/ArchiBIM_latest.rbz`. GitHub Actions runs Ruby syntax, calculation tests and MCP tests before packaging and posting a release from the merged main branch.

## Correct use

1. Create a copy of your SKP file. Install a published RBZ through SketchUp Extension Manager.
2. Add ground and first levels if appropriate; model walls/doors/windows, slabs and roof.
3. From Export, choose **Generate complete architectural scene set**. Review the cut locations (sections A-A/B-B start at building midpoint) and roof viewport.
4. Use **Export 2D drawing set (DXF)** for editable CAD geometry and check each layer in AutoCAD/QCAD. Units are mm at 1:1. Clean up hidden lines, annotations, fixtures, roof detail and line weights.
5. Use **Export AI-readable JSON** and upload it to ChatGPT or point the offline MCP server to it.
6. After testing, export ArchiBIM Diagnostics and attach any faulty scenes / geometry screenshots to the issue or PR.

## Known limitations and mandatory regression checks

- Roofs still use rectangular footprint inputs. No arbitrary polygon roof solver, L-shaped cross roofs, valley trimming, dormers, rooflights or curved panels yet.
- Gutter geometry is conceptual; falls, brackets, elbows, head losses, pipe sizing, hydraulic sizing and code compliance are **not** implemented.
- Trusses are conceptual SHS forms. Engineering, bracing, member capacity, welded joints, gusset plates, connections and all loads are **not** designed or checked.
- The standalone awning is a roof type, not a dedicated independent multi-segment awning-hosting tool.
- 2D drawing coordinates are projected from modeled geometry. The hidden-line, annotative drawing, RCP ceiling-family, roof plane intersection, complete section hatch and DXF import-roundtrip systems remain outstanding.
- Exported MCP snapshot is read-only and not a live SketchUp editor; exported JSON must be refreshed after model changes.
- **Manual SketchUp acceptance testing is required**, including rollback/Undo, line styles, two-storey scene switching, geometry rebuild after edits, IFC and export in AutoCAD/LayOut.

## Source and research

[11-platform comparative research and engineering roadmap](RESEARCH_DRAWINGS_ROOFS_MCP.md) · [AI/MCP read-only server instructions](../ai/README.md) · [v0.7.1 wall junction repair](V0_7_1_RELEASE_NOTES.md)

**Build policy:** The stable latest-RBZ link is updated by publishing a new GitHub Release on successful `main` CI. A feature branch PR is *not* an installed release. Do not announce the RBZ as downloadable until the corresponding release asset is visible.
