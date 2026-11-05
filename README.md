# ArchiBIM for SketchUp

ArchiBIM is an experimental parametric architectural/BIM extension for SketchUp Desktop, developed by SS Digital Lab.

Version **0.2.0** includes parametric walls and hosted openings, slabs, stairs, roofs, beams, columns, footings, rooms, levels, BIM attributes, schedules and CSV/JSON/IFC handoff. This is an early prototype, **not a Revit or Archicad replacement**, and has not yet been runtime-tested inside SketchUp.

## Installation

Download the `ArchiBIM_v0.2.0.rbz` distribution and open SketchUp Desktop → Extensions → Extension Manager → Install Extension. Start with an empty SKP test model and use the ArchiBIM BIM Manager to create demo elements.

## Development

The repository is intended to contain the unpacked SketchUp extension source (`ArchiBIM.rb`, `archibim/`), tests (`test/`), documentation (`docs/`) and the installable `.rbz` distribution.

Run the calculation tests with:

```shell
ruby test/test_core.rb
```

See the full documentation and research in `docs/`.

**Warning:** Back up your models before testing. BIM geometry and IFC export need verification in SketchUp Desktop.
