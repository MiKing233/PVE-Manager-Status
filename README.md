# PVE-Manager-Status
为你的 ProxmoxVE 节点概要页面添加扩展的硬件监控信息

无论是小型 HomeLab 还是多节点的大型集群, 借助 PVE-Manager-Status 让你对当前服务器硬件状态了如指掌!

PVE-Manager-Status 是一款强大的开源脚本工具, 通过实时基于动态颜色的关键指标显示, 帮助你直观的了解服务器各项硬件的负载和温度, 从而轻松掌握设备的实时运行状态以确保其稳定高效.

<img width="1120" height="699" alt="image" src="https://github.com/user-attachments/assets/51224701-a763-4b14-9951-5990f7e22901" />

## 免责声明

在任何正式或关键的生产环境中, 未经完整测试与评估, 严禁直接部署和运行本工具. 在使用本工具之前, 您务必对代码进行详尽的审阅, 充分理解其运行机制, 使用该工具后的风险由您自行承担.

## 包含的功能

- 为ProxmoxVE Web 管理界面的节点概要中添加各项硬件的实时监控信息.
- 根据各项硬件的温度或负载, 使用红黄绿从高到低标注各项参数的数值显示.

## 如何使用

要使用本项目, 请通过 SSH 连接你的 Proxmox VE 节点, 并执行以下操作:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MiKing233/PVE-Manager-Status/master/pve-manager-status.sh)"
```

执行完毕后, 使用Ctrl + F5 刷新浏览器PVE页面缓存.

## 已知问题

- SATA 硬盘监控的代码实现部分, 未经过任何形式的测试, 也许完全不起作用, 我目前没有能够使用 SATA 硬盘的 x86 设备无法对这部分进行测试.
- nvme 硬盘监控部分对于 I/O 实时读写速度和延迟的实现代码使用目前常见的 iostat -d -x -k 1 1 但这将导致长时间运行后 iostat 进程被休眠或杀死, 你将会看到这部分监控参数"冻结", 在重启前将永远不再刷新, 尝试过使用其它方式实现这个功能避免冻结, 但都未能达到预期的效果, 有些实现方式复杂超出预期短期内无法解决, 另外一些能生效的方法则不够优雅, 会导致Web页面自动刷新间隔变得非常长.
- nvme 硬盘监控部分暂时只支持识别第一块.
- 脚本执行修改完成后, 如果核心数量过少或过多以及存在硬盘数量不同, 页面高度适配将不正常, 可能出现大量留白或是超出页面高度.

## 未来计划

- 修复一些针对 zh-CN 翻译缺失的部分
- 支持识别多块 nvme 硬盘

## 相容性

- 适用于基于 Debian 12 "bookworm" 的 Proxmox VE 8.x 和基于 Debian 13 "trixie" 的 Proxmox VE 9.0-1.
- 理论上支持 Proxmox VE 7.x 等旧版环境但未经过实际测试. 您需要在拥有root权限的节点上运行该工具执行修改.
- 在将脚本应用到实际环境之前, 最好先在测试环境进行测试, 若发生意外请通过下面的命令重新安装 pve-manager 来复原被修改的文件.
```
apt install --reinstall pve-manager
```

## 贡献

欢迎您的贡献! 如果您有任何改进或调整, 请 fork 代码库并提交拉取请求.

## 联系与反馈

如果您遇到任何问题或有任何建议, 请在 GitHub 代码库中提交问题.

## 致谢

感谢以下来源和社区贡献, 本项目的诞生离不开源自这些来源和贡献:

- https://github.com/shidahuilang/pve
- https://github.com/xiangfeidexiaohuo/pve-diy
- https://bbs.x86pi.com/thread?topicId=20
- https://community-scripts.github.io/ProxmoxVE
- https://github.com/community-scripts/ProxmoxVE
- https://github.com/proxmox/pve-manager
- https://github.com/Debian

## 贡献者

<a href="https://github.com/MiKing233/PVE-Manager-Status/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=MiKing233/PVE-Manager-Status" />
</a>

## 许可证

本项目为开源项目, 遵循 MIT License.

这些代码按"原样"提供, 不提供任何担保, 也不授予任何权利. 您有责任安全地使用本工具, 并遵守软件许可协议的条款.

## 请我喝杯咖啡

捐赠是本项目唯一的收入来源, 如果您愿意支持这个项目, 这将帮助该项目走得更远! 感谢您的支持!
- https://donate.mknetwork.net

### 如果你喜欢这个项目, 请不要吝啬您的 Star 🌟
[![Stargazers over time](https://starchart.cc/MiKing233/PVE-Manager-Status.svg?variant=adaptive)](https://starchart.cc/MiKing233/PVE-Manager-Status)

Enjoy a better Proxmox VE experience!
