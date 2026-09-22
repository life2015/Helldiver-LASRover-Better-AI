# 游戏内运行状态面板

0.7.14新增[可选标记主动转火](marked-priority.md)：不必等待普通计时，仍保留原生状态、Recent和0.5秒标记请求冷却。黄色暂不可选处理不变。

当前0.7.13的标记评分宽限为1.5秒，标记存在与可攻击资格已分离；最新规则及HUD原因见[标记宽限说明](marked-grace.md)。下文历史版本条目按当时行为保留。

当前版本0.7.12；更新于2026-09-23。v12/v14/v15的HUD本体相同，区别在启动入口。

0.7.11：当前有效标记目标的第二行显示`Marked: ID | attack 2.0/4s`，表示已观察到的连续同步攻击时间和4秒窗口；未进入攻击状态时显示`no attack 2.0/3s`。活动重选请求显示实际阈值：标记目标为`no attack 3s`或`lock 5s`，普通目标仍为1.5秒。它们不是命中/点燃计时。下文0.7.10的`current lock`文字已由进度提示取代。

0.7.10：有效本地敌人标记在等待转火期间也于第一行显示绿色`ROVER | MARKED`，使用与索敌干预相同的标题字号与绿色。第二行显示`Marked: ID | waiting for rotation`；同步锁定该目标时改为`current lock`，不代表命中或点燃。活动请求优先显示原有`MOD: MARKED`、`MOD: NEAREST`或`MOD: NATIVE PICK`，避免掩盖超时重选。标记取消、过期、候选失效、快照丢失或停止后，不保留实时MARKED状态；刚结束的实际请求仍可按原有规则显示0.5秒`MOD: MARKED (last)`历史提示。没有改变索敌逻辑、面板位置或五行绘制数量。

0.7.2提供独立No HUD包：完全省略HUD实现，不创建GUI、不读取字体或调用绘制接口；转火和文本日志照常。测试完成后可选择此包；先退出游戏、移除旧变体再安装。以下界面说明仅适用于HUD包。No HUD成功初始化后日志为`hud_enabled=false`、`hud_status=disabled`。

HUD版默认启用屏幕顶部居中的五行小面板，不需要另开外部悬浮窗。面板使用英文短标签和颜色，约每0.1秒更新一次。当前已通过模拟GUI与生命周期测试，新位置及其他HUD兼容仍待实机验证。

| 第一行 | 含义 |
| --- | --- |
| 绿色 `ROVER \| MARKED` | 已识别当前有效的本地敌人标记，等待正常轮换或当前已锁定它；不表示正在干预 |
| 绿色 `ROVER \| MOD: MARKED` | 标记优先的转火请求正在生效 |
| 绿色 `ROVER \| MOD: NEAREST` | 最近目标策略的转火请求正在生效，临时筛选尚未恢复 |
| 黄色 `ROVER \| MOD: NATIVE PICK` | Mod仍在筛选策略允许的候选（超时重选忽略Recent），但距离不可用，由原生AI在允许的候选中选择 |
| 灰色 `ROVER \| NATIVE` | 此刻没有正在生效的Mod请求；第二行说明原因，Mod仍可能正常运行 |
| 灰色 `ROVER \| WAITING` | 等待任务、本地激光狗或有效快照 |
| 红色 `ROVER \| STOPPED` | 已初始化的控制器因错误停止；如清理尚未完成，显示`restoration pending` |

0.7.1中绿/黄标题在请求恢复结束后额外显示0.5秒，带`(last)`后缀，第二行变为`Request ended - native control`。没有后缀时仍表示活动请求。新请求立即覆盖旧提示；停止、快照缺失、场景/无人机身份变化时不保留旧颜色。保留期从控制器确认恢复完成起算，避免漏掉两次HUD刷新之间的短请求；不延长游戏内临时修改。时长参数为`hud.lua`的`status_hold_seconds=0.5`。

`NATIVE`下的`attack window`表示等待约0.4秒攻击窗口；`no other target`表示没有其他有效敌人；`tracking / aiming`表示正在搜敌/瞄准或目标尚未同步；`data changed; retry`表示写入前数据变化而放弃本次请求。

原生AI始终负责实际攻击和选敌执行。这个面板表示Mod有没有施加临时筛选，不能解读成游戏切换到了另一套完整AI。

0.7的第二行/Last行显示距离依据：`adjacent target`按本次离开的目标到候选的距离；`near Rover (20m)`表示从20米外优先转回圈内；`nearest Rover`表示目标坐标降级或超时解卡时按距漫游车排序。第一行的NEAREST统指当前距离策略，不一定是离漫游车最近。

第三行`Last`只在成功提交请求后的2秒内显示策略与距今秒数。它是历史事件，独立于第一行结束后0.5秒的颜色保留；计划未提交、写入失败、仅诊断都不产生这条成功请求记录。

第四行`Requests / Changes / Recent`分别表示本次进程累计请求数、请求期间观察到的目标变化数、近期历史项数（0.6最多1个、1秒过期）。Recent包含达到攻击窗口的目标及锁定超时后放弃的目标。这些不是成功点燃次数，`Changes`也不严格证明变化由请求引起。

0.7.6显示`no attack; waiting 1.5s`表示正在等待攻击状态；触发后显示`no attack 1.5s - reselecting`，Last行包含`timeout`。判断依据是节点6/7及目标同步状态，不能据此证明激光真正发射/命中。超时请求忽略上一条Recent，从当前目标以外选最近有效目标；无距离时仍由原生AI选。

第五行例如`Locked: 123 | Next: 456`。`Locked`仅在Behavior目标与Targeting目标一致、同步标志有效时显示当前目标ID；未同步、无目标、快照不可用或停止后显示`--`。`Next`在活动请求期间显示目标ID，结束后保留到请求提交满2秒并标注`(last)`，避免0.1秒HUD刷新漏掉短暂请求。距离降级对应`native`或`native (last)`。Next保留与标题额外0.5秒提示独立计时，均不延长游戏内干预；Last行提供距今时间。场景/无人机身份变化、缺失快照或停止时隐藏历史请求。不能把Next当作已锁定；数字为运行时实体ID，可能复用，不是敌人类型或跨局永久身份。

## 面板没有出现时

检查`%LOCALAPPDATA%/RoverFireSpread.log`的时间、`build_id=experimental-0.7.6`、当前PID及`hud_status`：

- `visible`：绘制调用完成，但仍需肉眼确认没有被其他界面遮住。
- `waiting_for_ui`：尚无可用UI world，稍后自动重试。
- `unavailable`：查看`hud_error`，失败后约2秒重试；不停止索敌控制器。
- `unverified_font_layout`：game.dll哈希不匹配字体布局基线。仅HUD隐藏；0.4.1放宽的索敌兼容性尝试仍保留。
- `initialization_failed`：初始化失败，未安装更新回调，不能在游戏内绘制红色状态。查看主`status`。
- `disabled` / `closed`：构建时关闭HUD / 游戏关闭回调已清理HUD。

**没有面板不能证明正在使用原生行为。** 模块根本没加载时无法自行显示错误；旧日志也不能用于判断当前进程。

## 实现与维护

`src/hud.lua`只读取控制器状态，绘图在原始游戏update和控制器检查之后执行，异常独立捕获。切换UI world时重建自己的GUI；只销毁仍存在world中的自有GUI，不缓存跨帧字体/向量临时对象。面板始终最多一个背景和五条文本，内容变化时更新，不逐帧追加。

`controller.lua`将`active_request / active_ranking`与`last_request_*`分开；恢复时立即清除active标记，每次完整采样清除旧计划字段。单目标、窗口未满、快照缺失均有独立`decision`。面板只显示最近一次轮询状态，显示延迟约为绘图间隔，不是逐机器指令跟踪。

字体读取与GUI材质配置参考CowboyBingus/KnowYourConstellation提交`b3101485354d5d79596399ad9916226e351d54d2`中的`src/presentation.lua`和`src/panel.lua`，该项目使用相同game.dll基线。读取当前语言的body字体、normal材质和图集；正文使用ASCII标签避免跨语言字形依赖。布局：game.dll+0x2a750d8为字体hash，+0x2a75d58为atlas hash，+0x2ac7058为材质表指针，表+24为材质hash。检查非零、完整读取和前后值一致；未知game.dll不使用这些额外偏移。

要关闭面板，直接选择`package.py`生成的`-No-HUD.zip`，默认v12渠道也可用`deploy.py install --variant no-hud`安装；切换前需退出游戏并卸载旧包。位置/尺寸在`hud.lua`的`x,y,w,h`；HUD横向居中，距顶边24个参考像素，宽410、高129（参考1920×1080），按分辨率缩放。暂未添加快捷键、INI或拖动功能。

## 0.7.6同目标占用兜底

活动请求显示`lock 1.5s - reselecting`，Last行标注`max lock /`；连续未攻击超时仍显示`no attack 1.5s - reselecting`及`timeout /`。两者都按距漫游车最近的其他有效候选选择；No HUD版通过`active_reason`/`last_request_reason=lock_max_duration`核对。提示不表示已命中或原生一定完成转火。

0.7.7新增`ROVER | MOD: MARKED`，表示标记优先请求正在生效；结束后额外0.5秒显示`(last)`，Next仍保留2秒。`Selecting/Last: your marked enemy`说明选择依据，不表示正在命中。
