# 当前跨会话交接

> Last verified: 2026-08-04
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

- `main` 的最新 head 为 `83e9b3b`（2026-08-04 由 `git ls-remote` 复核）；其中 `fc22398`
  仍是 P0.3/P2 代码合并提交。
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
- [PR #3](https://github.com/Andrew05213/starfall-embers/pull/3) 已留下替代说明并关闭；旧 head
  `b4ec6ab` 未直接合并。
- [PR #8](https://github.com/Andrew05213/starfall-embers/pull/8) 已在 8/8 checks 全绿后合并，
  merge commit 为 `401d65e`；`AGENTS.md`、`todo.md` 与本交接已进入 `main`。
- [PR #9](https://github.com/Andrew05213/starfall-embers/pull/9) 已在 8/8 checks 全绿、CLEAN
  且 MERGEABLE 后合并，merge commit 为 `fc22398`；它取代了已关闭的 PR #3，并完成
  P0.3/P2 的原生区块与批传输基线。
- [PR #10](https://github.com/Andrew05213/starfall-embers/pull/10) 已合并状态维护，merge commit
  为 `bb8953f`；它把 P0.3/P2 的 `todo.md`、`current.md` 对账带入最新 `main`。
- [PR #11](https://github.com/Andrew05213/starfall-embers/pull/11) 已从 Draft 转为 Ready 并合并，
  base 为 `main`，head 为 `727fd23`，merge commit 为 `afa36c7`；最终 head 的 content、
  native-core、windows-native-bridge、godot-demo checks 全部通过。
- [PR #12](https://github.com/Andrew05213/starfall-embers/pull/12) 已在全套 CI 通过后合并，
  head 为 `c558ec0`，merge commit 为 `83e9b3b`；只包含 P3 的 `todo.md` 与
  `docs/handoff/current.md` 状态对账。

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
- `C:\tmp\starfall-status-after-p2-20260802`
  - `codex/update-status-after-p2`，从合并 PR #9 后的 `main` `fc22398` 建立；只用于核销
    `current.md` 与 `todo.md`，不得夹带代码、构建输出或素材。
- `C:\tmp\starfall-p3-material-powder-20260803`
  - `codex/p3-material-powder`，从 `origin/main` `bb8953f` 建立；实现提交 `bd3dace`、状态
    对账提交 `ab15a1b`，最终 head `727fd23`，对应 PR #11（已合并）。只用于 P3 首批固定向下
    `SAND↔AIR` 原生迁移和验证，不得接触 PR #7、萨迦素材或主要工作区的受保护改动。
- `C:\tmp\starfall-status-after-p3-20260804`
  - `codex/update-status-after-p3`，从 PR #11 merge commit `afa36c7` 建立；只用于核销 P3
  首批和更新本交接，不夹带代码、构建输出或素材。
- `C:\tmp\starfall-p4-native-gravity-20260804`
  - `codex/p4-gravity-core`，从 PR #11 合并后的 `main` 建立；已同步 PR #12 的状态提交，
    核心实现提交为 `c98e641`，当前包含合并文档的本地整合提交。只用于 P4 原生重力核心，
    不得接触 PR #7、萨迦素材或主要工作区的受保护改动。
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

1. PR #11 已合并，P3 首批三个 TODO 已核销；状态对账已通过 PR #12（merge commit `83e9b3b`）
   写入 `main`。
2. P4 原生重力核心已在独立 worktree 实现：新增 ADR-0006、`GravityField`、局部场命令、
   checksum、高速 ballistics 子步和 native CTest；核心 PR 尚未推送或创建，待本地审查后发布。
3. 按“核心 → 批桥接/影子 → 角色/镜头 → 诊断/验收”四个非堆叠 Draft PR 依次推进。P4 不改变
   材质 DTO、P3 固定 `+Y` 粉末规则或正式混合材质场景；每阶段保留 GDScript 参考和确定性回放。
4. PR #7 继续由独立工作线处理；重新审查其相对最新 `main` 的范围、LFS 指针和可合并性，
   必要时仅在其 worktree 变基，不把 PR #11 或萨迦素材带入本分支。
5. PR #7 收敛后，再独立审计萨迦 worktree 中 5 个已跟踪修改与 10 个未跟踪后续项。
6. 每项操作完成后同步本文件与 `todo.md`，再进入下一项。

## 9. 本次维护快照

- PR #4 已完成 Ready、合并与远端 `main` 复核；merge commit 为 `267b18b`。
- PR #8、PR #9 和 PR #10 已依次把原生区块实现、验收与状态对账带入最新 `main`；P0.3/P2
  的旧“尚未完成”描述仅保留作历史快照，当前复选框已按合并验收正式核销。
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
- 本地 VS18 Debug 与 Release CTest 均为 3/3，通过独立朴素随机参考模型；Debug GDExtension 构建、
  Godot 4.7.1 headless import、与 CI 对齐的 10/10 headless smoke，以及 Python Godot 合约检查
  全部通过。
- VS18 Release 1024×1024 benchmark 使用 2,048 条命令，报告 256 个活跃脏区、
  1,048,576-byte payload、0.899 ms 命令批、0.386 ms 脏批消费、checksum
  `5901029088708457294`，第二宿主确定性重放为 PASS。时间是本机单次结果，只用于本轮趋势
  基线；对应 Debug 单次结果为 8.033 ms 与 2.240 ms，checksum 相同。
- 实现最终 head 为 `e01684e`，已通过 PR #9 合并为 `fc22398`；远端 content、native-core、
  Godot 与 Windows bridge 共 8/8 checks 全绿，旧 PR #3 已关闭。因此 `todo.md` 的 P0.3
  与 P2 复选框可以正式核销。

验证结果只说明对应提交和审计时点；代码、内容或构建环境变化后必须按 `AGENTS.md` 重新验证。

## 11. P3 首批固定向下粉末迁移快照（2026-08-03）

- Worktree `C:\tmp\starfall-p3-material-powder-20260803` 的分支为
  `codex/p3-material-powder`，从 `origin/main` `bb8953f` 建立；实现提交为
  `bd3dace85686f1f4c5e9597ae17bab88d846e85d`，状态对账提交为
  `ab15a1bf27a4584ca185c7914fd463c82a4cc9f0`，均已推送到远端。
- ADR-0005 冻结本批所有权：C++ `World::step()` 只规范 `SAND↔AIR`，固定网格 `+Y`、32 位
  LCG、seed 派生 row-major 循环起点、每 tick moved 标记和五项候选顺序；越界与非 AIR
  封闭。ROCK、METAL、WATER、OIL、FIRE、SMOKE、LAVA、STEAM 保持静止；不改材质 ID、64×64
  区块、DTO v1、GDExtension 批接口、正式混合场景或 P4 重力。
- Native 测试覆盖垂直/双斜线/水平/阻塞/四边界、静止材质、x=63/64 与 y=63/64 跨区块、
  dirty row-major、单 tick 不重复移动、seed 分歧和随机参考模型；Debug/Release CTest
  均为 3/3。
- Godot 4.7.1 headless import、11 个现有/新增 smoke（含独立 GDScript 逐 tick 对照）、
  `demo_benchmark.gd` 和 Python Godot 合约检查均通过。参考器逐 tick 对比 cell bytes、dirty
  DTO 和完整 16 位 checksum；Native 双 World 额外对比 random state。
- 1024×1024、2,048 条初始化命令、300 个粉末 tick：Debug 平均/P95/最大为
  `6.960/8.102/10.541 ms`，P95 占 33.333 ms 帧预算 `24.307%`；Release 为
  `3.640/4.745/10.286 ms`，占比 `14.234%`。Release dirty chunks 平均/最大
  `152.973/165`，payload 平均/最大 `626578.773/675840` bytes；双宿主最终 checksum
  `7604899322391318841`，确定性重放 PASS，帧预算 PASS。
- PR #11（base `main`，head `727fd23`）已在最终 head 全部 CI 通过后由 Draft 转 Ready 并合并，
  merge commit 为 `afa36c7`。P3 首批固定向下 `SAND↔AIR` 的三个 TODO 已达到“合并且验收”
  门槛；PR #7 保持独立处理。

## 12. P4 原生重力核心快照（2026-08-04）

- 独立 worktree `C:\tmp\starfall-p4-native-gravity-20260804` 的分支为
  `codex/p4-gravity-core`，基线为 PR #11 merge 后的 `main`，当前远端 main 已包含 PR #12
  状态对账 merge `83e9b3b`。
- 实现提交 `c98e641` 新增共享 `Vec2`、`GravityField`、主坠核和两类有界局部场、稳定
  source ID 命令、tick 过期、field checksum，并让 ballistics 通过同一 field 进行确定性
  高速子步采样；未改变 material DTO、P3 `+Y` 粉末规则或 Godot 正式行为。
- ADR-0006 冻结实体重力所有权、角色/镜头边界和后续批桥接方向。核心 Debug CTest 为 4/4，
  包括新增 gravity smoke；Release、Godot bridge、跨语言 shadow 和 P4 角色切换尚未完成。
- P4 第一核心 PR 尚未推送；下一步是补充/审查 native gravity 接口后推送 Draft PR，并在
  每个阶段完成后同步本文件与 `todo.md`。用户要求的最终 `gpt-5.6-sol xhigh` 只读 review
  在 P4 交付完成后执行；若发现 blocker，只记录，不在 review 后擅自修改。

## 13. P4 gravity core CI lifetime fix snapshot (2026-08-04)

- Local fix commit `1301ec8`: bridge reset/configure now rebinds `BallisticSystem` to the host-owned `GravityField` instead of assigning a temporary `SimulationHost`; host and ballistics copy/move are disabled.
- Debug CTest 4/4, Release CTest 4/4, and `tests/integration/check_godot_demo.py` pass locally.
- PR #13 remains Draft until `1301ec8` is pushed and Godot smoke plus Windows bridge CI are green; do not merge before then.
- The previous Godot failure was confirmed on the `reset_to_gate1_baseline()` to `GravityField::advance_tick()` path. The local fix is validated; remote re-verification remains pending.
## 14. P4 核心合并状态（2026-08-04）

- PR #13 `codex/p4-gravity-core` 已由 Draft 转 Ready，并在 8/8 CI 全绿后合并到 `main`；merge commit 为 `2f5f0e106514ac0a436d6d080b4dd3d47103cf00`。
- `1301ec8` 的 host reset 生命周期修复已通过两组 Godot 4.7.1 smoke、两组 Windows bridge、两组 native/content checks；之前的 `GravityField::advance_tick()` 悬空指针 blocker 已关闭。
- 下一工作线必须从 `origin/main=2f5f0e1` 新建 `C:\tmp\starfall-p4-gravity-shadow-20260804` / `codex/p4-gravity-shadow`，不堆叠旧 PR #13，不触碰 PR #7、萨迦素材或主工作区脏改动。
## 15. P4 gravity shadow transport snapshot (2026-08-04)

- Worktree `C:\tmp\starfall-p4-gravity-shadow-20260804`, branch `codex/p4-gravity-shadow`, starts from `origin/main=98c1e2e` (PR #13 core plus PR #14 status merge); implementation commit is `39cd1c5`.
- Added gravity query/result DTO v1 without changing material DTO v1, atomic pending-source preflight, batched GDExtension command/query methods, source result drain, checksum access, and `NativeGravityProvider` with fallback/shadow/authoritative modes. Existing MaterialWorld remains the shadow reference and dual-write target.
- Local Debug native CTest 4/4 and Godot contract check pass; Debug bridge compiles with pinned godot-cpp `58d1de7`. Headless Godot 4.7.1 gravity shadow smoke and full CI remain pending until the Draft PR is pushed.
- No formal scene, project.godot, PR #7, or protected main-worktree/Saga asset changes are included. P4 role/camera authority, diagnostics, and benchmark remain incomplete.
## 16. P4 gravity shadow merge status (2026-08-04)

- PR #15 `codex/p4-gravity-shadow` 已由 Draft 转 Ready，并在 8/8 CI 全绿后合并；merge commit 为 `98177ebd06e905a510aa44c7d843b1ea15ece4b4`。
- 已验收 gravity DTO v1 批命令/查询、source result drain、`NativeGravityProvider` 三模式、MaterialWorld 双写和 `gravity_shadow_smoke.gd`；PR #7、萨迦素材和主工作区脏改动仍隔离。
- 下一工作线从最新 `origin/main=98177eb` 新建 `C:\tmp\starfall-p4-player-camera-20260804` / `codex/p4-player-camera-gravity`，只处理 GravityFrame、角色和镜头，不改材质 DTO、P3 `+Y` 规则或正式素材。
## 17. P4 GravityFrame role/camera snapshot (2026-08-04)

- Worktree `C:\tmp\starfall-p4-player-camera-20260804`, branch `codex/p4-player-camera-gravity`, base `origin/main=98177eb`; implementation commit `eb58c1b`.
- Added `GravityFrame` with zero-gravity hysteresis (`0.001`/`0.002`), stable up/tangent selection, and one frame consumed by player movement and `GravityFollowCamera`; native provider defaults to authoritative when the extension is available and falls back cleanly otherwise.
- Added `gravity_transition_smoke.gd` to CI. Static Godot contract check passes; headless Godot 4.7.1, full smoke, bridge, and role/camera transition CI remain pending until Draft PR publication.
- Camera remains presentation-only and reads `GravityFrame.up`; no material DTO, P3 powder rule, formal scene, PR #7, Saga asset, or protected main-worktree change is included.

## 18. P4 GravityFrame role/camera merge status (2026-08-04)

- PR #17 `codex/p4-player-camera-gravity` was promoted from Draft and merged into `main`; merge commit is `606614f2dd55969f0aeee1a656a1b6e15c770b91`.
- Final head `f52e42e739f21bebc6f682cbf74e114cece3679` passed both push and pull-request CI workflows, 8/8 checks each: content, native-core, Godot demo, and Windows native bridge.
- `GravityFrame` is now the single role/camera gravity-frame boundary with zero-gravity hysteresis and stable up/tangent selection. The camera remains presentation-only and the native provider falls back when the extension is unavailable.
- The protected main worktree, PR #7, Saga assets, material DTO v1, P3 fixed `+Y` powder rule, formal scenes, and `game/project.godot` were not changed.
- Next phase is the non-stacked diagnostics/acceptance worktree from `origin/main=606614f`; activation scheduling remains explicitly incomplete until a real P3 activation batch exists. The requested final read-only GPT-5.6-sol xhigh review remains pending until P4 diagnostics and acceptance are complete.

## 19. P4 diagnostics/acceptance snapshot (2026-08-04)

- Worktree `C:\tmp\starfall-p4-gravity-diagnostics-20260804`, branch `codex/p4-gravity-diagnostics`, starts from `origin/main=d0bc415` (PR #18 status merge); implementation commit is `268b15c`.
- Draft PR #19 targets `main`. It adds the opt-in `GravityDiagnosticsOverlay`, `native_gravity_bridge_smoke.gd`, a 32-source/4096-query/300-tick 1024x1024 gravity benchmark, a large deterministic gravity CTest, high-speed projectile substep/limit reporting, and explicit dirty-chunk (not activation scheduling) labels in the P3 powder benchmark.
- Python Godot contract check passes. Local CMake configure is blocked because this Windows host has no C++ compiler (`No CMAKE_CXX_COMPILER`); local Debug/Release CTest and native benchmarks therefore remain pending. Remote PR CI is the required compiler/Godot verification.
- CI changes build and run the Release gravity, powder/chunk, and ballistics benchmarks plus the new bridge smoke. No hardware timing threshold is enforced; the benchmark reports the 30 Hz budget and P95 utilization.
- No material DTO/P3 powder rule, formal scene, `game/project.godot`, PR #7, Saga assets, or protected main-worktree changes are included. Real activation scheduling and the final GPT-5.6-sol xhigh read-only review remain incomplete.

## 20. P4 diagnostics/acceptance merge status (2026-08-04)

- PR #19 `codex/p4-gravity-diagnostics` was promoted from Draft and merged into `main`; merge commit is `176d7c7108d14d541cc247096e36acfa27d21488`.
- Final head `ee9d189c9d8bacdc661ff785e6115304fb90c684` passed both push and pull-request CI workflows, 8/8 checks each. Native-core included the new Release gravity/powder/ballistics benchmarks and diagnostics CTest; Godot included the bridge diagnostics smoke; Windows native bridge also passed.
- P4 native gravity core, batched shadow transport, GravityFrame role/camera authority, diagnostics overlay, deterministic benchmark reporting, and high-speed sampling diagnostics are merged. The overlay remains opt-in and labels dirty chunks as transport output rather than activation scheduling.
- Local Windows CMake/CTest was not available because no C++ compiler is installed; remote CI is the completed compiler/Godot verification. Python contract check passed locally.
- This status worktree starts from `origin/main=176d7c7`; after it merges, P4 remains complete except for real chunk activation scheduling (requires a future P3 activation batch) and the requested final read-only GPT-5.6-sol xhigh review.

## 21. P4 final read-only review: BLOCKED (2026-08-04)

- Review model: GPT-5.6-sol, xhigh reasoning; read-only. No files were modified, staged, built, or committed by the reviewer.
- P0 blocker — formal Native local-gravity runtime chain is disconnected. `game/scripts/demo/player_controller.gd` creates a private `StarfallSimulationHost` and selects `native_authoritative`, but the formal path never calls `step_fixed()`. `game/scripts/main.gd` and `game/scripts/demo/starseed.gd` continue to write local fields only to `MaterialWorld`; provider dual-write is exercised only by smoke tests that manually advance the host. With the extension enabled, Native tick/TTL/removal do not advance and anchored-seed local gravity regresses from the pre-P4 path.
- P1 blocker — high-speed cross-field boundary sampling is not implemented. `player_controller.gd` samples only the current position; `GravityFrame.transitioning` represents zero-gravity hysteresis only. The transition smoke uses synthetic threshold samples and does not cover a role, local-field/bidirectional boundary, predicted-position batch, or per-tick anti-flip behavior.
- P1 blocker — local source IDs can collide. `native_gravity_provider.gd` uses MaterialWorld IDs for radial sources but its uniform-source request counter is independent; adding a uniform source before a radial source can reuse an ID and be rejected by Native. Uniform sources are not written to the GDScript shadow reference.
- Non-blocking risks: the overlay has no formal runtime consumer and does not show source type/remaining ticks; bridge failures collapse duplicate/not-found cases into `invalid`; the high-speed benchmark uses 1200 px/s and reports two substeps with zero sample-limit hits; older top-of-file handoff statements still contain historical hashes/order text.
- Verification snapshot: final `main=122e5e37b9dcc733dc0820c6312b51ab369c3e18`; PR #19 and #20 final heads had 8/8 push/PR checks; final main push workflow `30849263051` completed all four jobs successfully. Remote CTest/Godot/benchmark checks passed, while local CMake remained unavailable because this Windows host has no C++ compiler.
- Policy: preserve the blockers and current implementation unchanged after this review. Do not mark P4 fully accepted or start follow-up fixes without an explicit new authorization; real chunk activation scheduling also remains a separate P3 dependency.

## 22. Final blocker record landed on main (2026-08-04)

- The review-status document commit is now on `origin/main` as merge commit `cc428899cdb50bf2b2b4911bf29b86931cbfbca9` (PR #21 content, `85f4ce5`). This is the authoritative handoff tip after the review; no implementation files changed after the review.
- The last verified full main workflow before this documentation-only landing was `30849263051` for `122e5e3`, all four jobs successful. The blocker record itself is documentation-only and does not alter runtime behavior or assets.

## 23. P4 blocker repair worktree (2026-08-05)

- Execution-time base was rechecked as `origin/main=cf4f6ee5c957340208155fbb6a4798c31838a3f4`. The isolated worktree is `C:\tmp\starfall-p4-gravity-review-fixes-20260805` on `codex/p4-gravity-review-fixes`; runtime ownership is `b5d5741`, transition hardening is `4b162c1`, and the documentation/status commit is `a20959d`. The branch is pushed and PR #24 targets `main` as Draft.
- This branch addresses the three reviewed blockers without merging PR #23: the formal scene now owns one `NativeGravityRuntime`/provider with a 30 Hz accumulator; starseed local fields are dual-written and explicitly removed; provider IDs are monotonic and independent from request IDs; uniform fields are mirrored by `MaterialWorld`; signed radial strength, TTL preservation, and precise gravity result codes are covered; current/predicted positions are sampled in one native tick; diagnostics and the high-speed sample-limit benchmark are wired into CI.
- P4 remains unchecked until both push and pull-request CI execute real build/test steps and pass, followed by the requested GPT-5.6-sol xhigh read-only review. PR #23 remains Draft/unmerged and its historical no-step/no-log runner failure is retained as infrastructure history, not treated as proof of this branch.
- Local verification: `tests/integration/check_godot_demo.py` passes and `git diff --check` passes. CMake cannot configure because this machine has no C++ compiler; local Godot 4.7.1 headless attempts did not complete, so remote CI is mandatory for native/Godot verification.
- LFS recovery was isolated without deleting data: ACL dump `C:\tmp\starfall-lfs-tmp-acl-20260805.txt` was saved and the old `.git\lfs\tmp` was renamed to `.git\lfs\tmp.blocked-20260805`; no protected ACL was weakened. The main worktree, `game/project.godot`, PR #7, Saga/LFS assets, material DTO v1, material IDs, 64×64 chunk protocol, and P3 activation scheduling remain out of scope and untouched.
