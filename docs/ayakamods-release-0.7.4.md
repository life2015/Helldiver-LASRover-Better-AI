# AyakaMods 发布准备：0.7.4

发布地址：https://ayakamods.com/mods/games/helldivers-2.119/add

标题：激光狗索敌优化 / Laser Rover Targeting Optimization

分类：Miscellaneous

版本：0.7.4

简介：让激光漫游车短暂攻击后频繁转火，优先邻近敌人，并提供 HUD / No HUD 版本。

上传材料：publication/ayakamods-0.7.4/，包含六个互斥安装ZIP、封面、说明和SHA256SUMS.txt。封面为AI生成的功能示意，不是游戏截图。最终提示词见[封面生成记录](ayakamods-cover-prompt.md)。

以下为页面文案草稿，尚未提交发布。

激光狗索敌优化 / Laser Rover Targeting Optimization
版本：0.7.4（实验版）

让激光护卫犬漫游车短暂攻击后更频繁地切换目标，减少持续盯着同一个敌人的时间，帮助将火焰持续伤害铺向更多敌人。

功能
• 普通转火：约0.4秒同步攻击状态后，尝试转向当前敌人附近的其他有效目标。
• 近处优先：当前敌人在漫游车15米外、圈内又有其他有效敌人时，优先转回15米内。
• 近期记忆：最多1个目标、1秒过期，尽量避免立即转回刚处理的目标。
• 未攻击重选：同一目标连续约1.5秒未进入同步攻击状态时，尝试选择离漫游车最近的其他目标。
• 同目标兜底：独立累计约1.5秒有效观察时间，短暂切换攻击/瞄准状态不会无限清零；成功提交请求、换目标或观察失效后重新计时。
• HUD / No HUD：带界面版在顶部居中显示索敌状态、Locked/Next目标ID及计数；无界面版保留相同索敌逻辑与文本日志。

只安装下面六个包中的一个
• v12：默认渠道，内置加载器。
• v14：内置官方v14加载器，适用于保留v14环境的玩家。
• v15：独立Addon，需要另外安装官方Bingus Shared Loader v15。
• 每个渠道各有HUD和No HUD变体；文件名已注明依赖。No HUD表示无界面，不是另一套索敌策略。
官方v15加载器：https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15

安装与更新
1. 正常退出游戏，禁用并移除旧版激光狗索敌优化，包括其他渠道与HUD变体。
2. 用Mod管理器导入所选ZIP并启用；先检查包内INSTALL.txt。
3. v12/v14需要让本包的启动桥在资源冲突中生效；v15需要单独安装并让官方v15加载器生效，不要残留旧Rover内置启动包。
4. 部署完成后直接从Steam启动，无需额外启动参数。
已有其他Mod时请核对加载顺序；内置旧加载器、自定义启动脚本或修改同一无人机的Mod不保证兼容。卸载时只移除自己安装的Rover文件，并保留其他Mod需要的加载器。

0.7.4更新
增加独立的同目标计时，修正合成测试中“攻击状态反复切换，转火计时一直清零”的问题。正常约0.4秒攻击转火保持优先。HUD兜底提示为“lock 1.5s - reselecting”。

效果与验证范围
计时依据是游戏攻击状态，不读取命中、伤害或点燃标记；不保证每次照射都点燃，也不保证原生一定接受转火请求。没有其他有效候选时不会强制转火。
127项Lua测试、5项部署测试及六包离线检查通过。盾虫卡锁反馈的实战效果仍需验证，不能将代码回归通过当作所有敌人、游戏版本或联机场景均已验证。
此前测试中出现过整机卡死/黑屏，根因尚未确认；No HUD和本次计时调整都不是已确认的崩溃修复。

反馈问题时，请提供包名、游戏版本、其他Mod列表、复现条件，以及本次运行的RoverFireSpread.log。日志位置：%LOCALAPPDATA%/RoverFireSpread.log。分享前请自行检查个人信息。

致谢
感谢CowboyBingus的SentryAimRetention、BingusSharedLoader、KnowYourConstellation等项目提供实现与研究参考。
https://github.com/CowboyBingus/SentryAimRetention
https://github.com/CowboyBingus/BingusSharedLoader
https://github.com/CowboyBingus/KnowYourConstellation

English summary
Encourages the laser Guard Dog Rover to switch between nearby eligible enemies after short attack windows. Includes a 15m nearby-threat preference, one-entry recent-target memory and a 1.5s same-target fallback. Install ONE package only: bundled v12/v14, or v15 Addon with the official v15 loader installed separately; each comes with HUD or No HUD. It does not detect ignition or damage. Experimental release; gameplay compatibility and stability remain under validation. The cover is an AI-generated feature illustration, not an in-game screenshot.
