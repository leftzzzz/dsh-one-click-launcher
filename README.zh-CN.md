# DSH 一键启动器

[English](README.md) | 简体中文

这些脚本会在当前文件夹启动 `@deepseek-ai/dsh` Web UI。脚本所在文件夹会成为
DSH 的默认工作区位置。

## Windows

双击 `start-dsh.cmd`，使用 DSH 时不要关闭命令行窗口。

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

- 已有兼容的 Node.js 时直接使用，不重复安装。
- Node.js 缺失或版本不兼容时，从 `nodejs.org` 下载最新版 Node.js 24，校验官方
  SHA-256 后仅安装到当前用户目录。
- `npx` 会按需下载并缓存最新版 `@deepseek-ai/dsh`。
- 不修改系统 `PATH`，不需要管理员权限。

启动后打开 <http://127.0.0.1:3080>。在命令行窗口按 `Ctrl+C` 即可停止 DSH。
