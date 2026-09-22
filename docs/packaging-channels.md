# 多加载器版本与HUD变体

更新于2026-09-23；适用0.7.14。

从当前0.7.14构建起，运行`python scripts/package.py`会生成六个ZIP。文件名中的v12/v14/v15是Bingus加载器渠道，不是索敌算法版本。六包使用相同的当前索敌源码及参数；同一种HUD变体的编译本体在三个渠道逐字节复用。

| 渠道 | HUD包 | 无HUD包 | 加载方式 |
| --- | --- | --- | --- |
| v12（默认渠道） | 激光狗索敌优化-0.7.14-v12-内置加载器.zip | 激光狗索敌优化-0.7.14-v12-内置加载器-No-HUD.zip | 内置固定v12启动桥 |
| v14 | 激光狗索敌优化-0.7.14-v14-内置加载器.zip | 激光狗索敌优化-0.7.14-v14-内置加载器-No-HUD.zip | 内置完整官方v14，然后启动Rover |
| v15 Addon | 激光狗索敌优化-0.7.14-v15-需要额外安装加载器.zip | 激光狗索敌优化-0.7.14-v15-需要额外安装加载器-No-HUD.zip | 不包含加载器，另装官方v15，由其自动发现入口 |

文件命名统一为`激光狗索敌优化-版本-v12/v14/v15-加载器说明[-No-HUD].zip`。v12/v14标注“内置加载器”，v15标注“需要额外安装加载器”；管理器显示名同步标注。历史旧名称ZIP可以保留用于回退，本次分发以`build/package-matrix.json`列出的包为准。使用`python scripts/package.py --channels v14 v15`只生成四个发行包，v12中间包保存在build/internal-base。

v12/v14均无需额外安装同版独立加载器；v15必须另装官方加载器。其他Mod依赖v14与内置v14是两种情况，兼容边界见[v15共存说明](shared-loader-v15.md)。

**六个Rover包只能选一个。**HUD方便测试和观察；No HUD不编入hud.lua，不创建界面、不读取字体或绘制文字，保留相同转火功能和文本日志。No HUD不是已确认的整机故障修复。

## 安装和迁移

先正常退出游戏，禁用/移除旧Rover包并清理其旧部署，再导入所选ZIP。不要保留旧启动桥后叠加v15 Addon。所有包保留同一Mod GUID，管理器可能将其视为同一Mod的替换。

- **v12/v14内置渠道：Rover包必须赢得Wwise启动资源覆盖。**Arsenal默认排序把Rover放在相关启动包之后；首项优先模式放在前面，以实际覆盖关系为准。黄色资源重叠警告仍可能存在。独立加载器覆盖Rover桥时，Rover可能没有启动入口；旧加载器桥覆盖新版时，其他Mod可能失去新版功能。
- **v15 Addon：另装[官方Bingus Shared Loader v15](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15)。**只有此渠道不包含Wwise；所有Rover渠道均不替换boot。让官方加载器赢得启动资源覆盖，不要沿用v14的“让Rover桥获胜”规则。固定官方v15与本Addon没有共同Lua资源，二者patch编号前后两种顺序均经过离线自动发现测试。其他Mod的覆盖仍需单独检查。

管理器按manifest处理：v12/v14数据位于ZIP的`data/`；v15位于`Addon/`。手动部署时仅复制所选目录中的三个文件到游戏`data`，使用统一且未占用的patch编号，并记录文件归属。不要覆盖其他Mod，也不要混用管理器与手动部署。

本地`deploy.py install [--variant no-hud]`目前仍只选择默认v12报告。v14/v15通过管理器或按上面的手动流程安装；不能把渠道报告拷进默认报告来绕过名称/目录校验。打包不会更改本机安装。

## 日志确认

本体日志仍为`%LOCALAPPDATA%/RoverFireSpread.log`，本体build_id为`experimental-0.7.14`。No HUD成功运行后应为`hud_enabled=false`、`hud_status=disabled`；HUD版为hud_enabled=true。核对本次PID和文件更新时间，加载成功不等于已经验证实际转火或稳定性。

v14的`RoverFireSpread-startup.log`标明`experimental-0.7.14-v14`（No HUD再带`-No-HUD`）和`shared_loader_release=v14`。v15 Addon不会更新此旧启动日志，应看官方日志`%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log`中的发现记录、`mods/retrox/rover_fire_spread: loaded`，再核对Rover本体状态。

卸载时退出游戏，只移除所选Rover包；保留其他Mod需要的独立加载器。回退旧内置渠道前先移除当前Addon，并重新核对所用加载器和启动优先级。

## 构建输入与输出

三个固定输入放在build/；构建前校验全部ZIP的SHA-256，不会静默改用另一版：

| 输入 | SHA-256 |
| --- | --- |
| Bingus-Shared-Loader-v12.zip | 4A95D7A056F0A9E01842420883059A380374092145B5D9EC807C14C8CA351568 |
| Bingus-Shared-Loader-v14.zip | 7FA8AF328AC2C98F68DD5946D94444315DD61B2B3504B0788301700CC9C023B2 |
| Bingus-Shared-Loader-v15.zip | FA766634DFF3F7D1FD9C5C0EBA72B1FBABAD8721710491CAAA4E12A598028CDA |

运行`package.py`编译当前HUD/No HUD两个本体，然后依次包装v14、v15，每个渠道复用对应本体。`package_v14.py`和`package_v15.py`也可独立运行，各生成两个变体，但要求已存在同版本、哈希有效的当前默认包；不再固定复用旧0.7.1。

默认报告仍为`build/experimental-package-report[ -no-hud ].json`（实际文件名不含空格）；渠道报告为`build/v14-compat/{hud,no-hud}/package-report.json`、`build/v15-addon/{hud,no-hud}/package-report.json`。成功完成六包后输出`build/package-matrix.json`，列出本次版本及六包名称/哈希；每包内部另带provenance.json。

构建验证包含：编译入口实际HUD配置、v14音频回调/模块名单保留和失败隔离、v15真实发布字节码在临时目录发现入口（加载器与Addon两种编号顺序、缺失实现、无Addon）、本体字节不变、v15无启动资源交集，以及全部归档往返/ZIP完整性。这些离线检查不等于实机共存或整机稳定性验证。

0.7.14包含新旧两个显式游戏布局，运行时依模块哈希对选择并检查关键代码。该版本的更新兼容证据见[迁移记录](game-update-25327279.md)。
