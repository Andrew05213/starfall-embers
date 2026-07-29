# 设定裁决台账

> 自动生成自 `content/src/design/decision-register.json`；请勿手改。

| ID | 标题 | 状态 | 版本 | 影响内容 |
| --- | --- | --- | --- | --- |
| `well.departure.repair-old-ship` | 首发切片以修复旧船离开井星 | frozen | v0.1 | well.departure, well.state, saga.arrival |
| `saga.primary-resolution.rotation-calendar` | 萨迦首发切片固定为重建轮坠历 | frozen | v0.1 | saga.main-route, saga.witness, saga.revisit |
| `saga.revisit.first-rotation` | 萨迦回访展示第一次轮坠 | frozen | v0.1 | saga.revisit, saga.world-state, asset.saga.variants |
| `asset.saga.first-slice-specification-only` | 萨迦首发素材只交付占位规格 | frozen | v0.1 | asset.saga, asset.validation |
| `furnace.final-endings` | 六种终局继续保持开放 | variable | v0.6 | furnace.endings, saga.scope |

## 首发切片以修复旧船离开井星

- ID：`well.departure.repair-old-ship`
- 状态：`frozen`
- 版本：`v0.1`
- 变更理由：为首发内容切片提供稳定开场，并避免引入尚未实现的崩塌、救援与留守系统。
- 依据：`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/00_阅读说明与冻结基线.md`；`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/01_世界观与整体主线.md`
- 不可破坏约束：井星四条离星路线继续存在于总设定；本切片只实现修复旧船。；修复旧船不得取走井星坠核，也不得触发拔核崩塌或扩大救援容量。
- 验收：切片入口记录旧船已修复、井星共同下方仍存在、砾同行。；运行时清单中不得出现坠核移除或井星崩塌状态。

## 萨迦首发切片固定为重建轮坠历

- ID：`saga.primary-resolution.rotation-calendar`
- 状态：`frozen`
- 版本：`v0.1`
- 变更理由：用可预测的双向坠律验证局部重力玩法，并把共存表现为持续维护。
- 依据：`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/02_星球篇章设计.md`
- 不可破坏约束：轮坠历要求三项校准全部完成后才能恢复。；本切片不能把萨迦坠核或法则见证写成同一物件。；恢复轮坠历不等于消除翻转事故或阵营冲突。
- 验收：三项校准缺任一项时，轮坠历恢复节点不可完成。；结果写入受授的重力与方向见证，且萨迦坠核保留。

## 萨迦回访展示第一次轮坠

- ID：`saga.revisit.first-rotation`
- 状态：`frozen`
- 版本：`v0.1`
- 变更理由：证明主星选择会持续改变可探索世界，而非仅切换结算文本。
- 依据：`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/02_星球篇章设计.md`；`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/04_动态叙事与任务编排.md`
- 不可破坏约束：回访必须发生在离开萨迦并完成至少一次航行推进之后。；回访展示外昼城、内海穹与无下城的不同适应压力，不新增第二个终局选择。
- 验收：回访前置条件包含轮坠历已恢复和至少一次航行推进。；回访目标为中和层校准，结论保留翻转风险与维护代价。

## 萨迦首发素材只交付占位规格

- ID：`asset.saga.first-slice-specification-only`
- 状态：`frozen`
- 版本：`v0.1`
- 变更理由：在不扩大二进制资产与Git LFS风险的前提下，为后续像素生产提供可验收规格。
- 依据：`project_reference/坠星余烬_当前设定与素材_2026-07-26/设定集/井星_星际单元设定集_V0.3/README.md`；`project_reference/坠星余烬_当前设定与素材_2026-07-26/素材/地质背景/素材清单与验收状态.md`
- 不可破坏约束：本切片不新增 PNG，也不把当前地质背景候选接入正式场景。；环境规格必须使用160×90原生单元、20像素人物标尺、硬边二值Alpha和不超过48色的环境色板。
- 验收：五个萨迦区域均有轮坠前、中、后状态说明。；所有资产条目状态为specification-only，且不引用未验收地质背景。

## 六种终局继续保持开放

- ID：`furnace.final-endings`
- 状态：`variable`
- 版本：`v0.6`
- 变更理由：保留总设定的终局开放性，不让垂直切片替代全局裁决。
- 依据：`project_reference/坠星余烬_当前设定与素材_2026-07-26/文档/01_世界观与整体主线.md`
- 不可破坏约束：首发切片不得把任一终局写成唯一正史或唯一正确路线。
- 验收：切片内容不声明任何官方真结局。
