# 部署、启动、升级与回退

适用版本：0.7.7；更新于2026-09-22。玩家直接阅读[玩家中文说明](player-guide.zh-CN.md)；本页补充本地部署脚本和维护者验收步骤。

## 本机最新安装

2026-09-22 22:36，0.7.7 v15 HUD已部署到本机。包SHA-256：`D6A7E7634B369541962D0792F77A76107CEC7AAFE1AADCAAE4F8E9CB7AA6F3C8`。自有patch_3及sidecar读回校验通过，其余14个patch相关文件不变。旧版备份在`build/pre-deploy-0.7.7-20260922-223649/`。新进程标记优先尚待实机验收。

实际归档资源核对：patch_4是官方v15加载器（SHA-256 8312B061...，与固定官方ZIP内容一致），patch_5是EATAirburst（当前0.2.3、D10C2FE1...）；旧排查记录对这两个用途曾标注颠倒。本次没有改动二者，也没有额外复制加载器。

本机当前渠道为v15；下文deploy.py install仅适用于v12，不能用来覆盖本机v15模块。此次依据现有部署记录及哈希执行局部更新，独立加载器沿用已安装版本。

## 先选加载器渠道和HUD变体

当前有六个互斥安装包，完整名称见[多渠道打包与安装](packaging-channels.md)。同一游戏安装只启用一个Rover包：

| 渠道 | 加载器依赖 | 启动资源应由谁生效 |
| --- | --- | --- |
| v12 内置加载器 | 本包带固定v12，无需额外安装它 | Rover的Wwise启动桥 |
| v14 内置加载器 | 本包带完整官方v14，无需额外安装它 | Rover的Wwise启动桥 |
| v15 需要额外安装加载器 | 单独安装官方Bingus Shared Loader v15 | 官方加载器；Rover自身没有Wwise/boot资源 |

每个渠道都有HUD版和`-No-HUD.zip`版。No HUD不编入界面模块，仍保留索敌和文本日志。它不是已确认的整机故障修复。

Mod管理器导入所选ZIP、启用并部署。v12/v14要让Rover桥赢得Wwise资源覆盖；v15让官方加载器赢得启动资源覆盖。Arsenal默认优先级中获胜包放最后，首项优先模式则放最前；以实际资源覆盖结果为准。其他Mod内置旧加载器或自定义boot时，应检查其启动链，不能用统一排序保证所有组合兼容。详见[v14说明](shared-loader-v14.md)与[v15说明](shared-loader-v15.md)。

同一安装采用管理器、本地脚本或手动复制中的一种管理方式。混用会让文件编号与卸载记录失去对应关系。手动步骤见[玩家指南](player-guide.zh-CN.md)。

## 本地脚本仅安装v12

在项目根目录，先按[开发文档](development.md)配置`$pythonExe`及`HD2_GAME_ROOT`。构建成功、正常退出游戏后，选择下面一条安装命令：

```powershell
# HUD版
& $pythonExe scripts/deploy.py install

# 或：No HUD版
& $pythonExe scripts/deploy.py install --variant no-hud
```

每次检查退出码，非零时先检查错误和`build/deployment.json`。已有未移除的安装记录会阻止叠加第二份；上述两条不能连续执行来安装两个变体。

默认读取`build/experimental-package-report.json`，No HUD读取`build/experimental-package-report-no-hud.json`。脚本接受当前带`-v12-内置加载器`的名称，并保留历史中文/英文包名兼容。它不提供v14/v15渠道参数，也不替玩家安装独立加载器；不要把渠道报告复制到默认报告来绕过校验。

脚本依次确认游戏已关闭、核验ZIP哈希、读取游戏哈希、选择同归档前缀的最大编号加一，写入planned记录，再独占创建三个文件并读回校验。成功后记录为installed。游戏EXE/DLL哈希改变仅警告并记录；文件缺失、包损坏或游戏仍运行会中止。

ZIP中的`.patch_0`不是要求覆盖游戏中已有的编号。保留部署记录，其中包含游戏目录、包哈希及自有文件的哈希。不要清空`build/`导致丢失卸载依据。

## 从Steam启动并确认本次运行

安装后直接从Steam正常启动，无需Python、注入器或自定义启动器。先在飞船确认初始化，再进任务测试。

```powershell
Get-Process helldivers2 | Select-Object Id, StartTime
Get-Item "$env:LOCALAPPDATA\RoverFireSpread.log" | Select-Object Name, LastWriteTime
Get-Content "$env:LOCALAPPDATA\RoverFireSpread.log"
```

所有0.7.7渠道的本体日志均应为`build_id=experimental-0.7.7`，`process_id`对应本次游戏，更新时间晚于本次启动。连续读取时`samples`增长；飞船中的`waiting_for_mission`和`requests=0`正常。`build_id`本身不区分加载器渠道，需要结合ZIP身份和启动日志。

| 渠道 | 额外检查 |
| --- | --- |
| v12 | `%LOCALAPPDATA%/RoverFireSpread-startup.log`中有当次`bridge_entered`、`shared_loader_returned`和Rover状态 |
| v14 | 同一启动日志的build包含`-v14`（No HUD再加`-No-HUD`），且有`shared_loader_release=v14` |
| v15 | `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log`有Rover发现/加载记录；不会更新旧Rover启动桥日志 |

HUD包在飞船中通常显示顶部居中`ROVER | WAITING`。No HUD成功运行后为`hud_enabled=false`、`hud_status=disabled`，没有面板是预期行为。加载器的`loaded`只说明入口返回，不证明Rover控制器初始化成功；未知游戏字体布局也可能只禁用HUD。详见[调试手册](debugging.md)。

进入任务并装备激光漫游车，对多个有效敌人观察`requests`/`rotations`增量与活敌转火。计数不证明命中、点燃或新距离策略的全面正确性。

## 升级、切换变体与回退

先保存旧ZIP、匹配的package report、部署记录副本和必要日志。正常退出游戏后，在同一个游戏目录中移除旧包，再装所选包。由脚本管理的v12例如：

```powershell
& $pythonExe scripts/deploy.py uninstall
if ($LASTEXITCODE -ne 0) { throw 'Uninstall stopped; inspect the journal' }
& $pythonExe scripts/deploy.py install --variant no-hud
if ($LASTEXITCODE -ne 0) { throw 'Install failed; inspect build/deployment.json' }
```

安装使用当前所选报告指向的ZIP；回退时恢复与旧ZIP匹配的package report，不把旧deployment记录直接当成当前已安装状态。脚本卸载先逐项核对哈希，再只删除记录中的自有文件；不同哈希会拒绝继续，缺失文件可跳过。

管理器安装通过同一管理器禁用并重新部署。迁移v15时移除所有旧Rover启动包，将独立旧加载器替换为官方v15，再安装v15 Addon；不能保留旧Wwise桥叠加。停用Rover后保留其他Mod所需的独立加载器。没有运行时热更新。

## 本地状态与历史记录

2026-09-19 22:10：游戏关闭时由0.7.1升级为0.7.4默认v12 HUD内置加载器包。ZIP SHA-256为`AA9C01F3DA1EF71BFDBBC6BD1E660072A42E22D5B2EF69DB8DC8E2B053BEECDA`，patch_3及两个sidecar已读回核对，游戏文件匹配基线。旧安装文件、部署记录与日志保存在`build/pre-deploy-0.7.4-20260919-221017/`。尚未启动游戏验收。历史安装哈希和回退目录已集中到[本机历史部署记录](deployment-history.md)，当前六包身份以`build/package-matrix.json`为准。

## 失败时先看什么

| 现象 | 处理 |
| --- | --- |
| `Helldivers 2 is running` | 正常退出游戏再操作 |
| `A prior installation record exists` | 检查记录及实际文件，按正确记录卸载 |
| `Package checksum mismatch` | 找回匹配的报告/ZIP，不手改期望哈希 |
| `Installed file changed` | 核对管理器是否重编号/替换，确认文件归属 |
| planned / incomplete | 对照目标文件和记录；部分写入文件可能保留，不直接重试叠加 |
| 更改了`HD2_GAME_ROOT` | 不复用另一游戏目录的部署记录；脚本尚未强制比较记录目录 |

脚本没有游戏启动竞态的强锁，也不是跨目录迁移或通用修复工具。发现归属不明的文件时先核对记录。
