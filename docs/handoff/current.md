# 当前跨会话交接

> Last verified: 2026-07-29
>
> Repository: `Andrew05213/starfall-embers`
>
> 本文件是日期化操作快照。执行写操作前，必须用本地 Git 和 GitHub 重新确认会变化的事实。

## 1. 权威来源与使用方式

- 人工维护的内容权威源位于 `content/src`；`content/generated` 和生成的可读文档只由
  `contentc` 生成，不得手改。
- 当前冻结决策以 `content/src/design/decision-register.json` 和
  `content/src/slices/well-saga-first-slice.json` 为准，并由 Schema、编译器和测试约束。
- `project_reference` 是经项目负责人批准入库的上游依据，不自动覆盖内容权威源、Schema、
  ADR 或 `AGENTS.md`。
- `project_reference/.../文档/07_项目进度与下一阶段交接_2026-07-26.md` 记录的是
  PR #4 时期的历史状态，只可作为背景资料，不是当前操作入口。

## 2. GitHub 与分支关系

- `main` 的已知远端 head 为 `2b82c72`。
- `agent/design-baseline-20260726`：
  - 远端 head：`3652627`（设计基线参考资料）。
  - 本地 head：`5a31a99`（增加获批准素材与 Git LFS 仓库规则）。
  - 本地领先远端 1 个提交，尚未推送，也尚未创建以 `main` 为目标的设计基线 PR。
- [PR #5](https://github.com/Andrew05213/starfall-embers/pull/5)：
  - Draft，head 为 `agent/content-ledger-well-saga`，已知 head `76c0b15`。
  - base 仍为 `agent/design-baseline-20260726` 的远端 `3652627`。
  - 已发布差异应保持为内容台账、井星→萨迦切片、内容编译器、文档和 CI 共 16 个文件。
- [PR #4](https://github.com/Andrew05213/starfall-embers/pull/4)：
  - Draft，head 为 `agent/combat-gate1` 的 `a556cd8`，base 为 `main`。
  - Gate 1.5 仍保持 GDScript 权威模拟、C++ 原生影子模拟的边界。

## 3. 本机 worktree

以下路径只描述 Andrew 当前机器，换机或清理后必须重新运行 `git worktree list`：

- `C:\Users\Andrew\Documents\game`
  - `agent/content-ledger-well-saga`，当前主要工作区。
  - 含受保护的未提交工作，禁止擅自暂存、重置、覆盖或删除。
- `C:\tmp\starfall-design-baseline-rules`
  - `agent/design-baseline-20260726`，用于设计基线、仓库规则和后续 LFS 整理。
- `C:\Users\Andrew\Documents\game\build\pr4-gate15-src`
  - detached `a556cd8`，用于 PR #4 Gate 1.5 的隔离复现，不是当前开发分支。

## 4. 当前受保护的未提交工作

主要工作区已知包含：

- `game/project.godot` 的 Godot 自动序列化改动。
- `tools/contentc/src/index.ts` 和 `tools/contentc/test/contentc.test.ts` 的资产目录编译/测试改动。
- 四个未跟踪的资产目录文件：
  - `content/src/assets/saga-concept-candidates.json`
  - `content/schemas/asset-catalog.schema.json`
  - `content/generated/assets/saga-concept-candidates.json`
  - `docs/design/saga-concept-candidates.md`
- `project_reference/.../素材/萨迦/概念候选` 下 16 张未跟踪 PNG。

这 16 个候选目录项由 10 个环境、3 个装置和 3 个角色组成，状态均为
`concept-candidate`；另有 5 个 `specification-only` 的轮坠中变体规划。它们尚未属于
PR #5，也不得接入正式 Godot 场景。处理前必须重新检查工作区，因为这些文件可能继续变化。

普通 `git status` 还会把设计基线中的既有 PNG/ZIP 显示为修改。审计已证明这些是原始 Git
blob 与现行 LFS 属性不一致造成的假修改；不得据此覆盖或重新暂存素材。

## 5. Git LFS 审计与发布阻塞

- 设计基线中的 43 张 PNG、1 个 ZIP 和 2 个 DOCX 当前仍以普通 Git blob 保存，尚未归一化
  为 LFS 指针。
- 46 个已跟踪二进制的工作区原始哈希与索引完全一致；43 张 PNG 均可读取，两份 DOCX
  结构有效。
- 本机审计到的 60 个 LFS 对象均存在且 SHA-256 与 OID 一致，但当前提交没有对应 LFS
  指针，因此这不能证明远端素材完整。
- `project_reference/.../素材/旧概念资产/井星_区域背景审核包_V0.1.zip` 缺少 ZIP
  中央目录结尾，已确认截断；本机常见资料目录中未找到有效副本。
- 在取得并验证权威 ZIP 副本前，不发布设计基线 PR，不执行素材归一化。
- `.git\lfs\tmp` 的拒绝写入来自 Codex 沙箱 ACL；Andrew 本身具有完全控制。LFS 写操作应
  使用获批的非沙箱执行环境，不得削弱沙箱 ACL。

## 6. 冻结的井星→萨迦首发切片

- 修复旧船离开井星；井星共同下方与坠核保留，砾同行。
- 在萨迦依次完成外昼光钟、内海潮钟和无下城自由陀仪三项校准，重建轮坠历。
- 至少完成一次航行推进后回访萨迦，并完成中和层校准。
- 萨迦五个区域的首发资产仍是 `specification-only`。现有概念候选不得被当作已验收 PNG、
  无缝地质背景或正式场景资产。
- 六种终局仍保持开放，首发切片不得声明唯一官方结局。

## 7. 后续顺序

1. 从权威来源取得有效 ZIP，验证结构和哈希，同时保留当前截断文件直到替换件确认。
2. 在独立设计基线 worktree 中定向归一化已批准二进制，运行 `git lfs fsck`，推送 LFS
   对象，并用临时干净克隆执行 `git lfs pull` 验证远端对象完整。
3. 清理并验证 `agent/design-baseline-20260726`，创建以 `main` 为目标的设计基线 Draft PR。
4. 设计基线合并后，将 `agent/content-ledger-well-saga` 变基到已合并基线，改指 PR #5
   到 `main`，确认仍只有预期 16 个文件并等待 CI 全绿。
5. 最后为当前未提交的萨迦概念候选建立独立范围；不得混入设计基线或未经复核的 PR #5。

## 8. 最近验证证据

- PR #4 Gate 1.5 隔离复现：Native 3/3、Godot 8/8、VS2022 `/MD` 桥接构建通过。
- PR #5 内容变更：TypeScript、生成一致性、6/6 内容测试、CTest 1/1 和 Godot 合约检查通过。
- 设计素材审计：59 张现有 PNG 可读取；43 个已跟踪 PNG、1 个 ZIP、2 个 DOCX 的原始内容
  未发生工作区变化。

验证结果只说明对应提交和审计时点；代码、内容或构建环境变化后必须按 `AGENTS.md` 重新验证。
