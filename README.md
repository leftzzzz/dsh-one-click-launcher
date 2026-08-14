# DSH One-Click Launcher

English | [简体中文](README.zh-CN.md)

These scripts launch the `@deepseek-ai/dsh` Web UI in the current directory. The
directory containing the scripts becomes the default DSH workspace.
Launcher messages are shown in Chinese when the system UI language is Chinese;
all other languages use English.
Keep `dsh-manager.mjs` in the same directory as the launcher scripts.

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
- DSH is installed into a user-local directory per version, with a
  `package-lock.json` retained for each installation. Launches use the validated
  version directory directly instead of asking `npx` to resolve dependencies.
- The first launch installs the latest version. Later launches check for updates
  at most once every 24 hours and ask before installing one; declining skips
  that version and keeps the current version.
- If an update check or installation fails, the current version remains active.
- The scripts do not modify the system `PATH` and do not require administrator
  privileges.

The first launch or an accepted upgrade may take several minutes while DSH is
installed and initialized. The launcher shows an activity bar with real elapsed
time. When DSH prints its `dsh web:` readiness URL, the launcher opens it in the
default browser. If the browser cannot be opened, use the URL shown in the
terminal. Press `Ctrl+C` in the command prompt or terminal window to stop DSH.
