# 技术架构

## 目标

首阶段只证明三件事：模拟可以独立运行、Godot 可以低成本呈现模拟结果、内容规则可以被机器校验。任何提前增加的复杂度都必须服务这三个目标。

## 运行时边界

```text
Godot scenes / UI / input / audio / rendering
                 │
                 │ command batches
                 ▼
        godot-cpp GDExtension bridge
                 │
                 │ fixed-step API
                 ▼
       C++20 engine-independent sim_core
                 │
                 ├── chunks and materials
                 ├── reactions and temperature
                 ├── gravity field cache
                 ├── starseed component VM
                 └── facts and persistence snapshots
```

桥接层在每个模拟步开始前提交一批命令，结束后取回事件和脏区块。材质数组、温度场或像素颜色不得通过逐像素函数调用跨越边界。

## 模拟模型

- 固定步长：30 Hz；表现层允许插值到 60 Hz。
- 空间划分：64 × 64 像素区块。
- 激活策略：玩家、活跃反应和高速实体附近的区块更新；远区块休眠或降频。
- 数据布局：高频属性使用 SoA；稀疏、低频的“记性”等历史数据进入 sidecar。
- 重力：显式坠核/引核源生成低分辨率向量场并缓存，不进行逐像素 N 体求解。
- 确定性：随机种子、命令顺序和固定步编号都进入重放状态。

### 当前原生化进度

`SimulationHost` 已承载 ballistics 与 Godot 无关的材质区块存储。材质世界使用单字节
row-major cell、固定 64×64 区块和 DTO v1：Godot 整批提交绘制/采掘命令，并整批读取有序
结果与紧凑脏区 bytes。右侧、底部非整块边缘只传输有效区域，材质编号 `0..9` 由跨语言合约
测试锁定。

这一边界不代表材质玩法权威已经迁移。砂、水、火、温度、反应和激活区块调度仍留在当前
GDScript 参考世界；P3 必须按类别完成确定性双跑后再切换所有权。DTO 版本、区块尺寸或材质
编号变化必须按 ADR-0004 升级协议，不能静默改变版本 1。

## 星种执行

星种的“核、质、形、律、触、连”组件先编译为受预算约束的中间表示，再由模拟核心执行。初版不嵌入通用脚本语言。预算至少限制嵌套层数、单步事件数、子星种数量、可吸附质量和重力源数量。

## 内容与叙事

`content/src` 是人工编辑的权威输入。`contentc` 验证唯一 ID、引用、反应参数、术语和物理—文本一致性，并以确定顺序写入 `content/generated`。

世界客观状态存入 `WorldFactStore`。任务、阵营文本和环境叙事只能读取并解释事实，不能各自维护冲突的真相。

## 存档方向

计划使用 SQLite 保存元数据、世界事实、星体、区块增量、事件、玩家与库存，再以 zstd 压缩大块二进制增量。正式实现前必须先冻结迁移策略、校验和与崩溃恢复边界。
