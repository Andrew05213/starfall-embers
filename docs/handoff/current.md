# 当前跨会话交接

> Last verified: 2026-08-02
>
> Repository: `Andrew05213/starfall-embers`
>
> 本文件是日期化操作快照。执行写操作前，必须用本地 Git 和 GitHub 重新确认会变化的事实。

## 1. 权威来源与维护规则

- 人工维护的内容权威源位于 `content/src`；`content/generated` 和生成的可读文档只由
  `contentc` 生成，不得手改。
- 当前冻结决策以 `content/src/design/decision-register.json` 和
  `content/src/slices/well-saga-first-slice.json` 为准，并由 Schema、编译器和测试约束。
- `project_reference` 是经项目负责人批准入库的上游依据，不自动覆盖内容权威源、Schema、
  ADR 或 `AGENTS.md`。
- `project_reference/.../文档/07_项目进度与下一阶段交接_2026-07-26.md` 是历史资料，不是
  当前操作入口。
- 每项有范围的仓库或 GitHub 操作完成后，必须同时复核并更新本文件与 `todo.md`。易变状态
  和验证证据写在本文件；`todo.md` 只在合并与验收门槛实际满足时勾选，否则记录日期化对账。

## 2. GitHub 与分支关系

- `main` 的已知远端 head 为 `401d65e`。
- [PR #6](https://github.com/Andrew05213/starfall-embers/pull/6) 已合并设计基线，merge commit
  为 `112e6da`；46 个批准二进制的 LFS 远端恢复验证已经完成。
- [PR #5](https://github.com/Andrew05213/starfall-embers/pull/5) 已变基并改指 `main`，确认保持
  预期 16 个文件后完成验证与合并；merge commit 为 `df64f49`。
- [PR #4](https://github.com/Andrew05213/starfall-embers/pull/4) 已于本次维护中从 Draft 改为
  Ready 并合并；head 为 `75f81e3`，merge commit 为 `267b18b`。合并前 8/8 CI checks 全绿，
  GitHub 报告 CLEAN 且 MERGEABLE；远端 `agent/combat-gate1` 分支仍保留。
- [PR #7](https://github.com/Andrew05213/starfall-embers/pull/7) 仍为以 `main` 为 base 的 Draft，
  head 为 `edfaa6f`。已发布范围是萨迦 `concept-candidate` 台账、编译/测试支持和 16 张 LFS
  PNG；2026-07-31 的 6/6 CI checks 全绿。由于 `main` 已继续前进，审查或合并前必须重新
  获取可合并性并按需变基。
- [PR #3](https://github.com/Andrew05213/starfall-embers/pull/3) 仍为旧的 Draft 原生区块基础，
  head 为 `b4ec6ab`，其 GitHub 基线仍停在旧 `main` `2b82c72`。不得直接合并；应从当前
  `main` 新建移植分支，定向移植区块存储、批命令、脏区、checksum、测试和 benchmark，
  并手工适配 PR #4 已合并的 ballistics 与 `SimulationHost`。
- [PR #8](https://github.com/Andrew05213/starfall-embers/pull/8) 已在 8/8 checks 全绿后合并，
  merge commit 为 `401d65e`；`AGENTS.md`、`todo.md` 与本交接已进入 `main`。

## 3. 本机 worktree

以下路径只描述 Andrew 当前机器，换机或清理后必须重新运行 `git worktree list`：

- `C:\Users\Andrew\Documents\game`
  - `agent/content-ledger-well-saga`，head `76c0b15`；相对远端 ahead 1、behind 7。
  - 含受保护的未提交工作，禁止擅自暂存、重置、覆盖或删除。
- `C:\tmp\starfall-design-baseline-rules`
  - `agent/design-baseline-20260726`，head `01c99e3`；保留为设计基线与 LFS 审计工作区。
- `C:\tmp\starfall-pr5-rebase-20260729`
  - `codex/pr5-rebase-20260729`，head `02f8dda`；PR #5 的历史变基工作区。
- `C:\tmp\starfall-pr4-native-convergence-20260731`
  - `codex/pr4-native-convergence-20260731`，head `75f81e3`，跟踪
    `origin/agent/combat-gate1`；PR #4 已合并后的保留工作区。
- `C:\tmp\starfall-saga-candidates-20260730`
  - `codex/saga-concept-candidates`，head `edfaa6f`；对应 PR #7，另含受保护的后续工作。
- `C:\tmp\starfall-status-after-pr4-20260802`
  - `codex/update-status-after-pr4`，从合并 PR #4 后的 `main` `267b18b` 建立；只用于本次
    `AGENTS.md`、`todo.md` 与交接快照维护。
- `C:\tmp\starfall-native-chunk-p2-20260802`
  - `codex/native-chunk-p2`，从合并 PR #8 后的 `main` `401d65e` 建立；只用于定向移植
    PR #3 的原生区块基础并完成 P0.3/P2 验收。
- `C:\Users\Andrew\Documents\game\build\pr4-gate15-src`
  - detached `a556cd8`；PR #4 Gate 1.5 的历史隔离复现工作区，不是当前开发分支。

## 4. 当前受保护的未提交工作

主要工作区 `C:\Users\Andrew\Documents\game` 在 2026-08-02 复核仍包含：

- `game/project.godot` 的 Godot 自动序列化改动。
- `tools/contentc/src/index.ts` 和 `tools/contentc/test/contentc.test.ts` 的资产目录后续改动。
- 未跟踪的资产 Schema、权威源、生成 JSON 和设计文档目录。
- `project_reference/.../素材/萨迦/概念候选` 下与 PR #7 同源的 16 张未跟踪 PNG。

萨迦 worktree `C:\tmp\starfall-saga-candidates-20260730` 在 2026-08-02 复核包含 5 个已跟踪
修改和 10 个未跟踪后续项：

- 5 个已跟踪修改：候选权威 JSON、生成 JSON、可读文档和两处 `contentc` 编译/测试支持。
- 5 张未跟踪 `during_rotation` 区域 PNG。
- 4 个未跟踪的无下城生产验收权威源、Schema、生成 JSON 和文档。
- 1 个未跟踪审查目录（含审查 README）。

以上两组改动都未被本轮暂存、重置、覆盖或删除。PR #7 已发布的 16 张图仍保持
`concept-candidate`，不得接入正式 Godot 场景；5 张 `during_rotation` 图和生产验收资料须
另行审计，不得顺带加入 PR #7。

## 5. Git LFS 审计与远端恢复验证

- 设计基线已跟踪的 43 张 PNG、1 个 ZIP 和 2 个 DOCX 已定向归一化为 46 个标准 Git LFS
  指针；没有对 `project_reference` 执行无范围重新暂存。
- 除 ZIP 外的 45 个二进制与归一化前原始内容一致；43 张 PNG 均可读取，两份 DOCX 结构
  有效。
- 有效 ZIP 大小为 4,153,650 字节，SHA-256 为
  `79CFAE00B4E966F4643821EC1E86FA9D70BA48F9B2C3928DEC5BE462CFFCB7D0`；含 14 个目录项、
  10 个实际文件，结构、读取与声明长度验证全部通过。
- 截断 ZIP 备份仍位于
  `C:\tmp\starfall-design-baseline-backups\2026-07-29\井星_区域背景审核包_V0.1.truncated-43E497EEAC1251C2.zip`；
  大小 786,446 字节，SHA-256 为
  `43E497EEAC1251C2F1917A08CEE1819D4E56319A706379124BDFB9CFC7A68026`，不得删除。
- 46/46 个 LFS 对象已推送；临时干净克隆的 `git lfs pull`、OID/大小复核、PNG/DOCX/ZIP
  结构检查和 `git lfs fsck` 全部通过。
- `.git\lfs\tmp` 的拒绝写入来自 Codex 沙箱 ACL。Git LFS 写操作使用获批的非沙箱执行环境；
  不得削弱或移除该安全 ACL。

## 6. 冻结的井星→萨迦首发切片

- 修复旧船离开井星；井星共同下方与坠核保留，砾同行。
- 在萨迦依次完成外昼光钟、内海潮钟和无下城自由陀仪三项校准，重建轮坠历。
- 至少完成一次航行推进后回访萨迦，并完成中和层校准。
- 萨迦五个区域的首发资产仍是 `specification-only`。现有概念候选不得被当作已验收 PNG、
  无缝地质背景或正式场景资产。
- 六种终局仍保持开放，首发切片不得声明唯一官方结局。

## 7. Native 权威基线

- PR #4 已把 Gate 1.5 合并到 `main`：支持 `gdscript_fallback`、`native_shadow` 和
  `native_authoritative` 三种模式。
- 权威模式由 C++ 决定弹体推进、寿命、命中、销毁和事件顺序；Godot 批量提交输入并消费
  快照/事件，保持固定 30 Hz、显式 seed 与 60 Hz 表现插值。
- 双跑副作用保持单次执行，GDScript 回退仍可独立运行；在新移植分支通过等价验证前不得删除
  回退路径。
- 合并证据：隔离复现 Native 3/3、Godot 8/8、Windows VS2022 `/MD` 桥接构建通过；最终
  PR 8/8 CI checks 全绿。

## 8. 后续顺序

1. 在 `codex/native-chunk-p2` 中定向移植 PR #3 的区块存储、批命令、脏区、checksum、
   测试和 benchmark，手工适配已合并的 ballistics 与 `SimulationHost`；不得 cherry-pick
   整个旧提交。
2. 完成 64×64 区块、版本化 DTO、Godot 批传输、确定性重放和 1024² benchmark 验收，
   发布替代 PR 后关闭或标记 PR #3 被取代。
3. 重新审查 PR #7 相对当前 `main` 的范围、LFS 指针和可合并性；必要时在隔离 worktree
   变基，验证后再决定 Ready 与合并。
4. PR #7 收敛后，再独立审计萨迦 worktree 中 5 个已跟踪修改与 10 个未跟踪后续项。
5. 每项操作完成后同步本文件与 `todo.md`，再进入下一项。

## 9. 本次维护快照

- PR #4 已完成 Ready、合并与远端 `main` 复核；merge commit 为 `267b18b`。
- PR #8 已合并并把状态维护带入 `main`；P0.3/P2 分支已从该合并提交建立，但尚未完成代码
  移植或验收，因此 `todo.md` 中对应复选框保持未勾选。
- 主要工作区与萨迦 worktree 的受保护改动保持原状；本轮没有归一化、暂存或删除其中素材。
- 普通沙箱内 `git status` 仍可能因共享 `.git\lfs\tmp` 的安全 ACL 失败；这不是素材损坏证据。

## 10. P0.3/P2 本地实现快照

- `codex/native-chunk-p2` 已定向移植旧 PR #3 的连续单字节 row-major 存储、批命令、稳定
  脏区、snapshot/checksum、单元测试与 benchmark；没有 cherry-pick 旧提交，也没有建立第二套
  原生宿主。
- `SimulationHost` 现同时承载 ballistics 与材质 `World`，在相同固定 tick 消费两类命令；
  GDExtension 通过 DTO v1 PackedArray 整批提交材质命令，并整批返回结果和拼接后的脏区 bytes。
- `NativeMaterialChunkView` 一次消费整个 dirty DTO，在 Godot 本地展开 cells 并更新
  `ImageTexture`；没有增加逐像素 GDExtension 调用。
- 区块协议固定为 64×64，材质 ID 固定为 `0..9`；未知 DTO 版本、非法材质或数组结构在写入前
  整批拒绝。ADR-0004 明确这一阶段不切换 GDScript 材质玩法权威，也不冻结存档格式。
- 本地 VS18 Debug CTest 3/3 通过，其中包含独立朴素随机参考模型；Debug GDExtension 构建、
  Godot 4.7.1 headless import、与 CI 对齐的 10/10 headless smoke，以及 Python Godot 合约检查
  全部通过。
- 1024×1024 benchmark 使用 2,048 条命令，报告 256 个活跃脏区、1,048,576-byte payload、
  8.033 ms 命令批、2.240 ms 脏批消费、checksum `5901029088708457294`，第二宿主确定性重放
  为 PASS。该时间是本机 VS18 Debug 单次结果，只用于本轮趋势基线。
- 当前实现尚未提交、推送或进入 PR，因此 `todo.md` 的 P0.3/P2 复选框保持未勾选；发布并完成
  远端 CI/审查前不得声明 P2 已进入 `main`。

验证结果只说明对应提交和审计时点；代码、内容或构建环境变化后必须按 `AGENTS.md` 重新验证。
