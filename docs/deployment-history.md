# 本机历史部署记录

归档日期：2026-09-19。以下从旧部署指南迁出，保留曾安装包的哈希及回退证据；每段描述当时的状态，不是当前安装指令。旧版HUD位置、Recent参数和包名不能用于当前版本。

截至本次文档核对，本机`build/deployment.json`仍记录0.7.1对应的ZIP及patch哈希；0.7.2六包仅构建、未部署。本机记录与玩家实际安装无关，后续以各自的部署记录及本次进程日志为准。现行操作见[部署与启动](deployment.md)，功能验证见[验证记录](validation.md)。

历史安装：0.7.1：绿/黄MOD标题在请求恢复结束后多显示0.5秒并标注(last)，不延长实际请求。游戏关闭时顺序卸载0.7并安装0.7.1，patch_3与两个sidecar读回校验通过；118项Lua、3项部署测试和编译/归档检查通过。ZIP SHA-256：`3D5247041A68364A128C990AA0B64CC0D031B887DF2E6E2B6DE77F3FC1825768`；patch_3 SHA-256：`D0D143BB2D9D6870DE64B7C12F1068949A76963248090C33FA18C0E47B4842D4`。旧0.7 ZIP保留，匹配报告及部署记录在`build/rollback-0.7/`。以下为历史记录。

历史安装：0.7：相邻敌人优先，当前目标在漫游车15米外时优先转回圈内有效敌人；0.5秒锁定超时仍按距漫游车最近解卡。游戏关闭时顺序卸载0.6.1并安装0.7，patch_3与两个sidecar读回校验通过。ZIP SHA-256：`9FB69F4301D65AEF83A1952D2576A588A5B1B9DDC2C7491630D1CA11D43E12A0`；patch_3 SHA-256：`6D37E05FBFAC70B409EDD0B57DD792F4CE5E97A0B903160206033D64ACEFAAD6`。旧包及`build/rollback-0.6.1/`匹配报告、部署记录和更新前运行日志保留。115项Lua、3项部署测试及编译/归档检查通过，新排序效果待Steam重启实测。以下为历史记录。

历史安装：0.6.1：修复Next请求过短时难以看到的问题，最近请求从提交起显示2秒并标注`(last)`，实际索敌和请求期限不变。patch_3及两个sidecar复制校验通过。ZIP SHA-256：`7A618253473FD24FBE0B07C05F80A3E84A70C4B588C969764D92FDC78FFA5822`；patch_3 SHA-256：`94E6AC5F811C08D7A57735E889F7CFF4D921DB7EF269AD0FBEC5B7210F6C24E7`。旧0.6 ZIP保留，匹配报告、部署记录及更新前运行日志位于`build/rollback-0.6/`。101项Lua测试及编译入口/归档检查通过，0.6.1显示效果待重启实测。以下均为历史部署记录。

历史安装：0.6：顶部居中、Recent 1项/1秒、0.5秒未进入同步攻击状态后重选。游戏关闭时更新patch_3及两个sidecar，复制后校验通过。ZIP SHA-256：`81039F62322918FCE271003D40F70CA36A05912B1C2FF357B6DEB5E90F617FC9`。0.5.1旧包保留，报告与旧部署记录在`build/rollback-0.5.1/`。下面各版均为历史记录；新超时行为仍待实机验证。

历史安装：0.5.1（增加Locked/Next目标ID），patch_3及两个sidecar均校验通过。ZIP SHA-256：`A55276B00E84F446381E3AA928F88ADD336A0EDB122B124A9BDD92B742D95B2F`。0.5旧包保留，匹配报告/部署记录位于`build/rollback-0.5/`。以下0.5及更早条目为历史安装记录。

历史更新至0.5（带HUD），仍为patch_3及两个sidecar，安装后校验通过。ZIP SHA-256为`DAB6F7F88D8802F54744E0CA5C6AFBBB09A2CEFF42051EB9D4E96A492A6650C5`。旧0.4.1包及`build/rollback-0.4.1/`报告/部署记录已保留。先在飞船确认左侧的`ROVER | WAITING`及`hud_status=visible`，再战斗验证。下面的0.4.1/0.4记录均为历史信息。

随后同日更新为0.4.1，仍为patch_3及两个sidecar。当时包SHA-256为`4B08ECA3F22F684F95435D6D6CAF28C8B21E3175ABFF5393627D3D023C57D0BD`，游戏文件仍匹配基线。旧0.4包保留，匹配报告和旧部署记录在`build/rollback-0.4/`；以下0.4安装记录为历史信息。

2026-09-18本机已更新为0.4，仍使用`9ba626afa44a3aa3.patch_3`及两个sidecar，复制后哈希校验通过。包为`releases/Rover-Fire-Spread-Experimental-0.4.zip`，SHA-256为`090CF5D9206F9313BD52225A05526EDB03332EF64D8CE5C5FCFC3D7BBB414A5E`。0.3旧包仍在`releases/`；匹配的报告和旧部署记录备份在`build/rollback-0.3/`。旧报告从原ZIP内的`provenance.json`恢复并补入已核验的ZIP名称及哈希。0.4新增距离排序尚待实机验收。
