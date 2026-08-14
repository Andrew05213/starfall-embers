import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

import {
  type DecisionRegister,
  type Slice,
  type AssetCatalog,
  validateSchemas,
  validateSemantics
} from "../src/index.js";

const root = resolve(import.meta.dirname, "../../..");
const register = JSON.parse(
  readFileSync(resolve(root, "content/src/design/decision-register.json"), "utf8")
) as DecisionRegister;
const slice = JSON.parse(
  readFileSync(resolve(root, "content/src/slices/well-saga-first-slice.json"), "utf8")
) as Slice;
const catalog = JSON.parse(
  readFileSync(resolve(root, "content/src/assets/saga-concept-candidates.json"), "utf8")
) as AssetCatalog;

function clone<T>(value: T): T {
  return structuredClone(value);
}

test("accepts the canonical decision register, first slice and Saga catalog", () => {
  assert.doesNotThrow(() => validateSchemas(register, slice, catalog));
  assert.doesNotThrow(() => validateSemantics(register, slice, catalog));
});

test("rejects incomplete, production, unisolated and alpha-missing Saga candidates", () => {
  const missing = clone(catalog);
  missing.assets.pop();
  assert.throws(() => validateSemantics(register, slice, missing), /missing required Saga candidate/);

  const production = clone(catalog);
  (production.assets[0] as unknown as Record<string, unknown>).status = "production-ready";
  assert.throws(() => validateSchemas(register, slice, production), /asset catalog schema/);

  const unisolated = clone(catalog);
  unisolated.assets[0].source_path = "game/assets/saga_outer_day_city.png";
  assert.throws(() => validateSemantics(register, slice, unisolated), /candidate may not reference game\/assets/);

  const missingAlpha = clone(catalog);
  missingAlpha.assets.find((asset) => asset.kind === "device")!.alpha_processing = "not-applicable";
  assert.throws(() => validateSemantics(register, slice, missingAlpha), /missing alpha processing/);

  const wrongSize = clone(catalog);
  wrongSize.assets.find((asset) => asset.kind === "character")!.target_size = {
    width: 160,
    height: 90,
    concept_aspect: "wrong"
  };
  assert.throws(() => validateSemantics(register, slice, wrongSize), /wrong target size/);
});

test("rejects duplicate decision ids", () => {
  const invalidRegister = clone(register);
  invalidRegister.decisions.push(clone(invalidRegister.decisions[0]));
  assert.throws(() => validateSemantics(invalidRegister, slice), /duplicate decision id/);
});

test("rejects missing decision source references", () => {
  const invalidRegister = clone(register);
  invalidRegister.decisions[0].source_refs = ["docs/design/does-not-exist.md"];
  assert.throws(() => validateSemantics(invalidRegister, slice), /missing decision source reference/);
});

test("rejects a slice that reverses a frozen decision", () => {
  const invalidSlice = clone(slice);
  const claim = invalidSlice.decision_claims.find((entry) => entry.decision_id === "saga.primary-resolution.rotation-calendar");
  assert.ok(claim);
  (claim.value as Record<string, unknown>).core_removed = true;
  assert.throws(() => validateSemantics(register, invalidSlice), /slice reverses frozen decision/);
});

test("rejects a slice that makes a variable decision unique", () => {
  const invalidSlice = clone(slice);
  invalidSlice.decision_claims.push({
    decision_id: "furnace.final-endings",
    value: "renew-furnace",
    asserts_unique: true
  });
  assert.throws(() => validateSemantics(register, invalidSlice), /slice makes variable decision unique/);
});

test("rejects an incomplete rotation calendar and an invalid revisit gate", () => {
  const invalidSlice = clone(slice);
  const journey = invalidSlice.journey as Record<string, unknown>;
  const calendar = journey.rotation_calendar as Record<string, unknown>;
  (calendar.required_sequence as unknown[]).pop();
  assert.throws(() => validateSemantics(register, invalidSlice), /three canonical calibrations/);

  const invalidRevisit = clone(slice);
  const revisit = (invalidRevisit.journey as Record<string, unknown>).revisit as Record<string, unknown>;
  ((revisit.entry_requirements as Record<string, unknown>).minimum_travel_ticks) = 0;
  assert.throws(() => validateSemantics(register, invalidRevisit), /requires one travel tick/);
});
