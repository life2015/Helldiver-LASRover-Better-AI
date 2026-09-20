# 开发与构建

当前版本0.7.4；更新于2026-09-19。默认打包一次生成v12/v14/v15 × HUD/No HUD六包，不部署也不启动游戏。

## 环境和目录依赖

使用Windows x64 Python及游戏自带`bin/lua51.dll`，Python部分仅依赖标准库。原开发环境为Python 3.12。Linux Python无法加载这些Windows DLL。

```text
workspace/
  RoverFireSpread/
    src/ scripts/ tests/ docs/
    build/                         # 固定输入、生成报告、本机部署记录
    releases/                      # 生成ZIP
  SentryAimRetention/
    scripts/archive.py             # 打包直接导入
  research/
    observe_rover.py                # 外部观察器直接导入Reader和版本常量
    artifacts/                     # 本地研究证据
```

只复制本仓库可以在满足Lua DLL条件后测试/编译，但打包还需要同级`archive.py`，外部采样还需要`observe_rover.py`。SentryAimRetention固定研究checkout为`3582f4f381e70cd6e63a49bac4cc9f90ca061aa7`，来源`https://github.com/CowboyBingus/SentryAimRetention.git`；无需编译或安装整个哨戒炮Mod。

`package.py`将归档依赖路径插在本项目脚本路径之后。不要改为优先导入依赖目录，否则其中同名`package.py`可能遮蔽本项目的多渠道构建模块。

## 配置运行环境

在RoverFireSpread根目录的PowerShell中执行。`$pythonExe`使用真实的64位Python，若`python`指向Windows Store占位程序则替换它。

```powershell
$pythonExe = 'python'
$env:PYTHONIOENCODING = 'utf-8'
$env:HD2_GAME_ROOT = 'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2'
& $pythonExe -c "import sys, struct; print(sys.version); print('pointer bits:', struct.calcsize('P') * 8)"
Test-Path -LiteralPath (Join-Path $env:HD2_GAME_ROOT 'bin\lua51.dll')
```

`HD2_GAME_ROOT`可省略，默认即上述目录。不要把个人缓存路径写成公共默认值。

[`scripts/lua_host.py`](../scripts/lua_host.py)通过ctypes在构建Python进程创建独立Lua state，用游戏LuaJIT的`string.dump`生成stripped bytecode；不是向游戏进程注入DLL。要求非GC64模式，输出头为`1b 4c 4a 02 02`，不要随意替换为系统Lua编译器。

## 准备三个固定加载器输入

打包脚本不自动下载。先分别取得官方[v12](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v12)、[v14](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v14)、[v15](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v15)的ZIP，保留发布文件名放入build/。完整输入SHA-256见[多渠道说明](packaging-channels.md)。

```powershell
New-Item -ItemType Directory -Path build -Force | Out-Null
foreach ($loaderVersion in @('v12', 'v14', 'v15')) {
    $loaderPath = Join-Path (Get-Location) "build\Bingus-Shared-Loader-$loaderVersion.zip"
    if (-not (Test-Path -LiteralPath $loaderPath)) { throw "Missing input: $loaderPath" }
    Get-FileHash -LiteralPath $loaderPath -Algorithm SHA256
}
```

`package.py`在开始六包构建前检查三个ZIP的固定哈希，并校验v12/v14回调资源。输入不匹配时应找回正确发布物，不删除断言或静默替换为最新版。v15输入用于离线集成测试，不会内置到Rover的v15包。

## 测试和打包

按顺序执行，每一步成功后再继续：

```powershell
& $pythonExe scripts/test.py
if ($LASTEXITCODE -ne 0) { throw 'Lua tests failed' }
& $pythonExe tests/test_deploy.py
if ($LASTEXITCODE -ne 0) { throw 'Deployment tests failed' }
& $pythonExe scripts/build.py
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic compilation failed' }
& $pythonExe scripts/package.py
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
```

| 命令 | 作用 |
| --- | --- |
| `test.py` | 每个`test_*.lua`使用独立Lua state；当前127项：核心66、生命周期13、HUD25、位置6、快照17 |
| `tests/test_deploy.py` | 5项临时模拟目录测试，验证部署校验、No HUD选择及卸载后切换，不接触真实安装 |
| `build.py` | 默认生成禁止写入的诊断入口和报告 |
| `build.py --experimental [--no-hud]` | 单独编译实验本体，不生成完整安装ZIP |
| `package.py` | 重新编译两个实验本体，包装六包，运行启动/归档验证，生成矩阵索引 |
| `package_v14.py` / `package_v15.py` | 各生成两个变体，要求当前v12基础ZIP及报告名称/哈希匹配；不自动重新编译基础包 |

`package.py`不代跑全部Lua或部署测试。源码修改后单独运行相关测试，正式构建前执行上述流程；文档修改只需核对内容和链接，不需要重新部署。

`compile_entry(enabled, show_hud)`控制运行模式及是否编入HUD。No HUD从源码列表移除hud，传入`hud=nil`和`show_hud=false`，不创建GUI、不读取字体或绘图，控制器和文本日志照常。HUD和No HUD共有源码及target_policy由构建断言核对。

## 两种启动链与包结构

| 渠道 | ZIP资源目录 | Lua资源及入口 |
| --- | --- | --- |
| v12/v14 | `data/` | Rover本体资源与Wwise回调桥；桥保留对应官方加载器，再直接执行内嵌Rover编译入口 |
| v15 | `Addon/` | 纯文本`mods/retrox/rover_fire_spread`声明入口及编译后的`mods/retrox/rover_fire_spread_impl`；由独立官方v15发现并require |

各包资源目录中均有`9ba626afa44a3aa3.patch_0`及空的`.stream`、`.gpu_resources`；另外附manifest.json、provenance.json和INSTALL.txt。两种HUD变体分别编译，同一变体在三个渠道的本体逐字节相同。所有包共用GUID `209a1d35-17ef-4c55-a163-616bf8f31861`，不能同时安装。

v15声明必须是纯文本且首行为`-- HD2-Addon: mods/retrox/rover_fire_spread`；不要strip/编译该入口。实现资源仍为字节码。构建检查不包含Wwise或boot，与固定官方v15没有Lua资源交集。

归档编码来自同级`archive.py`：magic `0xF0000011`、Lua type `0xA14E8DFA2CD117E2`；头72字节、type entry 32字节、resource entry 80字节，主体按16字节对齐。Lua资源由`<uint32 size, uint32 version=2>`及正文组成；正文可以是本项目v15声明文本或相应编译字节码。路径使用64位资源哈希，不是Python内建hash()。

## 启动测试的边界

v12/v14分别执行实际编译桥，验证原音频回调、Rover入口及HUD配置、重复初始化；v14还检查固定模块名单、失败隔离及已有协调器。v15使用实际官方发布字节码和Win32文件枚举扫描临时归档，对两个变体分别验证加载器高编号、Addon高编号、缺失实现、无Addon。

这些测试在没有game.dll的独立构建进程内运行；Rover初始化受控失败是预期，不表示游戏内控制器已运行。其他Mod及引擎资源查询为模拟。另有归档往返、ZIP完整性、本体一致性检查，均不能替代实机共存或整机稳定性验证。

## 文件名、报告与复现

ZIP统一为`激光狗索敌优化-0.7.4-渠道-加载器说明[-No-HUD].zip`。v12/v14说明为“内置加载器”，v15为“需要额外安装加载器”；manifest显示名也标注。名称集中在`package.py`的`PACKAGE_NAME`及`package_name()`，完整清单见[多渠道说明](packaging-channels.md)。

| 文件 | 用途 |
| --- | --- |
| `build/build-report.json` / `build-report-no-hud.json` | 最近一次对应本体编译结果；诊断与实验共用报告名，注意mode和刷新时间 |
| `build/experimental-package-report.json` / `experimental-package-report-no-hud.json` | v12 HUD/No HUD包身份及默认部署输入 |
| `build/v14-compat/{hud,no-hud}/package-report.json` | v14渠道报告 |
| `build/v15-addon/{hud,no-hud}/package-report.json` | v15渠道报告 |
| `build/package-matrix.json` | 本次成功构建的六包名及SHA-256；分发从这里选，不按目录里所有ZIP批量发送 |
| 包内`provenance.json` | 打包时的来源和验证信息，不会随之后实测自动改变 |
| `build/deployment.json` | 本机实际安装/移除记录，与构建报告分开；不能当作可清理生成物 |

报告模式有渠道差异：基础包是`sources`，派生渠道以`core_sources`记录本体来源；v15明确`bundled_loader=false`。不要假定所有渠道具有完全相同的报告字段。

ZIP条目时间固定，但不承诺跨Python/zlib版本逐字节一致；文档或manifest更新也会改变ZIP哈希。已经分发/实测的包应保留原ZIP和匹配报告，用独立验证记录追加结论。文档更新不会自动更新已有ZIP内的说明，下次打包才嵌入新内容。

## 发下一版前

运行版本仍分散在`src/install.lua`、`src/startup.lua`和`scripts/package.py`；核对日志版本、桥接测试预期、manifest、README、INSTALL.txt和文档。游戏哈希及签名的定义和适配步骤见[运行时布局](runtime-layout.md)。

按变更补充有区分能力的边界测试，特别是节点切换、目标身份复用、写入失败和恢复。最后生成六包并核对矩阵，保留来源和实测证据。干净环境构建及无游戏DLL的CI仍未完成，详见[维护说明](maintenance.md)。
