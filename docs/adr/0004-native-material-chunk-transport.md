# ADR-0004：原生材质区块与版本化批传输

- 状态：已接受
- 日期：2026-08-02

## 背景

PR #4 已让 `SimulationHost` 承载可切换权威弹道，但材质世界仍由 Godot 的
`MaterialWorld` 维护。旧 PR #3 证明了连续单字节存储、64×64 区块、批命令、脏区与
checksum 的可行性，却基于 PR #4 之前的宿主结构，且没有冻结 GDExtension DTO 版本。

直接合并旧 PR 会形成第二套原生宿主；直接暴露 cell getter 则会把桥接退化为逐像素调用。
同时，P2 只负责数据地基，不能借机宣布砂、水、火、温度或反应规则已经迁移。

## 决策

`SimulationHost` 同时拥有 ballistics 和一个 `World` 材质存储，两者使用相同固定 tick 与显式
seed。材质区块固定为 64×64；世界右侧和底部边缘只传输有效宽高和紧凑 row-major bytes。
材质编号 `AIR..METAL` 固定为 `0..9`，并由跨语言合约测试约束。

材质命令、结果和脏区批使用 DTO v1：

- Godot 通过一次 PackedArray 调用提交整批绘制/采掘命令。
- `SimulationHost::step()` 在固定步边界消费材质命令和弹道命令。
- Godot 通过一次调用读取有序结果批，通过一次调用读取稳定 chunk row-major 脏区批。
- 脏区 bytes 以单个连续数组返回，配套 chunk 坐标、有效宽高和 byte offset；不提供逐 cell
  GDExtension getter。
- 未知 DTO 版本、非法材质或结构不一致的批次在任何写入前整体拒绝。
- checksum 包含 DTO 版本、配置、seed、tick、随机状态和完整 cell bytes，用于重放验证。

DTO v1 是运行时传输协议，不是持久化格式。未来改变字段语义、材质编号、区块尺寸或布局时
必须新增 DTO 版本；不得静默复用版本 1。

## 后果

- ballistics 与材质存储只有一个原生宿主和一个固定步入口，不会形成 PR #3 的平行核心。
- 1024² 世界可通过 2,048 条确定性命令、脏区 payload 和 checksum 建立可重复 benchmark。
- 当前可玩场景仍以 GDScript `MaterialWorld` 为材质玩法权威；P3 按材质类别逐步迁移前，
  C++ 存储只作为已接通桥接的基础与重放目标。
- 进程内 snapshot 和 checksum 不承诺存档兼容；正式持久化仍需独立 ADR。
