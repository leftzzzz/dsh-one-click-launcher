# DSH 一键启动器

[English](README.md) | 简体中文

这些脚本会启动 `@deepseek-ai/dsh` Web UI。启动脚本所在文件夹会成为 DSH 的默认
工作区位置。
系统界面语言为中文时，启动器会显示中文文案；其他语言统一显示英文。
请将 `dsh-manager.mjs` 与启动脚本保留在同一文件夹。

## 下载

- [Windows ZIP](https://github.com/leftzzzz/dsh-one-click-bootstrap/releases/latest/download/dsh-one-click-bootstrap-windows.zip)
- [Linux 和 macOS tar.gz](https://github.com/leftzzzz/dsh-one-click-bootstrap/releases/latest/download/dsh-one-click-bootstrap-linux-macos.tar.gz)
- [版本说明与 SHA-256 校验文件](https://github.com/leftzzzz/dsh-one-click-bootstrap/releases/latest)

请先解压再启动 DSH。推送 `v1.0.0` 这类版本标签后，Release 压缩包会自动发布。

## Windows

双击 `start-dsh.cmd`，使用 DSH 时不要关闭启动器新打开的 PowerShell 窗口。

也可以直接运行 PowerShell 脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1
```

## Linux 和 macOS

首次使用时赋予 Bash 脚本执行权限，然后运行：

```bash
chmod +x ./start-dsh.sh
./start-dsh.sh
```

部分桌面环境允许直接双击已经设置为可执行的脚本。

## 脚本会安装什么

- 已有 Node.js 24 或 Node.js 22（最低 22.19）时直接使用，不重复安装；不使用其他
  Node.js 主版本。
- Node.js 缺失或版本不兼容时，从 `nodejs.org` 下载最新版 Node.js 24，校验官方
  SHA-256 后仅安装到当前用户目录。
- DSH 会按版本安装到当前用户目录，并为每个版本保存 `package-lock.json`；启动时
  直接使用已验证的版本目录，不通过 `npx` 重新解析依赖。
- 首次启动会安装最新版。后续每 24 小时最多检查一次更新，发现新版本时先询问；
  确认后才安装并切换，拒绝后会跳过该版本并继续使用当前版本。
- 升级成功后保留当前版本和上一个版本，自动删除更早的受管 DSH 版本。
- 更新检查或新版本安装失败时，继续使用当前版本。
- 不修改系统 `PATH`，不需要管理员权限。

首次启动或确认升级后，安装并初始化 DSH 可能需要几分钟。启动器会显示活动进度条
和真实已用时间。检测到 `dsh web:` 的就绪地址后会自动打开默认浏览器；如果系统
无法打开浏览器，请手动访问命令行中显示的地址。在命令行窗口按 `Ctrl+C` 即可
停止 DSH。
