# ADR-0006：原生实体重力与角色重力帧所有权

- 状态：Accepted with review-repair constraints
- 日期：2026-08-05

## 背景

P4 将主坠核、局部场和高速实体采样迁移到 C++ `GravityField`。此前正式演示场景
仍由玩家创建一个未推进的私有 Native host，星种也只写入 `MaterialWorld`，因此
Native 局部源的 tick、TTL 和移除不会在实际运行中生效。

## 决策

- 正式场景只允许一个 `NativeGravityRuntime` 持有 `StarfallSimulationHost` 和
  `NativeGravityProvider`；Runtime 以固定 30 Hz、最多三步追赶的时钟推进 host。
- 星种在固定处理顺序中先提交源命令，Runtime 再推进 Native tick，玩家随后以一个
  批次采样当前位置和预测位置；镜头只读取玩家产生的 `GravityFrame.up`。
- `GravityField` 是实体重力的唯一计算权威，包含一个主坠核和按稳定 source ID
  顺序求和的局部径向/常向量场。径向 strength 允许有限有符号值：正值吸引、负值排斥。
- Native source ID 与请求 ID 使用独立、单调递增的命名空间；provider 维护其 ID
  与 `MaterialWorld` 内部 ID 的映射。reset 后不复用仍可能被旧对象持有的 provider ID。
- 正式星种使用永久 Native 源和显式移除；通用 provider 仍支持有限 tick TTL，更新
  必须保留原始 `expires_at_tick`。
- GDScript `MaterialWorld` 保留为 fallback/shadow 参考，常向量场、边界和稳定求和
  必须与 Native 对齐。material DTO v1、材质编号、64×64 区块和 P3 `+Y` 粉末规则不变。
- `gravity_transport_dto_version` 继续为 1。批命令失败保持原子性，并通过
  `accepted`、`invalid`、`duplicate`、`not_found` 结果码报告原因。

## 角色与镜头规则

- 每个角色固定 tick 使用同一 `GravityFrame` 完成贴地、跳跃、推进、速度分解、朝向
  和瞄准。零重力退出/重新进入阈值为 `0.001/0.002`。
- 当前位置与预测位置的零重力状态、主导源或方向（夹角超过 15°）发生变化时，帧标记
  `transitioning`；该标记不提前修改当前 tick 的权威方向。
- 零重力死区保留上一次有效 `up`；切线从两个候选方向中选择与上一次点积较大的方向。
- 传送/reset 立即重采样并清除角色、镜头插值历史。镜头只做表现平滑，不参与权威计算。

## 后果与边界

- Native 与 MaterialWorld 可在迁移期双写，且不会因为实体重力迁移改变材质 authority。
- 高速弹体使用固定空间间距子步和固定上限；不得使用墙钟、自适应耗时或随机采样。
- 诊断叠层可以显示 dirty chunks，但不得将其称为 activation scheduling；真实区块激活
  调度仍属于后续 P3 工作。
