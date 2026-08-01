# 原生材质区块与批传输基础

## 阶段边界

本阶段定向移植旧 PR #3 的可复用存储基础，并手工适配 PR #4 已合并的 ballistics 与
`SimulationHost`。它建立可运行的 GDExtension 批传输，不迁移砂、水、气体、火焰、熔岩、
温度、反应或重力场规则；当前可玩场景中的 GDScript `MaterialWorld` 仍是材质玩法权威。

## 已实现

- 一个字节一个 cell 的连续 row-major 存储，材质 ID 与 GDScript `AIR..METAL` 对应 `0..9`。
- 固定 64×64 区块；边缘区块使用有效宽高和紧凑 bytes，不做 64×64 填充。
- DTO v1 命令批包含圆形绘制与圆形采掘；结果与输入保持相同顺序和数量。
- 非法 DTO 版本、材质或数组结构在写入前整体拒绝，批次不会留下部分修改。
- 脏区批按 chunk row-major 稳定排序，同一区块每次 drain 只出现一次；所有快照构造成功后
  才清除 dirty 标志。
- `SimulationHost` 在同一固定步中消费 projectile 与 material 命令，输出共享权威 tick。
- Godot 使用 PackedArray 一次提交命令，一次读取结果，一次读取拼接后的脏区 payload；没有
  逐像素跨边界 API。
- seed、tick、随机状态、配置、DTO 版本和 cells 进入 snapshot/checksum，可由相同命令流重放。

## 验证与 benchmark

Native 单元测试覆盖配置与 DTO 拒绝、固定区块、材质协议、圆形裁剪、批内顺序、采掘统计、
边缘区块、稳定脏批、双宿主 tick 与确定性重放。Godot headless smoke 通过 DTO v1 提交四条
命令，并验证三个脏区的坐标、有效尺寸、offset、4,486-byte payload 与 checksum。

`starfall_native_chunk_benchmark` 使用 1024×1024 世界、256 个 64×64 区块和 2,048 条确定性
圆形绘制命令，报告命令批耗时、活跃脏区数、payload bytes、脏批消费耗时、checksum 与
第二宿主重放结果。benchmark 记录趋势，不设置易抖动的 CI 时间阈值。

## 后续

P3 按固体、粉末、液体和气体逐类迁移规则，每类都保留 GDScript 参考模型、确定性重放与
性能证据。DTO v1 不是存档格式；持久化兼容性必须由后续独立 ADR 决定。
