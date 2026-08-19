import { Ajv2020 } from "ajv/dist/2020.js";
import { type ErrorObject } from "ajv";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

type JsonObject = Record<string, unknown>;

export type Decision = {
  id: string;
  title: string;
  status: "frozen" | "provisional" | "variable" | "rumor" | "forbidden";
  version: string;
  source_refs: string[];
  canonical_value: unknown;
  constraints: string[];
  affected_content: string[];
  change_reason: string;
  acceptance_criteria: string[];
};

export type DecisionRegister = { schema_version: 1; decisions: Decision[] };

type DecisionClaim = { decision_id: string; value: unknown; asserts_unique: boolean };

export type Slice = {
  schema_version: 1;
  id: "well-saga-first-slice";
  title: string;
  version: string;
  decision_claims: DecisionClaim[];
  starting_state: JsonObject;
  journey: JsonObject;
  asset_specs: JsonObject[];
};

export type ConceptAsset = {
  id: string;
  location_id: string;
  kind: "environment" | "device" | "character";
  purpose: string;
  target_size: { width: 160 | 64; height: 90 | 64; concept_aspect: string };
  status: "concept-candidate";
  prompt: string;
  source_path: string;
  variants: string[];
  alpha_processing: "not-applicable" | "chroma-key-removed";
  audit: { conclusion: "approved-concept-candidate" | "needs-regeneration"; checks: string[] };
  prohibited_integration_reason: string;
};

export type AssetCatalog = {
  schema_version: 1;
  catalog_id: "saga-concept-candidates";
  title: string;
  assets: ConceptAsset[];
  planned_variants?: { id: string; status: "specification-only"; prompt: string }[];
};

type Output = { path: string; content: string };

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDirectory, "../../..");
const contentRoot = join(root, "content");

function readJson(path: string): JsonObject {
  return JSON.parse(readFileSync(path, "utf8")) as JsonObject;
}

function stable(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stable).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as JsonObject).sort(([left], [right]) => left.localeCompare(right));
    return `{${entries.map(([key, entry]) => `${JSON.stringify(key)}:${stable(entry)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function formatJson(value: unknown): string {
  return `${JSON.stringify(JSON.parse(stable(value)), null, 2)}\n`;
}

function formatErrors(errors: ErrorObject[] | null | undefined): string {
  return (errors ?? []).map((error) => `${error.instancePath || "/"} ${error.message ?? "is invalid"}`).join("; ");
}

function requireCondition(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

export function validateSchemas(register: DecisionRegister, slice: Slice, catalog?: AssetCatalog): void {
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const registerSchema = readJson(join(contentRoot, "schemas", "decision-register.schema.json"));
  const sliceSchema = readJson(join(contentRoot, "schemas", "vertical-slice.schema.json"));
  const catalogSchema = readJson(join(contentRoot, "schemas", "asset-catalog.schema.json"));
  const validateRegister = ajv.compile(registerSchema);
  const validateSlice = ajv.compile(sliceSchema);
  const validateCatalog = ajv.compile(catalogSchema);
  requireCondition(validateRegister(register), `decision register schema: ${formatErrors(validateRegister.errors)}`);
  requireCondition(validateSlice(slice), `vertical slice schema: ${formatErrors(validateSlice.errors)}`);
  if (catalog) {
    requireCondition(validateCatalog(catalog), `asset catalog schema: ${formatErrors(validateCatalog.errors)}`);
  }
}

export function validateSemantics(register: DecisionRegister, slice: Slice, catalog?: AssetCatalog): void {
  const decisionById = new Map<string, Decision>();
  for (const decision of register.decisions) {
    requireCondition(!decisionById.has(decision.id), `duplicate decision id: ${decision.id}`);
    decisionById.set(decision.id, decision);
    for (const sourceRef of decision.source_refs) {
      requireCondition(existsSync(join(root, sourceRef)), `missing decision source reference: ${sourceRef}`);
    }
  }

  for (const claim of slice.decision_claims) {
    const decision = decisionById.get(claim.decision_id);
    requireCondition(decision, `slice references unknown decision: ${claim.decision_id}`);
    if (decision.status === "frozen") {
      requireCondition(stable(claim.value) === stable(decision.canonical_value), `slice reverses frozen decision: ${decision.id}`);
    }
    requireCondition(!(decision.status === "variable" && claim.asserts_unique), `slice makes variable decision unique: ${decision.id}`);
  }

  const journey = slice.journey as JsonObject;
  const departure = journey.well_departure as JsonObject;
  const calendar = journey.rotation_calendar as JsonObject;
  const revisit = journey.revisit as JsonObject;
  const sequence = calendar.required_sequence as JsonObject[];
  const calibrationIds = sequence.map((entry) => entry.id);
  requireCondition(
    stable(calibrationIds) === stable(["outer-light-clock", "inner-tide-clock", "neutral-free-gyroscope"]),
    "rotation calendar must require the three canonical calibrations in order"
  );
  requireCondition(departure.route_id === "repair-old-ship", "slice must begin with the repaired old ship route");
  const resolution = calendar.resolution as JsonObject;
  const stateChanges = resolution.state_changes as JsonObject;
  requireCondition(stateChanges["saga.core_removed"] === false, "rotation calendar cannot remove Saga's core");
  requireCondition(stateChanges["saga.witness.category"] === "gravity-and-direction", "Saga witness category must be gravity-and-direction");
  requireCondition(stateChanges["saga.witness.acquisition"] === "granted", "Saga witness must be granted");
  const entryRequirements = revisit.entry_requirements as JsonObject;
  requireCondition(entryRequirements.minimum_travel_ticks === 1, "Saga revisit requires one travel tick");
  requireCondition(revisit.required_action !== undefined, "Saga revisit needs a maintenance action");

  const requiredLocations = new Set([
    "saga.outer-day-city",
    "saga.inner-sea-dome",
    "saga.no-down-city",
    "saga.axis-pillar",
    "saga.dual-pivot-chamber"
  ]);
  const assetLocations = new Set(slice.asset_specs.map((asset) => String(asset.location_id)));
  for (const location of requiredLocations) {
    requireCondition(assetLocations.has(location), `missing asset specification for ${location}`);
  }
  for (const asset of slice.asset_specs) {
    requireCondition(asset.production_status === "specification-only", `asset is not specification-only: ${asset.id}`);
    requireCondition(!("source_asset" in asset), `asset may not reference an unverified geology candidate: ${asset.id}`);
  }

  if (!catalog) return;
  const requiredIds = [
    "saga.outer-day-city.pre-rotation", "saga.inner-sea-dome.pre-rotation", "saga.no-down-city.pre-rotation", "saga.axis-pillar.pre-rotation", "saga.dual-pivot-chamber.pre-rotation",
    "saga.outer-day-city.post-rotation", "saga.inner-sea-dome.post-rotation", "saga.no-down-city.post-rotation", "saga.axis-pillar.post-rotation", "saga.dual-pivot-chamber.post-rotation",
    "saga.outer-day-city.during-rotation", "saga.inner-sea-dome.during-rotation", "saga.no-down-city.during-rotation", "saga.axis-pillar.during-rotation", "saga.dual-pivot-chamber.during-rotation",
    "saga.outer-light-clock.device", "saga.inner-tide-clock.device", "saga.neutral-free-gyroscope.device",
    "saga.xiu.character", "saga.fanzhi.character", "saga.yang.character"
  ];
  const assetIds = new Set<string>();
  for (const asset of catalog.assets) {
    requireCondition(!assetIds.has(asset.id), `duplicate asset id: ${asset.id}`);
    assetIds.add(asset.id);
    requireCondition(asset.status === "concept-candidate", `asset is not a concept candidate: ${asset.id}`);
    requireCondition(!asset.source_path.startsWith("game/assets/"), `candidate may not reference game/assets: ${asset.id}`);
    requireCondition(asset.source_path.includes("/素材/萨迦/概念候选/"), `candidate source is not isolated: ${asset.id}`);
    requireCondition(!asset.source_path.includes("井星") && !asset.source_path.includes("地质背景"), `candidate may not reference Well geology: ${asset.id}`);
    requireCondition(existsSync(join(root, asset.source_path)), `missing candidate source image: ${asset.source_path}`);
    const environment = asset.kind === "environment";
    requireCondition(environment ? asset.target_size.width === 160 && asset.target_size.height === 90 : asset.target_size.width === 64 && asset.target_size.height === 64, `wrong target size: ${asset.id}`);
    requireCondition(environment ? asset.alpha_processing === "not-applicable" : asset.alpha_processing === "chroma-key-removed", `missing alpha processing: ${asset.id}`);
    requireCondition(asset.prohibited_integration_reason.length > 10, `candidate lacks integration prohibition: ${asset.id}`);
  }
  for (const id of requiredIds) requireCondition(assetIds.has(id), `missing required Saga candidate: ${id}`);
  requireCondition(catalog.assets.length === requiredIds.length, "Saga catalog must contain exactly the 21 approved concept candidates");
  const planned = catalog.planned_variants ?? [];
  requireCondition(planned.length === 0, "approved during-rotation candidates may not remain specification-only");
}

function markdownEscape(value: string): string {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

function renderDecisionRegister(register: DecisionRegister): string {
  const rows = register.decisions
    .map((decision) => `| \`${decision.id}\` | ${decision.title} | ${decision.status} | ${decision.version} | ${markdownEscape(decision.affected_content.join(", "))} |`)
    .join("\n");
  const detail = register.decisions
    .map((decision) => [
      `## ${decision.title}`,
      "",
      `- ID：\`${decision.id}\``,
      `- 状态：\`${decision.status}\``,
      `- 版本：\`${decision.version}\``,
      `- 变更理由：${decision.change_reason}`,
      `- 依据：${decision.source_refs.map((sourceRef) => `\`${sourceRef}\``).join("；")}`,
      `- 不可破坏约束：${decision.constraints.join("；")}`,
      `- 验收：${decision.acceptance_criteria.join("；")}`,
      ""
    ].join("\n"))
    .join("\n");
  return [
    "# 设定裁决台账",
    "",
    "> 自动生成自 `content/src/design/decision-register.json`；请勿手改。",
    "",
    "| ID | 标题 | 状态 | 版本 | 影响内容 |",
    "| --- | --- | --- | --- | --- |",
    rows,
    "",
    detail
  ].join("\n");
}

function renderSlice(slice: Slice): string {
  const journey = slice.journey as JsonObject;
  const calendar = journey.rotation_calendar as JsonObject;
  const revisit = journey.revisit as JsonObject;
  const sequence = calendar.required_sequence as JsonObject[];
  const assets = slice.asset_specs
    .map((asset) => `| \`${asset.id}\` | ${asset.location_id} | ${asset.kind} | ${(asset.states as string[]).join(" / ")} | ${asset.production_status} |`)
    .join("\n");
  return [
    `# ${slice.title}`,
    "",
    "> 自动生成自 `content/src/slices/well-saga-first-slice.json`；请勿手改。",
    "",
    `版本：${slice.version}`,
    "",
    "## 链路",
    "",
    `1. 井星：修复旧船离星。${(journey.well_departure as JsonObject).system_text}`,
    "2. 萨迦：依次完成以下三项校准：",
    ...sequence.map((step, index) => `${index + 1}. ${step.player_operation}`),
    `3. 萨迦结果：${(calendar.resolution as JsonObject).system_text}`,
    `4. 回访：${(revisit.required_action as JsonObject).player_operation}`,
    "",
    "## 回访条件与后果",
    "",
    `- 最少航行推进：${((revisit.entry_requirements as JsonObject).minimum_travel_ticks as number)} 次。`,
    ...((revisit.visible_consequences as string[]).map((consequence) => `- ${consequence}`)),
    `- 系统文本：${revisit.system_text}`,
    "",
    "## 素材占位规格",
    "",
    "| 资产 ID | 地点 | 类型 | 状态变体 | 生产状态 |",
    "| --- | --- | --- | --- | --- |",
    assets,
    ""
  ].join("\n");
}

function renderAssetCatalog(catalog: AssetCatalog): string {
  const rows = catalog.assets.map((asset) => `| \`${asset.id}\` | ${asset.kind} | ${asset.location_id} | ${asset.target_size.width}×${asset.target_size.height} | ${asset.alpha_processing} | ${asset.audit.conclusion} |`).join("\n");
  const future = (catalog.planned_variants ?? []).map((variant) => `- \`${variant.id}\`：仅保留生成规格，未纳入本批 ${catalog.assets.length} 张候选。`).join("\n");
  return [
    `# ${catalog.title}`,
    "",
    "> 自动生成自 `content/src/assets/saga-concept-candidates.json`；请勿手改。",
    "",
    "所有条目均为概念候选：不属于生产资产，不接入 `game/assets`，后续仍需像素网格重建、限色、拆件与引擎验收。",
    "",
    "| ID | 类型 | 地点 | 目标逻辑尺寸 | Alpha | 审核 |",
    "| --- | --- | --- | --- | --- | --- |",
    rows,
    ...(future ? ["", "## 预留的轮坠中规格", "", future] : []),
    ""
  ].join("\n");
}

function outputs(register: DecisionRegister, slice: Slice, catalog: AssetCatalog): Output[] {
  return [
    { path: join(contentRoot, "generated", "design", "decision-register.json"), content: formatJson(register) },
    { path: join(contentRoot, "generated", "slices", "well-saga-first-slice.json"), content: formatJson(slice) },
    { path: join(root, "docs", "design", "decision-register.md"), content: renderDecisionRegister(register) },
    { path: join(root, "docs", "design", "well-saga-first-slice.md"), content: renderSlice(slice) },
    { path: join(contentRoot, "generated", "assets", "saga-concept-candidates.json"), content: formatJson(catalog) },
    { path: join(root, "docs", "design", "saga-concept-candidates.md"), content: renderAssetCatalog(catalog) }
  ];
}

async function build(allOutputs: Output[]): Promise<void> {
  for (const output of allOutputs) {
    await mkdir(dirname(output.path), { recursive: true });
    writeFileSync(output.path, output.content, "utf8");
    console.log(`generated ${relative(root, output.path)}`);
  }
}

function check(allOutputs: Output[]): void {
  const stale = allOutputs.filter((output) => !existsSync(output.path) || readFileSync(output.path, "utf8") !== output.content);
  requireCondition(stale.length === 0, `generated content is stale: ${stale.map((output) => relative(root, output.path)).join(", ")}`);
}

async function main(): Promise<void> {
  const command = process.argv[2];
  requireCondition(command === "validate" || command === "build" || command === "check", "usage: contentc <validate|build|check>");
  const register = readJson(join(contentRoot, "src", "design", "decision-register.json")) as DecisionRegister;
  const slice = readJson(join(contentRoot, "src", "slices", "well-saga-first-slice.json")) as Slice;
  const catalog = readJson(join(contentRoot, "src", "assets", "saga-concept-candidates.json")) as AssetCatalog;
  validateSchemas(register, slice, catalog);
  validateSemantics(register, slice, catalog);
  const allOutputs = outputs(register, slice, catalog);
  if (command === "build") {
    await build(allOutputs);
  } else if (command === "check") {
    check(allOutputs);
  }
  console.log(`contentc ${command}: PASS`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(`contentc: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  });
}
