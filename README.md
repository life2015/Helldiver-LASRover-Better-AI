# Rover Fire Spread

目标：让激光护卫犬漫游车短暂攻击后更频繁地转向其他敌人，以便铺开点燃。当前策略以约 0.4 秒的攻击节点停留时间为参考；不读取燃烧状态，不保证实际命中时间或点燃成功。只有一个可用目标时继续原有攻击。

**实验版0.3已在两组实机场景中观察到持续转火**，用户确认会在敌人仍活着时换目标。普通场景约40秒新增17次请求并观察到17次请求期间目标变化；更多怪物的场景约40秒新增44次请求、42次目标变化，最多14条候选。仍未验证点燃覆盖率、精确命中时长、所有敌人类型或性能影响。

41项模拟测试及实际编译入口/归档检查通过。当前只支持已校验的 Steam build **24826606** / EXE **1.8.45317.0**。这是本地实验项目，尚未选定项目许可证或完成独立公开发布。

## 维护文档

从 [docs 文档索引](docs/README.md)开始，无需阅读开发对话：

- [实现架构与轮换策略](docs/architecture.md)
- [运行时布局、版本和原生分析依据](docs/runtime-layout.md)
- [开发环境、测试与构建](docs/development.md)
- [安装、Steam启动、升级与回退](docs/deployment.md)
- [日志、只读采样和故障定位](docs/debugging.md)
- [验证记录与下一步测试](docs/validation.md)
- [来源、独立仓库及公开维护准备](docs/maintenance.md)

## 实现概览

确认本地玩家→背包→无人机归属后，短暂抑制该无人机候选列表中的近期目标，并推进原生选敌期限。原生 AI 继续按自身评分选择目标，随后控制器比较字段和对象身份并恢复自己仍持有的临时修改。

0.3会等待启动阶段尚未就绪的数据并重试；不一致的快照不用于写入。它不修改行为 ID，不直接指定新目标，不调用游戏原生选敌函数。完整流程、恢复限制和参数入口见[架构文档](docs/architecture.md)。

## 构建与测试

使用Windows x64 Python和本机游戏Lua DLL。**先按[开发文档](docs/development.md)准备同级源码依赖和固定的Shared Loader输入**，再在本目录依次执行：

```powershell
python scripts/test.py
python scripts/build.py
python scripts/package.py
```

每步成功后再继续。`build.py`默认只生成诊断字节码；`package.py`重新编译实验入口并生成可安装ZIP。构建不会安装或启动游戏。游戏目录可通过`HD2_GAME_ROOT`指定。

正常退出游戏后，可用`python scripts/deploy.py install`安装，`uninstall`移除。保留`build/deployment.json`；安装完成后直接从Steam启动。完整说明见[部署文档](docs/deployment.md)和[包内安装说明](INSTALL.txt)。

调试时`observe.py`仅对游戏做外部只读采样；这与已安装实验Mod在游戏进程内修改数据是不同路径。先确认飞船日志与运行计数，再开始战斗测试。

## 来源

Windows API适配器及归档编码来自CowboyBingus/SentryAimRetention；启动桥包含固定的Bingus Shared Loader v12发布资源。来源版本、许可现状和后续独立化工作见[维护文档](docs/maintenance.md)。游戏模块快照、原始采样、游戏DLL不应混入公开源码。
