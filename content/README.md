# Content pipeline

- `src/`: authored materials, reactions, components, facts, encounters, and localization sources.
- `schemas/`: machine-readable contracts for authored data.
- `generated/`: deterministic output produced by `tools/contentc`; never edit it by hand.

The compiler validates unique IDs, references, physical parameters, terminology, and conflicts
between objective world facts and their narrative presentations. The first active schema set covers
the design decision register and the Well → Saga vertical slice; run `npm.cmd run check` from
`tools/contentc` to verify authored and generated content remain synchronized.
