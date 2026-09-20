# 调试手册

当前实现0.7.4；更新于2026-09-19。加载器渠道、HUD变体和游戏进程需同时确认。

## 先确定正在看哪一次运行

先记录游戏进程 ID/启动时间、安装包 SHA、运行日志版本及文件时间。不能把旧 `mode=diagnostic` 日志或上一场的计数当成当前状态。

| 日志 | 用途 |
| --- | --- |
| `%LOCALAPPDATA%/RoverFireSpread-startup.log` | 仅v12/v14的启动桥阶段；v15不会更新此旧文件 |
| `%LOCALAPPDATA%/RoverFireSpread.log` | 当前进程的运行状态和累计计数，常规约每 2 秒覆盖写 |
| `%LOCALAPPDATA%/BingusSharedLoader.log` | v12加载器的旧日志路径；不代表Rover已运行 |
| `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log` | v14/v15加载器日志；v15核对发现条目及Rover loaded后，再检查Rover主日志 |

Rover主日志不是逐事件追加记录。连续观察两个时间点和计数增量，必要时用观察器把日志一并保存。只看到 `shared_loader_returned` 不够；只看到 `rover_state=waiting_for_mission` 也只证明入口完成，仍要看主日志的 `samples` 持续增长。

## 运行字段的准确含义

| 字段 | 含义和注意事项 |
| --- | --- |
| `build_id` / `mode` / `process_id` | 对应版本、实验或诊断模式、游戏进程身份 |
| `hud_enabled` / `hud_status` / `hud_error` | No HUD成功运行应为false/disabled；HUD面板状态见[面板说明](hud.md)。`visible`表示绘制调用完成，不代表实机已确认可见 |
| `decision` / `active_request` / `active_ranking` | 当前轮询的决策原因、临时请求是否仍在生效及其排序模式 |
| `no_attack_elapsed` / `active_reason` / `last_request_reason` | 0.6未进入同步攻击状态的累计秒数；活动/最近请求原因为`attack_window`、`lock_timeout`（连续未攻击）或`lock_max_duration`（同目标占用兜底） |
| `lock_elapsed` / `lock_limit` | 最近策略计算的同目标连续有效观察时间/1.5秒阈值。跨攻击状态切换保留，提交请求或观察失效后重计；请求期间可能仍显示提交前的值，不是实时物理锁定时长 |
| `target` / `target_synced` / `active_target` | 0.5.1：行为目标ID、是否与瞄准目标同步、当前活动请求指定的目标ID；HUD仅在同步时显示Locked，active_target只供Next显示 |
| `last_request_at` / `last_request_ranking` / `last_request_target` | 最近一次成功提交的请求；与当前状态分开。at为进程内单调时钟值，不是系统时间 |
| `last_request_finished_at` | 请求恢复完成的进程内时钟值，HUD从此额外保留绿/黄标题0.5秒并标注(last)。新请求提交时清空；实际干预仍以active_request为准 |
| `compatibility` / `game_sha256` / `exe_sha256` | 0.4.1新增：`baseline_hash_match`为基线哈希相同，`unverified_build_attempt`为不同但尝试运行；实际哈希用于后续定位。该字段不表示初始化已成功 |
| `samples` | 控制器完成快照调用的累计次数，包含等待状态；不是有效攻击帧数 |
| `requests` | 实验控制器成功提交的临时修改请求数；不是命中数 |
| `rotations` | 待恢复请求期间观察到同一无人机改为另一个非零目标的次数；不是严格因果证明 |
| `would_rotate` | 诊断控制器推演次数，没有写入；实验模式通常为 0 |
| `id` / `target` / `node` | 最近快照的无人机、目标及行为节点 |
| `candidates` / `eligible` | 最近快照中的候选条目数和可用条目数，条目不必等于独立敌人数 |
| `history_count` / `history_limit` / `history_seconds` | 0.6近期记录数、上限1、有效期1秒；记录数不应超过1。旧0.4/0.5版本为8项/4秒 |
| `distance_available` | 本次快照无人机位置可读；不保证每个候选坐标都有效 |
| `planned_target` / `planned_distance` | 本次计划目标及所用距离（米）；`previous_target`时为目标间距离，其余距离排序为距漫游车。不是请求成功或命中证明 |
| `selection_basis` / `active_basis` / `last_request_basis` | 计划/活动/最近成功请求的距离依据：`previous_target`相邻敌人、`near_rover`远目标转回15米内、`rover_fallback`当前目标坐标不可用、`timeout_rover`超时解卡、`native`两种距离均不可用。计划和活动字段会清空，短请求优先查看last字段 |
| `ranking` | `nearest`表示计划用了距离排序；`native_distance_unavailable`表示候选池无可用距离，退回原生选择 |

快照不可用时部分字段可能仍保留上次值，不能脱离 `status` 判断。计数跨任务累计；新任务或新无人机应看增量和 ID 变化，不期待计数归零。待恢复分支提前返回时，日志显示的目标也可能稍落后于外部读到的即时目标。

`requests - rotations` 不能直接当成失败率：请求可能超时、未导致非零目标变化，或起止点跨越观察窗口，日志还有约 2 秒刷新延迟。也不能把外部 `diagnostic_would_rotate` 与安装模块的 `requests` 相加。

## 常见状态

| 状态或错误 | 解释与排查方向 |
| --- | --- |
| `waiting_for_runtime` | 指针为空、读不到完整数据等暂时条件；0.3 会重试。长期持续才需要查具体管理器 |
| `waiting_for_consistent_snapshot` | 一次读取中身份/映射发生变化；丢弃这一帧并重试 |
| `waiting_for_mission` / `waiting_for_player` / `waiting_for_avatar` | 飞船、载入或玩家切换阶段常见 |
| `no_backpack` / `not_laser_backpack` | 没装备激光狗或装备了其他背包，不会干预 |
| `waiting_for_drone` / `drone_not_targeting` | 无人机尚未进入可处理的 registry |
| `pack_holder_mismatch` / `avatar_not_local` / `drone_not_local` | 归属检查没有通过；不能删掉检查来强行生效 |
| `observing` | 采样正常；不意味着正在发出请求 |
| `rotation_requested` | 请求已提交，等待原生选择和恢复 |
| `precondition_changed` | 写入前条件变化，本次没取得修改资格；后续可再观察 |
| `write_failed` / `restore_pending` / `restoration_requires_retry` | 停止新请求并尝试清理，保存日志及现场条件 |
| `Runtime signature mismatch` | 关键签名不匹配，仍停止；按布局迁移流程处理。0.4.1起单纯整文件哈希不同不再导致停止；旧版`Unsupported…`日志需核对build_id |
| `candidate group bound` / `invalid cached score` 等 | 结构校验失败；不要简单增大上限或吞掉错误 |

停止后的清理可能继续重试而日志不再变动，不要仅靠最后一条消息推定旧内存已恢复。正常退出游戏会结束该进程中的全部临时修改；下一次启动前先解决停止原因。

## 如何区分原生行为与Mod筛选

| 情况 | 实际含义 |
| --- | --- |
| `active_request=true`，`active_ranking=nearest` | Mod按距离选定允许目标，但仍由原生执行目标切换和攻击 |
| `active_request=true`，`native_distance_unavailable` | Mod仍限制允许候选，具体目标由原生评分决定，不是完全撤销Mod干预 |
| 无活动请求，`attack_window` / `tracking` / `no_alternative` / `retry_delay` | 等待计时、原生跟踪、没有替代目标或请求间隔，通常不代表异常 |
| `precondition_changed` | 本次预校验未通过，放弃请求，后续再观察 |
| 暂时缺数据 | 等待重试；如有旧请求则先尝试恢复，不能仅看等待状态认定已全部恢复 |
| 停止且`cleanup_pending=true` | 停止新请求，但可能仍有未恢复修改，不称为已完全恢复原生行为 |

HUD绿/黄标题带(last)已经结束请求，只保留0.5秒供观察；Next的(last)独立保留到提交满2秒。无HUD不等于原生，No HUD版完全通过日志确认。日志约2秒覆盖写，容易错过短请求，因此结合last_request字段及采样增量判断，不能拿单帧日志当完整事件序列。

## 有其他活敌但持续锁住同一目标

先区分请求未产生与请求后未切换：比较同一target的requests/rotations增量、decision和node/synced时间序列。中甲挡伤害不直接阻止策略计时，因为没有命中或伤害读取；已发现状态短暂交替时两种计时互相清零的盲区，详见[盾虫锁定调查及复现](hive-guard-lock-investigation.md)。0.7.4已增加独立计时并通过交替状态回归，但未确认是反馈现场的唯一原因。主日志2秒刷新不足以排除这种短周期切换。

## 整机卡死或黑屏

先区分用户正常退出、游戏进程崩溃、蓝屏、整机失去响应。记录准确时间、包哈希/渠道/HUD变体、驱动版本及同时运行的其他Mod，再保存事件与日志。当前GPU线索、旧转储时间误判和纯策略耗时结论见[故障调查](crash-investigation-2026-09-19.md)。No HUD可用于控制变量对照，不能从一局稳定或没有Lua错误直接排除Mod/驱动路径。

## 外部只读采样

在项目根目录、Python 和目录依赖已准备好的前提下：

```powershell
$gameProcess = @(Get-Process helldivers2 -ErrorAction Stop)
if ($gameProcess.Count -ne 1) { throw 'Expected exactly one game process' }
& $pythonExe scripts/observe.py --pid $gameProcess[0].Id --seconds 40
```

持续时间必须大于 0 且不超过 60 秒。`Reader` 只申请 `QUERY_INFORMATION | VM_READ`（`0x410`），检查 EXE/DLL 哈希和加载签名，不写游戏、不调用原生游戏函数。遇到访问拒绝时停止调查路径，不改变保护或升级权限。读取失败也可能来自用户退出，应核对进程，不自动归因为崩溃。

观察器在独立 Lua state 中执行相同的 snapshot/policy/controller，但控制器 `enabled=false`。已安装实验 Mod 可以同时在游戏内写数据，因此观察器看到的是**带 Mod 的游戏状态**，不是天然的无 Mod 对照组。

输出在同级 `research/artifacts/`：

| 文件 | 内容 |
| --- | --- |
| `rover-policy-时间.jsonl` | 约 10 Hz 的只读状态、候选、读错误及同时读取的 Mod 日志 |
| `rover-policy-时间.traceN.json` | 每类结果首份稀疏读取快照，最多 10 类，用于离线分析布局 |
| `*.summary.json` | 已有测试的人工分析摘要；观察器本身不自动生成 |

JSONL 的 `fields` 顺序为：无人机 ID、目标 ID、节点、可用候选条目数、外部推演次数、以逗号连接的 `目标ID:是否可用` 列表。值是字符串。`mod_log` 单独保存安装模块的键值；必须核对其中 `process_id`。`mod_log_mtime` 为文件时间，日志可能被重复采样；罕见时刻也可能刚好读到覆盖写期间的空/不完整内容。

0.4在上述6个fields后追加：距离原点是否可读（1/0）、`ID:距离或unknown`列表、计划目标ID、排序模式、历史条目数。0.6末尾再追加decision及no_attack_elapsed。旧采样缺少这些列，应按长度兼容读取。外部观察器的历史从采样启动才开始，与游戏内累积历史不完全相同；不能要求二者每次推荐同一个目标。

trace 是多次读取形成的稀疏记录，不是原子全进程快照，也不是自动可重放测试。若要转换成 fixture，需要处理重复地址和先后状态，不应随意拼成一个“同一时刻”的内存图。

## 调试顺序

1. **飞船**：确认版本、PID、日志时间和计数持续增长。入口失败时不要求测试者先打一场。
2. **单目标**：没有有效替代目标时应继续原有攻击。日志中有效目标数量和屏幕实际可见怪物数量不是一回事。
3. **多目标**：记录请求和目标变化增量，肉眼确认是否在目标仍活着时转走；同时观察转向空耗和停火。
4. **更密集或不同敌人**：改变一个条件，记下场景、候选规模、异常和包版本，不把难度变化等同于所有敌人覆盖。
5. **生命周期**：任务切换、丢包重捡、换背包、死亡复活、回船等，重点看旧请求恢复与新身份识别。

当前没有录屏同步器、逐次请求事件日志或 FPS 采集器。若要计算命中时长、点燃覆盖率、精确成功率或性能差异，需要新增对应证据，不能用现有计数替代。

## 已踩过的调试陷阱

0.1 时共享加载器日志是新的，Rover 日志却是旧测试内容，无法据此确认模块是否初始化。旧桥接测试 mock 了 `require`，只验证请求加载，没有执行实际入口。0.2 改为直接初始化，并在隔离测试中执行实际编译字节码。

旧的入口测试只在 fixture 安装期间替换 `io.open`，随后调用 update/shutdown 时恢复了真实 IO，导致写入真实 `%LOCALAPPDATA%` 日志。现测试隔离整个生命周期。其他测试也不要污染真实 Mod 状态文件。

0.2 启动桥证明初始化完成，但首次轮询碰到空指针后永久停止，`samples=0`。0.3 将数据尚未就绪和采样中身份变化与真正的结构错误分开，自动重试前两类。不能通过捕获所有错误后继续写入来解决。

曾把旧主日志移到本地 artifacts 后才读到新的错误日志；文件可见性现象的具体原因没有证明。遇到类似问题先保存旧文件、核对 PID/时间并排查，不能写成已知的系统或反作弊机制。
