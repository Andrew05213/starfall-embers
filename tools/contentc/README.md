# contentc

Deterministic TypeScript compiler for authored project content. The first implemented content set is
the decision register and the Well → Saga vertical slice.

## Commands

Run commands from this directory:

```powershell
npm.cmd ci
npm.cmd run validate
npm.cmd run build
npm.cmd run check
npm.cmd test
```

- `validate` checks JSON Schema and cross-file design invariants without writing files.
- `build` writes deterministic runtime JSON to `content/generated` and readable Markdown to
  `docs/design`.
- `check` fails when generated files are missing or differ from the current authored JSON.
- `test` exercises rejected content cases such as duplicate IDs, missing source references, reversed
  frozen decisions, unique claims for variables, incomplete calibration routes, and invalid revisit
  gates.

`content/src` is the only authoring authority. Do not edit `content/generated` or generated Markdown
files by hand.
