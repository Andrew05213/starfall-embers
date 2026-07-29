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
  - 已推送设计基线、仓库规则、LFS 归一化、交接入口和长期路线图；路线图提交为
    `10eb602`。
  - [PR #6](https://github.com/Andrew05213/starfall-embers/pull/6) 为以 `main` 为目标的
    Draft 设计基线 PR；本交接更新是其后的纯文档状态同步。
- [PR #5](https://github.com/Andrew05213/starfall-embers/pull/5)：
  - Draft，head 为 `agent/content-ledger-well-saga`，已知 head `76c0b15`。
  - base 仍为持续更新中的 `agent/design-baseline-20260726`；设计基线合并后必须重新变基并
    改指 `main`。
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

2026-07-29 复核：所有 16 张图均为 `v01` PNG，路径仅位于
`project_reference/.../素材/萨迦/概念候选/{区域,装置,角色}`。区域图为 16:9 概念构图；
三台装置与三名角色已经洋红键去背，台账声明为硬边 Alpha 候选。它们依然只是构图、色板、
材质与比例依据，不是可直接接入的 Sprite、tile、地质背景或生产资产。

普通 `git status` 还会把设计基线中的既有 PNG/ZIP 显示为修改。审计已证明这些是原始 Git
blob 与现行 LFS 属性不一致造成的假修改；不得据此覆盖或重新暂存素材。

## 5. Git LFS 审计与远端恢复验证

- 设计基线已跟踪的 43 张 PNG、1 个 ZIP 和 2 个 DOCX 已在本地定向归一化为 46 个标准
  Git LFS 指针；没有对 `project_reference` 执行无范围重新暂存。
- 除 ZIP 外的 45 个二进制与归一化前 `23a5734` 中的原始内容完全一致；43 张 PNG 均可读取，
  两份 DOCX 结构有效。
- 有效 ZIP 大小为 4,153,650 字节，SHA-256 为
  `79CFAE00B4E966F4643821EC1E86FA9D70BA48F9B2C3928DEC5BE462CFFCB7D0`。ZIP 结构有效，
  含 14 个目录项、10 个实际文件；所有文件均可完整读取且声明长度匹配。
- 截断 ZIP 已保留在
  `C:\tmp\starfall-design-baseline-backups\2026-07-29\井星_区域背景审核包_V0.1.truncated-43E497EEAC1251C2.zip`，
  大小 786,446 字节，SHA-256 为
  `43E497EEAC1251C2F1917A08CEE1819D4E56319A706379124BDFB9CFC7A68026`；不得删除该备份。
- 当前状态：**本地 LFS 归一化和远端对象恢复验证均已完成**。46/46 个 LFS 对象已推送，
  临时干净克隆中的 `git lfs pull`、对象哈希/大小复核和 `git lfs fsck` 均通过。
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

1. 审查 [PR #6](https://github.com/Andrew05213/starfall-embers/pull/6) 并等待设计基线合并。
2. 设计基线合并后，将 `agent/content-ledger-well-saga` 变基到已合并基线，改指 PR #5
   到 `main`，确认仍只有预期 16 个文件并等待 CI 全绿。
3. 最后为当前未提交的萨迦概念候选建立独立范围；不得混入设计基线或未经复核的 PR #5。

## 8. 最近验证证据

- PR #4 Gate 1.5 隔离复现：Native 3/3、Godot 8/8、VS2022 `/MD` 桥接构建通过。
- PR #5 已发布内容变更：TypeScript、生成一致性、6/6 内容测试、CTest 1/1 和 Godot 合约检查通过。
- 2026-07-29 萨迦候选台账工作区：`npm run validate`、`build`、`check`、`test` 与
  `tsc --noEmit` 通过；内容测试为 7/7。此结果不表示候选图已获生产验收，也不替代 Godot
  场景测试。
- 设计素材审计：59 张现有 PNG 可读取；46 个已跟踪二进制均形成标准 LFS 指针，指针 OID
  和 size 与工作区内容一致；除预期替换的 ZIP 外，其余 45 个原始内容未变化。
- 远端恢复验证：已显式推送 46/46 个 LFS 对象（共 17 MB）；临时干净克隆
  `C:\tmp\starfall-lfs-verify-20260729-10eb602` 在禁用自动 smudge 后先显示 46 个指针，
  随后 `git lfs pull` 完整恢复 43 张 PNG、1 个 ZIP 和 2 个 DOCX；全部对象的 OID 与 size
  匹配，PNG 可读取、DOCX 结构有效、ZIP 14 个目录项/10 个实际文件均可完整读取，
  `git lfs fsck` 返回 `Git LFS fsck OK`。

## 9. 本次维护快照

- 复核日期：2026-07-29。
- 本地主要工作区：`agent/content-ledger-well-saga`，head `76c0b15`。
- GitHub 远端分支引用复核：`main` 为 `2b82c72`；设计基线已经由 `10eb602` 推送并创建
  Draft PR #6；内容台账为 `76c0b15`。本交接更新是 PR #6 上的纯文档后续提交。
- 第 4 节列出的主要工作区改动仍未提交，也未被本轮暂存、重置或删除。
- 本轮在独立设计基线 worktree 中提交 `AGENTS.md` 与 `todo.md`，推送分支和 46 个 LFS
  对象，完成干净克隆远端恢复验证并创建 Draft PR #6；普通全量状态查询仍可能因
  `.git/lfs/tmp` 的沙箱 ACL 失败。

验证结果只说明对应提交和审计时点；代码、内容或构建环境变化后必须按 `AGENTS.md` 重新验证。
