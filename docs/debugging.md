# 调试手册

## 先确定正在看哪一次运行

先记录游戏进程 ID/启动时间、安装包 SHA、运行日志版本及文件时间。不能把旧 `mode=diagnostic` 日志或上一场的计数当成当前状态。

| 日志 | 用途 |
| --- | --- |
| `%LOCALAPPDATA%/RoverFireSpread-startup.log` | 启动桥各阶段及 Rover 初始化后的状态 |
| `%LOCALAPPDATA%/RoverFireSpread.log` | 当前进程的运行状态和累计计数，常规约每 2 秒覆盖写 |
| `%LOCALAPPDATA%/BingusSharedLoader.log` | 原加载器可选模块状态；不代表 Rover 已运行 |

日志不是逐事件追加记录。连续观察两个时间点和计数增量，必要时用观察器把日志一并保存。只看到 `shared_loader_returned` 不够；只看到 `rover_state=waiting_for_mission` 也只证明入口完成，仍要看主日志的 `samples` 持续增长。

## 运行字段的准确含义

| 字段 | 含义和注意事项 |
| --- | --- |
| `build_id` / `mode` / `process_id` | 对应版本、实验或诊断模式、游戏进程身份 |
| `samples` | 控制器完成快照调用的累计次数，包含等待状态；不是有效攻击帧数 |
| `requests` | 实验控制器成功提交的临时修改请求数；不是命中数 |
| `rotations` | 待恢复请求期间观察到同一无人机改为另一个非零目标的次数；不是严格因果证明 |
| `would_rotate` | 诊断控制器推演次数，没有写入；实验模式通常为 0 |
| `id` / `target` / `node` | 最近快照的无人机、目标及行为节点 |
| `candidates` / `eligible` | 最近快照中的候选条目数和可用条目数，条目不必等于独立敌人数 |

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
| `Unsupported…` / `Runtime signature mismatch` | 游戏版本/签名不匹配，停止；按布局迁移流程处理 |
| `candidate group bound` / `invalid cached score` 等 | 结构校验失败；不要简单增大上限或吞掉错误 |

停止后的清理可能继续重试而日志不再变动，不要仅靠最后一条消息推定旧内存已恢复。正常退出游戏会结束该进程中的全部临时修改；下一次启动前先解决停止原因。

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
