中文 / English — English version below.

开源项目 / Open source: [Helldiver-LASRover-Better-AI](https://github.com/life2015/Helldiver-LASRover-Better-AI)

# 激光狗索敌优化 · 0.7.8（实验版）

[演示视频 / Gameplay demo（Bilibili）](https://www.bilibili.com/video/BV1mxe66jEHZ/)

让激光护卫犬漫游车短暂攻击后更频繁地切换目标，减少持续盯着同一个敌人的时间，帮助将火焰持续伤害铺向更多敌人。现在也支持优先选择你标记的有效敌人。

演示视频供了解转火效果，不代表已展示本次新增的全部功能。

## 主要功能

- **短时照射、相邻转火：** 约 0.4 秒同步攻击状态后，尝试转向当前敌人附近的其他有效目标，减少远距离切换目标的开销。
- **自己的标记优先：** 下一次正常转火时，优先选择你标记的、仍在游戏原生有效候选中的敌人。保留近期目标避让，照射后仍会正常转火，不会一直强制攻击到目标死亡。取消、过期或不再有效的标记不再提供优先级；地面标点不会被当作敌人。
- **30 米近处优先：** 当前敌人离漫游车超过 30 米，且 30 米内有其他有效敌人时，优先转回圈内。当前目标已在圈内时，继续按相邻目标选择。30 米是优先级阈值，不是索敌距离上限，也不会扩大游戏原生射程。
- **近期记忆：** 最多记录 1 个目标，1 秒过期，尽量避免立即转回刚处理的目标。标记优先也遵守这项避让。
- **未攻击重选：** 同一目标连续约 1.5 秒未进入同步攻击状态时，尝试选择离漫游车最近的其他有效目标。
- **同目标兜底：** 独立累计约 1.5 秒同目标有效观察时间，避免攻击和瞄准状态反复切换导致计时不断清零。超时重选仍按最近其他目标处理，不被标记优先覆盖。
- **HUD / No HUD：** HUD 版在顶部居中显示索敌状态、Locked/Next 目标 ID 和计数；标记优先请求显示 `MOD: MARKED`。No HUD 版保留相同索敌逻辑与文本日志，不显示面板。

## 0.7.8 更新

本轮更新适配游戏 **build 25327279**，加入玩家标记优先，并将近处优先阈值从 15 米调整到 30 米。

0.7.8 修复了部分有效敌人标记被错误过滤的问题：游戏的标记显示类型不能直接当作敌我判定，现继续结合漫游车原生有效敌人候选进行筛选。

标记优先目前仅在已适配的 **build 25327279** 布局中启用。关键代码签名及运行时身份检查仍保留；标记读取失败时回到普通索敌，核心布局校验失败时停止 Mod 干预。

## 下载选择

本次提供 **4 个互斥安装包**：

| 渠道 | 加载器 | 可选版本 |
| --- | --- | --- |
| **v14** | 内置官方 v14 加载器 | HUD / No HUD |
| **v15** | 需要另装[官方 Bingus Shared Loader v15](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15) | HUD / No HUD |

**只安装一个 Rover 包。** 建议先用 HUD 确认功能生效，再按需要换用 No HUD。文件名已注明加载器依赖；v14/v15 是加载器渠道，0.7.8 是本 Mod 版本。本次下载不包含 v12。

## 安装与更新

1. 正常退出游戏，禁用并移除旧版激光狗索敌优化，包括其他渠道与 HUD 变体。
2. 用 Mod 管理器导入所选 ZIP 并启用，先阅读包内 `INSTALL.txt`。
3. **v14：** 让本包的启动桥在相关启动资源冲突中生效。**v15：** 单独安装官方 v15 加载器，并确保其启动资源生效，不要残留旧 Rover 内置启动包。
4. 部署完成后，直接从 Steam 正常启动，无需额外启动参数。

已有其他 Mod 时请核对加载顺序。内置旧加载器、自定义启动脚本或修改同一无人机的 Mod 可能产生冲突。卸载时只移除自己安装的 Rover 文件，并保留其他 Mod 需要的加载器。

## 如何观察标记优先

使用 HUD 版，让激光狗附近有多个有效敌人，标记其中一个尚未被锁定的敌人，观察 `MOD: MARKED`、`Selecting: your marked enemy` 和 `Next` ID。

标记不会立即打断当前照射，而是在正常转火时参与选择。若标记敌人刚被处理、已被当前锁定、不在原生有效候选中，或正在执行超时解锁，不一定出现标记优先提示。`Next (last)` 表示最近请求的目标，不表示当前仍锁定它。

## 效果与验证范围

Mod 根据游戏攻击状态计时，不读取命中、伤害或点燃状态，也没有额外的掩体射线检测。不保证每次照射都点燃，或原生 AI 一定接受每次转火请求。没有其他有效候选时不会强制转火。

**174 项 Lua 测试及本次 4 个发行包的离线入口与归档检查通过。** 实际采样回放确认，0.7.8 能识别此前被错误过滤的标记目标；修复后的实际标记优先效果仍待进一步实战验证。这不代表所有敌人、联机环境或长期稳定性均已验证。

## 问题反馈

请提供完整包名、游戏版本、其他 Mod 列表、复现条件，以及本次运行的 `RoverFireSpread.log`。

日志位置：`%LOCALAPPDATA%/RoverFireSpread.log`

反馈标记问题时，也请说明是否看到 `MOD: MARKED`，以及你标记的是敌人还是地面。分享日志前请检查个人信息。

封面为 AI 生成的功能示意图，不是游戏实战截图。

---

# Laser Rover Targeting Optimization · 0.7.8 (experimental)

[Watch the gameplay demo on Bilibili](https://www.bilibili.com/video/BV1mxe66jEHZ/)

Encourages the laser Guard Dog Rover to switch targets after short attack windows, reducing the time spent focusing on one enemy and helping spread fire damage over time across more enemies. It now also supports priority for your marked eligible enemies.

The demo illustrates target switching; it does not necessarily show every feature added in this update.

## Features

- **Short attack windows and adjacent targets:** After roughly 0.4 seconds in a synchronized attack state, the mod requests another eligible enemy near the current target, helping reduce large target-to-target transitions.
- **Your marked enemy first:** At the next normal rotation, your marked enemy receives priority if it remains an eligible native target. Recent-target avoidance still applies, and the Rover continues rotating after a short attack window. This does not force sustained fire until death. Canceled, expired or invalid markers no longer grant priority; ground pings are not treated as enemies.
- **30 m nearby-target preference:** If the current enemy is more than 30 metres from the Rover and eligible alternatives exist within 30 metres, the mod prioritizes that nearby group. When the current target is already inside the radius, adjacent-target selection continues. This is a priority threshold, not a targeting distance limit or a range extension.
- **Recent-target memory:** Remembers at most one target for one second to help avoid immediately returning to it. Marked-target priority also respects this avoidance.
- **No-attack timeout:** After roughly 1.5 continuous seconds without entering a synchronized attack state on the same target, the mod requests the nearest eligible alternative to the Rover.
- **Same-target fallback:** A separate timer accumulates roughly 1.5 seconds of valid observations of the same target, preventing repeated changes between attacking and aiming from resetting progress indefinitely. Timeout requests still choose the nearest alternative and are not overridden by marker priority.
- **HUD / No HUD:** The HUD shows targeting status, Locked/Next target IDs and counters at the top centre of the screen. Marked-target requests display `MOD: MARKED`. No HUD retains the same targeting logic and text logs without the overlay.

## What's new in 0.7.8

This update series adds compatibility with **game build 25327279**, introduces player-marked target priority, and increases the nearby-target preference threshold from 15 m to 30 m.

Version 0.7.8 fixes some valid enemy markers being incorrectly rejected. A marker's display category is not sufficient to determine hostility; selection continues to require an eligible native enemy candidate.

Marked-target priority is currently enabled only for the adapted **build 25327279** layout. Code signatures and runtime identity checks remain in place. Marker-read failures fall back to normal targeting; failed core layout checks stop mod intervention.

## Choose a download

This release offers **four mutually exclusive packages**:

| Channel | Loader requirement | Variants |
| --- | --- | --- |
| **v14** | Bundles the official v14 loader | HUD / No HUD |
| **v15** | Requires the [official Bingus Shared Loader v15](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15), installed separately | HUD / No HUD |

**Install only one Rover package.** Start with HUD to confirm operation, then switch to No HUD if preferred. Dependencies are indicated in the filenames. v14/v15 identify loader channels; 0.7.8 is the mod version. This download set does not include v12.

## Installation and updates

1. Exit the game normally. Disable and remove older Rover Targeting Optimization packages, including other loader channels and HUD variants.
2. Import and enable your chosen ZIP in your mod manager. Read the included `INSTALL.txt` first.
3. **v14:** Ensure this package's startup bridge takes precedence in relevant startup-resource conflicts. **v15:** Install the official v15 loader separately and ensure its startup resources take precedence. Remove older Rover packages that bundle a startup bridge.
4. Deploy your mods, then launch normally through Steam. No additional launch options are needed.

Check load order when using other mods. Packages with older bundled loaders, custom startup scripts or changes to the same drone may conflict. When uninstalling, remove only the Rover files you installed and keep any loader required by other mods.

## Testing marked-target priority

With the HUD version installed, let the Rover encounter multiple eligible enemies and mark one it is not currently targeting. Watch for `MOD: MARKED`, `Selecting: your marked enemy` and the `Next` ID.

A marker does not immediately interrupt the current attack window; it affects selection at a normal rotation. The indicator may not appear if the marked enemy was recently handled, is already the current target, is outside the native eligible candidate list, or the Rover is executing a timeout request. `Next (last)` identifies a recent request, not a confirmed current lock.

## Behavior and validation

Timing is based on the game's attack state. The mod does not read hit, damage or burning-status flags, and adds no separate cover raycast. It cannot guarantee ignition with each burst or that the native AI will accept every retargeting request. It does not force a switch when no other eligible target is available.

**174 Lua tests and offline startup/archive checks for all four release packages passed.** Replaying captured data confirms that 0.7.8 recognizes previously rejected marker targets. The fix's actual targeting behavior still requires further gameplay validation; this does not establish coverage of every enemy, multiplayer environment or long-session stability scenario.

## Reporting issues

Please include the full package name, game version, other installed mods, reproduction steps and `RoverFireSpread.log` from the affected run.

Log location: `%LOCALAPPDATA%/RoverFireSpread.log`

For marker issues, also mention whether `MOD: MARKED` appeared and whether you marked an enemy or the ground. Check logs for personal information before sharing.

The cover is an AI-generated feature illustration, not an in-game screenshot.

---

## 致谢 / Credits

感谢 CowboyBingus 的以下项目提供实现与研究参考。Thanks to CowboyBingus for the following implementation and research references:

- [SentryAimRetention](https://github.com/CowboyBingus/SentryAimRetention)
- [BingusSharedLoader](https://github.com/CowboyBingus/BingusSharedLoader)
- [KnowYourConstellation](https://github.com/CowboyBingus/KnowYourConstellation)
