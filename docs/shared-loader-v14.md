# v14内置加载器包

适用版本：0.7.6；更新于2026-09-19。HUD和No HUD均内置完整的固定官方Bingus Shared Loader v14，再直接执行对应的Rover编译本体。无需额外安装独立v14。完整文件名见[六包清单](packaging-channels.md)。

## 为什么仍可能提示冲突

本包与独立加载器均提供`core/wwise/lua/wwise_flow_callbacks`，游戏只使用最终获胜的一份，不会合并。独立v14的固定模块名单没有Rover；它覆盖本包后，Rover可能没有启动入口。v12桥覆盖v14则可能使其他Mod失去新版加载功能。

因此本包必须赢得Wwise资源覆盖。Arsenal默认优先级放在相关启动包之后，首项优先模式放在之前；以实际覆盖关系为准。管理器黄色资源重叠提示本身不证明崩溃。自定义boot或另一套内置启动脚本仍需逐包检查。

## 安装和迁移

正常退出游戏，保留旧ZIP，移除旧Rover后导入所选v14包并部署。HUD/No HUD只能选一个。可以保留独立v14条目供停用Rover后使用，但启用本包时由本包的桥生效。手动安装使用ZIP的`data`目录，具体步骤见[玩家指南](player-guide.zh-CN.md)。

若其他Mod需要v15自动发现，应改用官方v15加[v15 Rover模块包](shared-loader-v15.md)，不能让内置v14桥压过官方v15，也不要同时启用两个Rover渠道。

## 日志与离线验证

`%LOCALAPPDATA%/RoverFireSpread-startup.log`应有`experimental-0.7.6-v14`（No HUD加`-No-HUD`）、`shared_loader_release=v14`、`shared_loader_returned`及Rover状态。本体`RoverFireSpread.log`仍为`experimental-0.7.6`。加载器日志位于`%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log`；核对当前PID/时间并检查其他Mod自己的功能。

`scripts/package_v14.py`从当前已验证的v12 HUD/No HUD包提取对应本体，逐字节复用，替换启动桥。它校验固定v14发布输入及原始回调资源，执行真实字节码的音频回调、模块名单、失败隔离、重复初始化和实际Rover入口测试。其他游戏模块是模拟依赖，尚未证明任意Mod的实机共存。

报告位于`build/v14-compat/hud/package-report.json`及`build/v14-compat/no-hud/package-report.json`。单独执行脚本会生成两个变体，但前提是当前基础包/报告存在且哈希匹配；通常直接运行`package.py`生成六包。

固定来源、输入哈希和报告索引见[多渠道构建](packaging-channels.md)。最初0.7.1兼容测试的包哈希和反馈保留在[历史验证](loader-compat-validation.md)，不能把旧包当作当前发行包。

## 卸载

退出游戏，通过原安装方式移除Rover；保留或恢复其他Mod需要的独立加载器。切换到v15时先移除本包的启动桥，再让官方v15生效。此渠道不是整机故障修复。
