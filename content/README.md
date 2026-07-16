# Content pipeline

- `src/`: authored materials, reactions, components, facts, encounters, and localization sources.
- `schemas/`: machine-readable contracts for authored data.
- `generated/`: deterministic output produced by `tools/contentc`; never edit it by hand.

The compiler will validate unique IDs, references, physical parameters, terminology, and conflicts
between objective world facts and their narrative presentations.
