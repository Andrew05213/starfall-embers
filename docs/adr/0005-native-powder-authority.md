# ADR-0005：固定向下粉末规则的原生权威迁移

- 状态：已接受
- 日期：2026-08-03

## 背景

P2 已完成材质 cell 存储、64×64 区块、批命令、脏区传输和 checksum，但材质运动仍由
GDScript `MaterialWorld` 负责。直接把整个混合材质世界切到 C++ 会同时改变砂、水、火、
熔质、反应和重力的所有权，也会把 P4 的径向重力接口提前带入 P3。

## 决策

本批只把 `SAND` 在 `AIR` 中的运动规则交给原生 `World`：

- 方向固定为网格 `+Y`，不读取坠核或局部重力；P4 再迁移重力采样。
- 每个固定 tick 使用显式 seed 驱动的 32 位 LCG，生成 canonical row-major 扫描的循环起点。
  每个 cell 恰好访问一次；moved 标记阻止同一砂粒在一个 tick 内重复移动。
- 每个未移动砂粒按固定顺序尝试正下、优先下斜、另一侧下斜、优先水平和另一侧水平；
  目标必须是 AIR。越界、ROCK、METAL 及所有其他材质均阻挡移动。
- 源格和目标格进入现有 dirty chunk 机制；DTO v1、材质编号 `0..9`、区块尺寸和 GDExtension
  批接口不变。
- C++ 是 `SAND↔AIR` 规则的规范实现；独立 GDScript 参考器逐 tick 比较 cell bytes 和
  checksum。现有混合材质正式场景暂不切换，直到未来具备明确的混合所有权和批量同步边界。

## 后果

- 相同 seed、命令顺序和 tick 可以重放相同的砂状态、随机状态、dirty chunks 和 checksum；
  不同 seed 只在对称候选路径上产生可解释的确定性分歧。
- ROCK、METAL、WATER、OIL、FIRE、SMOKE、LAVA 和 STEAM 在本批原生步中保持静止；不宣称
  液体、气体、反应、温度或区块激活调度已经迁移。
- `World::step()` 的行为从只推进 tick 变为“推进 tick 并运行粉末规则”，因此 snapshot 的
  `random_state` 从本批开始反映 LCG 状态。
- 1024² benchmark 把每 tick dirty chunk 数视为活跃区块观测值，并报告 30 Hz 的 33.333 ms
  帧预算；这不是 P3 的激活调度实现，也不设易受硬件抖动影响的 CI 时间阈值。

## 验收

Native 单元测试覆盖垂直/斜向/水平移动、阻塞、边界、跨区块、单 tick 不重复移动、静止材质、
seed 分歧和双宿主重放。Godot headless 测试使用独立参考器逐 tick 比较完整 cell 状态和
checksum；现有 DTO transport、Godot smoke、Python 合约和 demo benchmark 继续通过。
