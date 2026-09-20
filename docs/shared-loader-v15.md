# v15独立模块包与迁移

适用版本：0.7.4；更新于2026-09-19。名称标注“需要额外安装加载器”，HUD/No HUD均不内置加载器，也不提供Wwise或boot资源。单独安装[官方Bingus Shared Loader v15](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15)，由其自动发现Rover。六包名称见[多渠道说明](packaging-channels.md)。

## 从旧版更新

1. 正常退出游戏，保存旧包及管理器配置。
2. 移除所有旧Rover包，包括内置v12/v14版本，部署清理其启动桥。
3. 用官方v15替换独立v14或更早加载器，只启用一个独立官方加载器版本。
4. 导入所选v15 Rover包并启用。让官方加载器获得启动资源优先级：Arsenal默认放最后，首项优先模式放最前，以实际资源覆盖为准。
5. 重新部署，从Steam启动并检查两份本次日志。

官方v15与本Addon之间没有共同Lua资源，两种归档编号先后顺序均通过离线测试。它们使用相同归档前缀并不等于资源冲突；手动部署仍必须选择不同的空编号，不能覆盖文件。ZIP中使用`Addon`目录，文件最终放入游戏`data`，详见[玩家指南](player-guide.zh-CN.md)。

## 与其他v14 Mod的关系

普通模块只是依赖v14时，通常可以由v15继续加载：固定v15保留API 1及原有模块名单，并增加声明入口发现。但这只涉及加载机制，不保证具体Mod的游戏内行为兼容。

如果另一包内置v14或自定义启动桥，它可能覆盖官方v15；也可能先创建`CowboyBingusModLoader`，导致v15协调器提前返回。此时Rover Addon可能未被发现。反过来，让v15覆盖对方自定义入口也可能使对方模块失去启动机会，因此不能声称“把v15放最后就一定全部兼容”。需要检查具体资源和入口。其他Mod也修改激光狗时另有行为层面的冲突可能。

只装本Addon加旧v14通常没有发现入口。`src/addon_entry.lua`要求加载器`api >= 1`且内部`version >= 16`；内部16对应发布标签v15，不是要求额外的发布版v16。源码允许较新的版本尝试，当前仅固定v15输入完成离线验证。

## 日志确认

官方日志：`%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log`。检查本次发现记录及`mods/retrox/rover_fire_spread: loaded`。

本体日志：`%LOCALAPPDATA%/RoverFireSpread.log`，build为`experimental-0.7.4`。核对当前PID、时间、status和持续增加的samples。loaded只表示入口require返回；本体可能在初始化检查中受控停止，不能据此当作转火已运行。No HUD成功运行显示`hud_enabled=false`、`hud_status=disabled`。

本包不执行Rover旧Wwise桥，不会更新`RoverFireSpread-startup.log`。磁盘旧文件不能作为此包加载证据。

## 构建和验证

`src/addon_entry.lua`以纯文本保存到资源`mods/retrox/rover_fire_spread`，第一行必须保留`-- HD2-Addon: mods/retrox/rover_fire_spread`。它require资源`mods/retrox/rover_fire_spread_impl`；后者逐字节复用当前对应HUD变体的编译本体。不要把声明入口编译成字节码，否则扫描看不到注释。

`scripts/package_v15.py`校验当前基础包及固定官方v15输入，官方加载器仅用于离线验证，不打进成品。报告为`build/v15-addon/hud/package-report.json`和`build/v15-addon/no-hud/package-report.json`。完整构建运行`package.py`；单独脚本要求匹配的基础包和报告，生成两个变体。

测试使用官方v15字节码及真实Win32枚举扫描临时归档，覆盖加载器高编号、Addon高编号、实现缺失、无Addon四种情况；资源查询及游戏回调为模拟。另检查纯文本声明、本体字节一致、无启动资源交集、归档和ZIP完整性。尚未因此证明实机共存或整机稳定性。

固定输入哈希见[多渠道说明](packaging-channels.md)。最初0.7.1产物证据保留在[历史v15验证](v15-validation.md)。

## 卸载和回退

退出游戏，移除Rover Addon并重新部署，保留其他Mod需要的官方加载器。旧内置渠道不可直接叠加作回退；先移除Addon，再按旧包要求重建启动覆盖关系。临时排除Rover问题只需停用Addon，无需降级共享加载器。
