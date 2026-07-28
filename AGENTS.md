# Repository guidance

## Scope

This repository contains the game client, engine-independent simulation, content pipeline, tests,
benchmarks, and architecture records for Fallen Stars, Living Matter.

## Non-negotiable boundaries

- Keep `native/sim_core` independent from Godot headers and runtime types.
- Cross the Godot/C++ boundary in batches; never call native code once per pixel.
- Advance authoritative simulation with a fixed timestep and explicit random seeds.
- Treat `content/src` as authored input and `content/generated` as compiler output.
- Add an ADR before changing persistence compatibility or a major ownership boundary.
- Design-source documents and production assets may be committed only with explicit approval from
  the project owner; unapproved or confidential materials must not be committed.
- Store approved large binary files with Git LFS, including every binary type covered by
  `.gitattributes`.
- Keep ZIP archives only when the archive itself is required. Avoid committing both an archive and
  its complete extracted copy; document any approved exception in the reference bundle README.

## Verification

- Native changes: configure, build, and run CTest.
- Godot changes: run a headless project import and `res://tests/demo_smoke.gd`.
- Simulation performance changes: run `res://tests/demo_benchmark.gd` and compare its stress case.
- Content changes: run schema validation and deterministic regeneration when `contentc` exists.
- Performance-sensitive changes: add or update a benchmark; report the tested world size and active
  chunk count.
