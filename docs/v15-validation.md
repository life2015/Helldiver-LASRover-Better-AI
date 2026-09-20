# 历史：0.7.1官方v15模块包验证

归档说明（2026-09-19更新）：以下保留最初0.7.1实验的包身份与当时结论，不作为当前安装流程。当前0.7.2六包已纳入一键构建，见[多渠道说明](packaging-channels.md)及[当前验证](validation.md)。文中的“下一步”是当时计划，实机共存仍无新增确认。

官方发布v15（GitHub记录2026-09-18T22:22:13Z）已包含声明入口自动发现。[发布记录](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15)、[固定版本源码](https://github.com/CowboyBingus/BingusSharedLoader/blob/v15/src/shared_loader.lua)。本包无需此前issue #5设想的独立适配器，也不再内置固定Bingus版本。

产物`Rover-Fire-Spread-Addon-0.7.1-v15.zip`，SHA-256：`BAD3445B156F94AC8A518473113E998A0556C6B847EE7EFC8217F7026083BE8B`。

- 原0.7.1 Rover编译资源完整复用，移至implementation资源；原公开资源名改为纯文本声明入口。
- 成品只含两个Rover Lua资源；与官方v15资源集合无交集，未包含Wwise或boot替换。
- 真实官方v15字节码在独立进程扫描临时部署目录，真实Win32枚举读取实际生成归档：加载器编号10/Addon编号2和相反顺序均自动发现恰好一个入口，并经require到达Rover初始化。
- 实现资源不可用时记录加载失败；没有Addon归档时不启动Rover；重复执行协调器不重新扫描或重复require。
- 测试进程没有game.dll，Rover初始化受控停止，模拟update的参数/返回保持。不能把“入口到达”当作“控制器实机运行成功”。
- 成品声明、实现字节、资源边界、归档往返和ZIP CRC检查通过；核心没有修改，未重复宣称118项旧本体测试验证了新引擎加载路径。

未改变本机当前0.7.1安装、默认package report或部署记录。下一步需要装入官方v15和独立Addon、去掉旧Wwise桥，观察官方日志的发现/loaded状态、Rover本次进程日志和实际HUD/转火。其他Mod的实机共存及此前整机故障仍是独立待验证项。
