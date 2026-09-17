# 部署、启动、升级与回退

## 两种安装方式

优先选择一种方式管理同一安装：Mod 管理器或本地脚本。不要同时手动放文件又让管理器重新部署并改编号，否则本地部署记录可能不再对应实际文件。

使用 Arsenal/HD2MM 时，导入构建好的实验 ZIP、启用并部署。本包包含 Bingus Shared Loader v12 的启动桥，需赢得 `core/wwise/lua/wwise_flow_callbacks` 的冲突。依照当前固定输入附带的说明，Arsenal 默认优先级下放最后；如果开启首项优先，则放最前。其他管理器以实际资源覆盖结果为准，不只看列表位置。

本包不改写 `boot`。已有自定义 `boot` 或其他 Wwise 替换可能影响初始化顺序；保留音频回调和原加载器不等于兼容任意启动 Mod。先核对自己的加载链，再用阶段日志确认。独立共享加载器不认识 Rover 模块，不能只装模块资源后期待原加载器自动发现它。

## 本地脚本安装

在 `RoverFireSpread` 根目录，使用[开发文档](development.md)配置的 `$pythonExe` 和 `HD2_GAME_ROOT`。构建完成后，**正常退出游戏**再执行：

```powershell
& $pythonExe scripts/deploy.py install
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed; inspect the journal before retrying' }
```

脚本会：

1. 用 `tasklist` 确认没有 `helldivers2.exe`，并核对游戏文件及实验 ZIP 的校验值。
2. 枚举同一归档前缀已有 `patch_N` 及 sidecar，选最大编号加一。
3. 写入 `build/deployment.json` 的 planned 记录；再次检查游戏已关闭。
4. 以独占新建方式复制三个文件，读回校验成功后将记录改为 installed。

ZIP 内的 `.patch_0` 只是包内名字；不要因此覆盖游戏里已有的 `.patch_0`。原开发环境部署到了 `.patch_3`，其他人的编号可能不同。脚本不修改已有 Mod 文件，也不自动启动游戏。

保留 `build/deployment.json`，其中有目标目录、ZIP 哈希、三个文件名和文件哈希。不要把清空 `build/` 当成日常清理步骤：当前卸载依赖这份记录。该记录属于本机状态，不应公开提交。

## 正常启动和首次验收

安装后直接从 Steam 正常启动 Helldivers 2，不需要单独启动 Python、注入器或自定义游戏启动器。

先在飞船停留并检查：

```powershell
Get-Process helldivers2 | Select-Object Id, StartTime
Get-Item "$env:LOCALAPPDATA\RoverFireSpread-startup.log", "$env:LOCALAPPDATA\RoverFireSpread.log" |
    Select-Object Name, LastWriteTime
Get-Content "$env:LOCALAPPDATA\RoverFireSpread-startup.log"
Get-Content "$env:LOCALAPPDATA\RoverFireSpread.log"
```

启动日志应包含当前 build、`bridge_entered`、`shared_loader_returned` 和实验模式的 Rover 状态。主日志的 `process_id` 应对应当前进程，更新时间应晚于本次启动；连续两次读取时 `samples` 应增长。飞船里的 `waiting_for_mission` 是正常状态，`requests=0` 也正常。

初始化成功后再进入任务，装备激光漫游车，在多个可用敌人附近观察。确认 `requests` 和 `rotations` 的增量，并观察是否在敌人还活着时换目标；一个日志计数不能证明已命中或已点燃。详见[调试手册](debugging.md)。

## 升级

先保存被测旧 ZIP、package report、部署记录副本及必要日志。确认新包测试完成后，关闭游戏，在**同一 `HD2_GAME_ROOT`**下依次执行：

```powershell
& $pythonExe scripts/deploy.py uninstall
if ($LASTEXITCODE -ne 0) { throw 'Uninstall stopped; do not continue with installation' }
& $pythonExe scripts/deploy.py install
if ($LASTEXITCODE -ne 0) { throw 'Install failed; inspect build/deployment.json' }
```

安装使用当前 `experimental-package-report.json` 指向的 ZIP，因此要确保报告与要安装的版本一致。脚本不支持运行时热更新，也不自动合并管理器的部署记录。

## 卸载与回退

退出游戏后执行 `deploy.py uninstall`。脚本按部署记录逐个核对哈希；如果某个现有文件不同，拒绝继续删除，避免把别的 Mod 当成本项目。已不存在的文件会跳过。成功后只移除记录中的自有文件，把状态改为 removed。

通过管理器安装的包应通过同一管理器禁用并重新部署。移除本包的启动桥后，如果仍有其他 Mod 依赖 Bingus Shared Loader，需要保留或恢复独立共享加载器。

回退旧版本时，使用保存的旧 ZIP 和与其匹配的 package report；先卸载当前版本，再安装旧包，保留新旧各自的证据。不要把旧部署记录直接拷回去当作当前已安装状态。

## 失败时先看什么

| 现象 | 处理 |
| --- | --- |
| `Helldivers 2 is running` | 正常退出游戏再操作，不强杀游戏来跳过保护 |
| `A prior installation record exists` | 检查记录及实际文件；通常先按正确记录卸载 |
| `Package checksum mismatch` | 找回匹配的报告/ZIP，不手填期望哈希绕过校验 |
| `Installed file changed` | 判断是否被管理器重编号/替换；核实文件归属后再处理 |
| planned / incomplete | 对比三个目标文件和记录；脚本只回滚能确认完全匹配的本次文件，部分写入文件可能保留 |
| 改了 `HD2_GAME_ROOT` | 不复用另一游戏目录的部署记录；现脚本未强制把环境目录与记录目录作一致性比较 |

部署工具目前是本地脚本，不是完整的包管理器：没有游戏启动竞态的强锁，也没有跨目录迁移和通用修复功能。其边界应写进下一轮维护任务，而不是依靠手动改日志掩盖失败。
