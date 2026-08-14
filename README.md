# DSH One-Click Launcher

English | [简体中文](README.zh-CN.md)

These scripts launch the `@deepseek-ai/dsh` Web UI in the current directory. The
directory containing the scripts becomes the default DSH workspace.

## Windows

Double-click `start-dsh.cmd`. Keep the command prompt window open while using DSH.

You can also run the PowerShell script directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1
```

## Linux and macOS

Make the Bash script executable before running it for the first time:

```bash
chmod +x ./start-dsh.sh
./start-dsh.sh
```

Some desktop environments also let you double-click the script after it has been
made executable.

## What the scripts install

- If a compatible Node.js version is already available, the scripts use it
  without installing another copy.
- If Node.js is missing or incompatible, the scripts download the latest Node.js
  24 release from `nodejs.org`, verify it against the official SHA-256 checksum,
  and install it for the current user only.
- `npx` downloads and caches the latest `@deepseek-ai/dsh` package as needed.
- The scripts do not modify the system `PATH` and do not require administrator
  privileges.

Once DSH starts, open <http://127.0.0.1:3080>. Press `Ctrl+C` in the command prompt
or terminal window to stop DSH.
