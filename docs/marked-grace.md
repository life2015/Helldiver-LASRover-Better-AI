# 0.7.13 标记评分宽限

标记是否存在、候选是否可选、当前锁定是否仍适用标记计时是三件事。0.7.12将前两者合并，导致一次非正缓存评分即可丢掉标记提示和长照射窗口。实机证据见[距离调查](marked-range-investigation.md)，评分 -1 的全部原生语义仍未确定。

## 当前规则

- `markers.read` 的前两个返回值仍是严格可选标记与状态；新增第三个 `marker_observation` 描述尚有效的本地标记。观察记录不授予选敌权限，也不改变 Recent 或普通20米近处排序。
- `snapshot` 记录候选拒绝原因，顺序为 identity、flags、faction、score。只有前面条件通过而评分非正，才算单独评分失效。缺失候选单独报告 missing。
- 策略仅为当前锁定且已验证有效的标记目标保存一个缓存。标记记录token、完整实体身份及目标保持一致，生命周期继续有效，且只有score失败时，从最近一次有效观察开始最多宽限1.5秒。边界达到1.5秒即结束。缓存保存身份、计时和token，不保存可写地址。
- 宽限期间沿用4秒攻击、3秒连续未攻击、5秒最长锁定计时；计时继续，评分恢复不清零。重复标记也不重置这三个计时。真实同步攻击状态变化仍按原规则更新攻击/未攻击计时。
- 取消、到期、换标、身份变化、来源/阵营失效、候选缺失、离开节点6/7、观察中断、换玩家/背包/目标会立即取消宽限。不能确定死亡时不凭标记断言存活；持续单独评分失效最多保留上述1.5秒计时待遇。
- 宽限不是强制锁定，不阻止原生AI自行换目标；不把旧候选重新加入候选池。新转火仍要求当前有效候选及提交前校验，实际写入租约仍是0.25秒。

## HUD 与日志

| 提示 | 含义 |
| --- | --- |
| 绿色 MARKED / waiting for rotation | 标记当前可选，等待正常转火 |
| 绿色 MARKED / attack 或 no attack | 已同步锁定后的攻击进度，或未攻击等待进度 |
| 黄色 MARKED: WAITING / grace X.Xs | 当前目标处于评分宽限，显示剩余时间 |
| 黄色 MARKED: WAITING / score unavailable | 标记还在，但当前评分不可用且没有锁定宽限 |
| outside candidate list / identity unavailable / native flags reject / candidate filtered | 候选缺失、身份不可用、原生来源标志不通过、阵营筛选不通过 |
| NATIVE / mark expired | 仍在原始队列里的标记记录已到期 |
| NATIVE / mark ended / canceled / expired | 记录已不在有效队列，无法可靠区分主动取消、到期后移除等原因 |

活动请求优先显示 MOD: MARKED / NEAREST / NATIVE PICK；停止状态优先于所有标记显示。结束提示最多保留1.5秒；它只说明状态，不延长标记生命周期。HUD沿用五行保留式绘制与10Hz上限，No HUD有相同索敌逻辑。

日志新增 `marker_reason`、`marker_notice`、`marked_grace_remaining`。`marked_target` 现在可以表示暂不可选但仍存在的标记；必须同时看 `marker_status`，不能再将非零ID直接视为可发起选择。

## 验证和部署

运行 `python scripts/test.py`。重点回归：1.5秒边界、恢复后不重置进度、取消立即退出宽限、未验证目标不使用缓存、3/5秒兜底不延长、缺失快照不跨场景保留身份，以及标记观察不产生新的写入资格。支持两套布局，旧布局仍没有标记功能。

打包命令 `python scripts/package.py --channels v14 v15`，输出HUD/No HUD四包。游戏运行时不能替换正在使用的归档；关闭后按[部署指南](deployment.md)更新自有模块，保留其他Mod及官方加载器。新进程日志应为 experimental-0.7.13。

当前离线验证不等于真实战斗验收。下一轮应对照宽限倒计时、目标ID和转火请求，确认短暂评分变化恢复后继续原进度、持续不可用或标记取消能及时退出。
