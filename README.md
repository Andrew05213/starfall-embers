# 坠星余烬 / Fallen Stars, Living Matter

> 宇宙中的一切都是物质；每一粒物质都在下坠、反应，并记住自己曾经成为过什么。

《坠星余烬》是一款处于早期开发阶段的二维像素物理动作 Roguelike。玩家驾驶残破星舟，在由可模拟物质构成的星体群间漂泊，以微型重力核心铸造“星种”，追查初炉熄灭的真相，并决定现存世界是否应该成为新宇宙的燃料。

星种不是换皮法术或普通投射物。它是具有真实质量、引力、轨道和物质反应的微型天体：会吸附环境、改变地形，也可能因玩家设计失稳、裂解或引发连锁反应。

## 项目状态

**Pre-alpha · Playable Mechanics Slice**

仓库目前提供工程骨架、可交互的 Godot 早期物理 Demo、可独立编译的 C++20 模拟核心和基础冒烟测试；尚无可发布的游戏版本。首个垂直切片优先验证：

1. 星种构筑是否有趣；
2. 动态重力是否清晰可读；
3. 多步物质反应是否可理解、可复现。

设计文档中的内容规模均为目标，而非当前已实现功能。

### 可玩 Demo 已包含

- 160 × 90 律尘网格，以最近邻放大到 640 × 360；
- 圆形可破坏小星体和指向坠核的径向重力；
- 岩石、砂、水、油、火、烟、熔质、蒸汽和金属；
- 粉末沉降、液体分层、气体上浮、油燃烧、水灭火及水—熔质反应；
- 能绕星体行走、跳跃、推进、瞄准和采掘的角色；
- 生命、核力、物质储量、受击无敌帧、死亡和重开；
- 引核星种、蒸汽矛和斥裂核三种最小构筑，用于测试吸附、材料克制和群体位移；
- 岩壳、油体和孢子三类物质生物，身体构成决定其环境反应和弱点；
- “击败敌人回收坠核尘 → 解锁地维稳定器 → 用引核星种完成激活”的完整胜负闭环；
- 实时任务、资源、冷却、敌人数和模拟遥测 HUD。

这套像素模拟暂由 GDScript 实现，用于快速验证规则；确认玩法后会按批处理边界迁移到 C++ `sim_core`。

## 核心体验

### 玩法循环

`降落 → 观察 → 实验 → 构筑 → 远行`

- **降落**：进入规则陌生的星体。
- **观察**：辨认物质、生态和局部重力。
- **实验**：战斗、挖掘、炼金，验证物质反应。
- **构筑**：获取材料和组件，在星铸器中铸造星种。
- **远行**：保存、改变或摧毁一个世界，继续驶向星海。

### 设计支柱

- **万物可反应**：火、水、沙、血、气体、尸体和建筑共享物质规则。
- **构筑即实验**：组件提供语法，不提供唯一答案。
- **重力即地形**：局部“下方”、轨道和重心变化本身就是关卡。
- **知识即成长**：没有等级压制；理解规则就是最重要的永久成长。
- **选择具有物理后果**：夺走一颗星球的坠核，世界会真实地失稳，而不只是切换一段对白。

### 世界规则

世界由可模拟的“律尘”构成。律尘具有坠、热、流、导、活、记六类倾向。重力并非统一背景，而由星体的“坠核”与局部“坠律”定义；双核、周期翻转、选择性牵引和外置重力都可以成为世界规则。

叙事遵守“事实只有一套，名字至少有三套”：客观物理后果不随阵营立场改变，不同角色只会争夺解释事实的语言。

## 技术栈

| 层级 | 方案 | 职责 |
| --- | --- | --- |
| 游戏表现层 | Godot 4.7.1 Standard | 场景、输入、UI、音频、渲染与编辑器工作流 |
| 模拟核心 | C++20 `sim_core` | 像素物质、反应、动态重力、星种和确定性状态更新 |
| 引擎桥接 | 官方 `godot-cpp` GDExtension | 批量传递命令、事件和脏区块，不做逐像素跨边界调用 |
| 构建与测试 | CMake、Ninja、CTest；后续接入 Catch2 | 独立构建、单元测试、集成测试和基准测试 |
| 内容管线 | TypeScript、JSON Schema、Ajv | 校验材料、反应、组件、事实和本地化数据 |
| 存档 | SQLite + zstd（规划） | 世界事实、实体状态和区块增量 |
| 性能与质量 | Godot Profiler、Tracy、ASan/UBSan、libFuzzer（规划） | 帧分析、热点定位、内存错误与输入模糊测试 |

关键约束：

- `sim_core` 不依赖 Godot，必须能够独立测试和运行。
- 模拟以固定 30 Hz 更新，渲染目标为 60 Hz。
- 世界按 64 × 64 像素区块组织；只激活玩家和事件附近的区块。
- Godot 与 C++ 只交换 `CommandBatch`、`EventBatch` 和 `DirtyChunkBatch` 等批数据。
- CPU 是模拟权威源；GPU 负责呈现，不承担首版权威物理状态。

详细边界见 [`docs/architecture.md`](docs/architecture.md)。

## 仓库结构

```text
.
├── game/                    # Godot 工程、场景、脚本与表现层资源
├── native/
│   ├── sim_core/            # 与引擎无关的 C++20 模拟核心
│   └── godot_bridge/        # GDExtension 批处理桥（待接入 godot-cpp）
├── content/
│   ├── src/                 # 人工维护的内容源
│   ├── schemas/             # JSON Schema
│   └── generated/           # contentc 的确定性输出
├── tools/contentc/          # TypeScript 内容编译器（待实现）
├── tests/                   # 单元测试和集成测试
├── benchmarks/              # 模拟性能基准
├── docs/                    # 架构说明与 ADR
├── third_party/             # 固定版本的第三方依赖
└── .github/workflows/       # 持续集成
```

原始策划和文案 DOCX 是设计输入，不默认进入代码仓库。实现决策以版本化的架构文档、ADR、Schema 和测试为准。

## 本地开发

### 前置工具

- Git 2.40+ 与 Git LFS
- Godot 4.7.1 Standard（非 .NET 版）
- CMake 3.25+
- Ninja 1.11+
- 支持 C++20 的编译器：MSVC v143、Clang 16+ 或 GCC 13+
- Node.js 22+ 与 npm 10+（内容管线接入后使用）

Windows 是首发开发平台；CI 同时在 Linux 验证独立模拟核心。

### 构建模拟核心

```bash
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
```

没有 CMake 时，可用编译器直接执行当前零依赖冒烟测试：

```bash
g++ -std=c++20 \
  -Inative/sim_core/include \
  native/sim_core/src/world.cpp \
  tests/unit/world_smoke.cpp \
  -o /tmp/starfall_world_smoke
/tmp/starfall_world_smoke
```

### 打开 Godot 工程

```bash
godot --path game --editor
```

无图形环境检查：

```bash
godot --headless --path game --quit-after 240
godot --headless --path game --script res://tests/demo_smoke.gd
godot --headless --path game --script res://tests/demo_benchmark.gd
godot --headless --path game --script res://tests/combat_core_smoke.gd
godot --headless --path game --script res://tests/combat_lab_smoke.gd
```

当前启动场景会直接进入枪感 Gate 1 的独立战斗实验场；原早期物理 Demo 保留在 `res://scenes/main.tscn`，可在实验场按 `Esc` 返回。GDExtension 尚未接入，因此两个场景都使用临时 GDScript 模拟器，不会加载 C++ 模拟。

战斗实验场操作：

- `A / D`：沿星体表面移动；
- `W / Space`：跳跃；
- `Shift`：朝光标方向推进，消耗核力；
- `按住鼠标左键 / F`：连续发射高速幼年星种；
- `R`：重置实验场、靶子和枪感指标；
- `Esc`：返回原早期物理 Demo。

实验场包含可射击墙面、静止靶、移动靶和七发击杀的普通敌人。屏幕左上角显示实时射速、首发延迟、命中率与击杀数；本阶段只验证瞄准—开火—命中主干，不接入物质构筑。

原物理 Demo 操作：

- `鼠标左键 / F`：发射当前成熟星种；
- `鼠标右键`：采掘岩石、砂和金属，补充物质储量；
- `1 / 2 / 3`：切换引核星种、蒸汽矛和斥裂核；
- `鼠标滚轮`：循环切换星种；
- `R`：死亡、胜利或任意时刻重新开始。

试玩目标：击败任意三只物质生物，回收坠核尘，再用 `1` 号引核星种命中右上方的地维稳定器。Demo 的玩法闭环、材料克制和观察清单见 [`docs/prototypes/gameplay-demo.md`](docs/prototypes/gameplay-demo.md)；底层物理验证见 [`docs/prototypes/early-demo.md`](docs/prototypes/early-demo.md)。

## 开发路线

- **M0 · 工程地基**：独立模拟核心、Godot 启动场景、CI、批处理桥接口。
- **M1 · 物质沙盒**：少量固体/粉末/液体/气体，区块激活与脏区渲染。
- **M2 · 可读重力**：单坠核、局部向量场、角色朝向和调试可视化。
- **M3 · 最小星种**：引核、种子物质、触发和连接组件，加入预算与失稳反馈。
- **M4 · 井星垂直切片**：一处可探索区域、敌对生态、三至五步反应链和一次有后果的选择。

## 开发约定

- 先写可测规则，再接表现层；核心规则不得只存在于 Godot 场景脚本中。
- 禁止 Godot ↔ C++ 的逐像素调用。
- 所有随机过程显式携带种子；模拟更新使用固定时间步。
- `content/generated/` 只能由内容编译器生成，禁止手改。
- 第三方依赖必须固定版本；`godot-cpp` 必须匹配 Godot 4.7 系列，不跟随浮动 `main`。
- 大型二进制资源使用 Git LFS；`.godot/`、构建产物和本地缓存不提交。
- 改变架构边界或存档兼容性的决策必须新增 ADR。

更多协作规则见 [`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`AGENTS.md`](AGENTS.md)。

## 版权

本项目尚未选择开源许可证。除非权利人另行书面授权，代码、文本、设定与美术资源保留全部权利。
