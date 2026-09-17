# 开发与构建

## 当前工作区要求

构建工具使用 Windows x64 Python 和本机游戏的 `bin/lua51.dll`，仅用 Python 标准库。原开发环境使用 Python 3.12。不要用无法加载 Windows DLL 的 Linux Python 来运行这些脚本。

当前目录布局必须保留：

```text
workspace/
  RoverFireSpread/
    src/ scripts/ tests/ docs/
    build/                  # 本地输入和生成物，忽略提交
    releases/               # 生成的实验包，忽略提交
  SentryAimRetention/
    scripts/archive.py      # package.py 直接导入
  research/
    observe_rover.py         # observe.py 直接导入 Reader 及版本常量
    artifacts/              # 只读采样输出，忽略提交
```

仅复制 `RoverFireSpread` 时，测试和字节码编译可在满足 Lua DLL 条件后运行，但打包缺少 `archive.py`，外部采样缺少 `observe_rover.py`。它们不是 pip 包。独立仓库整理是后续工作，不能用一次本机成功构建代替干净环境复现。

`SentryAimRetention` 的原开发 checkout 为提交 `3582f4f381e70cd6e63a49bac4cc9f90ca061aa7`，远程地址是 `https://github.com/CowboyBingus/SentryAimRetention.git`。构建仅从其中导入归档编码与资源哈希逻辑；不需要编译或安装整个哨戒炮 Mod。

## 配置 Python 和游戏目录

下列命令均在 `RoverFireSpread` 根目录的 PowerShell 中执行。`$pythonExe` 应是已安装的 64 位 Python；若 `python` 指向 Windows Store 占位程序，改成真实可执行文件路径。

```powershell
$pythonExe = 'python'
& $pythonExe -c "import sys, struct; print(sys.version); print('pointer bits:', struct.calcsize('P') * 8)"
$env:HD2_GAME_ROOT = 'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2'
Test-Path -LiteralPath (Join-Path $env:HD2_GAME_ROOT 'bin\lua51.dll')
```

`HD2_GAME_ROOT` 是可选项，默认即上述目录。不要把个人 Python 缓存路径提交为公共默认值。

[`scripts/lua_host.py`](../scripts/lua_host.py) 通过 `ctypes.CDLL` 把游戏自带的 Lua DLL 加载到**构建 Python 进程**，创建独立 Lua state，使用 `string.dump` 生成 stripped bytecode。它不向游戏进程注入 DLL。要求非 GC64 模式，输出头须为 `1b 4c 4a 02 02`；不要任意换用系统 Lua/LuaJIT 编译器。

## 准备固定的共享加载器输入

`package.py` 不自动下载依赖。它要求 `build/Bingus-Shared-Loader-v12.zip`，而不是“最新版”。原始下载来源及校验：

```powershell
New-Item -ItemType Directory -Path build -Force | Out-Null
$loaderZip = Join-Path (Get-Location) 'build\Bingus-Shared-Loader-v12.zip'
if (-not (Test-Path -LiteralPath $loaderZip)) {
    Invoke-WebRequest -Uri 'https://github.com/CowboyBingus/BingusSharedLoader/releases/download/v12/Bingus-Shared-Loader-v12.zip' -OutFile $loaderZip
}
$expectedLoaderHash = '4A95D7A056F0A9E01842420883059A380374092145B5D9EC807C14C8CA351568'
if ((Get-FileHash -LiteralPath $loaderZip -Algorithm SHA256).Hash -ne $expectedLoaderHash) {
    throw 'Shared Loader input checksum mismatch'
}
```

提取的完整 Wwise Lua resource（含 8 字节资源头）SHA-256 应为 `D07ED04A7F68D588F424D155AFD8F08B1BFC4D946C90FBC5BBBDCADE1EB69123`。`package.py` 同时检查 ZIP 和 resource 的哈希，失败时应检查输入，不应删除断言。

## 测试、编译、打包

按顺序执行，每步成功后再继续：

```powershell
& $pythonExe scripts/test.py
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }

& $pythonExe scripts/build.py
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic compilation failed' }

& $pythonExe scripts/package.py
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
```

各脚本作用不同：

| 命令 | 结果 | 会安装吗 |
| --- | --- | --- |
| `test.py` | 执行 `tests/test_*.lua`，每文件独立 Lua state | 不会 |
| `build.py` | 默认生成禁止写入的诊断 Lua/字节码及 `build-report.json` | 不会 |
| `build.py --experimental` | 单独生成开启控制器写入的入口字节码 | 不会 |
| `package.py` | 重新编译实验入口、构建启动桥、跑桥接检查、生成 ZIP 和 package report | 不会 |

`package.py` **不会代跑全部 `test_*.lua`**，所以发布前必须单独跑 `test.py`。单独编译后的 `.luac` 不是可以直接丢进游戏目录的 Mod。

0.3 的独立测试共 41 项：核心控制/恢复 21、入口生命周期 6、快照布局 14。打包时另执行 `tests/check_bridge.lua`，验证实际编译入口执行、原音频回调保持、阶段日志和重复初始化保护，再做资源往返及 ZIP 完整性检查。

桥接测试运行在没有 `game.dll` 的独立进程，预期 Rover 报告版本/模块校验失败；它证明入口被执行，不是模拟了整场游戏。测试中的文件写入必须隔离，见[历史教训](debugging.md)。

## 包内结构及启动链

生成 ZIP 的主要文件：

```text
data/9ba626afa44a3aa3.patch_0
data/9ba626afa44a3aa3.patch_0.stream
data/9ba626afa44a3aa3.patch_0.gpu_resources
manifest.json
provenance.json
INSTALL.txt
```

两个 sidecar 为空。主归档包含 `mods/retrox/rover_fire_spread` 和 `core/wwise/lua/wwise_flow_callbacks` 两个 Lua resource。0.3 启动桥直接内嵌执行实验入口，不依赖新模块的 `require` 路径；独立模块资源仍保留，初始化全局 guard 防止重复执行。

编码取自 `SentryAimRetention/scripts/archive.py`：magic `0xF0000011`，Lua type `0xA14E8DFA2CD117E2`；归档头 72 字节，type entry 32 字节，resource entry 80 字节，主体按 16 字节对齐。Lua resource 是 `<uint32 bytecode_size, uint32 version=2>` 后接字节码。文件名来自资源路径的 64 位哈希；不要用 Python 内建 `hash()` 替代。

## 构建报告与复现

`build/experimental-package-report.json` 保存来源校验、源码摘要、启动测试、归档和 ZIP 哈希。`provenance.json` 是打包时刻的报告；它不会因为后来一次实机成功而自动改变。

已实测安装的 0.3 ZIP SHA-256 是：

```text
9B59A01521D14C91262CA13DA4F97814108EB9FBBAD8B79DD4C76C35D061D3F1
```

这是历史被测包的身份，不是要求任何未来重新构建都必须得到此值。脚本固定了 ZIP 条目时间，但未承诺跨 Python/zlib 版本逐字节一致。源码或 `INSTALL.txt` 变更也会产生新包。不要为刷新文档或实测标记直接覆盖被测包而丢失证据。

## 发下一版时容易漏掉的地方

0.3 的版本号尚未集中管理，至少核对 `src/install.lua`、`src/startup.lua`、`scripts/package.py` 中的显示版本/入口名/ZIP 名，以及 `INSTALL.txt`、README、验证记录。哈希、签名与支持版本的多处定义见[布局文档](runtime-layout.md)。

针对源码改动先跑对应测试；打包前跑全部 41 项及桥接检查。改变策略时补有区分能力的边界场景，例如大量目标、单目标、节点切换或请求失败，不只复制实现写断言。只有文档改动时，检查链接、命令、常量与现有报告即可，无须重新部署游戏。
