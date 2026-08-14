import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { createInterface } from "node:readline/promises";

const DSH_PACKAGE = "@deepseek-ai/dsh";
const UPDATE_INTERVAL_SECONDS = 24 * 60 * 60;
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;

const [
  installBaseArgument,
  language = "en",
  npmCommand,
  mode,
  ...dshArguments
] = process.argv.slice(2);
if (!installBaseArgument || !npmCommand) {
  throw new Error("Missing launcher arguments.");
}

const installBase = path.resolve(installBaseArgument);
const dshBase = path.join(installBase, "dsh");
const currentFile = path.join(installBase, "dsh-current");
const lastCheckFile = path.join(installBase, "dsh-last-check");
const skippedFile = path.join(installBase, "dsh-skipped");
const npmIsJavaScript = npmCommand.toLowerCase().endsWith(".js");

const messages = language === "zh"
  ? {
      checking: "正在检查 DeepSeek Harness 更新...",
      installingFirst: "正在安装 DeepSeek Harness {0}。首次启动可能需要几分钟。",
      installingUpdate: "正在安装 DeepSeek Harness {0}...",
      installingProgress: "安装中",
      installComplete: "安装完成，用时 {0}",
      updateAvailable: "发现 DeepSeek Harness 新版本：{0} -> {1}。",
      prompt: "是否立即升级？[y/N] ",
      switched: "已切换到 DeepSeek Harness {0}。",
      skipped: "已跳过 DeepSeek Harness {0}，继续使用 {1}。",
      checkFailed: "无法检查更新，继续使用 DeepSeek Harness {0}。",
      installFailed: "无法安装 DeepSeek Harness {0}，继续使用当前版本。",
      initialInstallFailed: "无法安装 DeepSeek Harness {0}。",
      cleanedVersions: "已清理旧版 DeepSeek Harness：{0}。",
      cleanupFailed: "部分旧版 DeepSeek Harness 无法清理，将继续启动。",
      lookupFailed: "无法获取 DeepSeek Harness 最新版本。",
      currentInvalid: "受管的 DeepSeek Harness 安装无效。",
      usingDsh: "正在使用 DeepSeek Harness {0}。",
      keepOpen: "使用期间请保持此窗口打开。按 Ctrl+C 可停止。",
      browserOpened: "DSH 已就绪，正在打开：{0}",
      browserOpenFailed: "DSH 已就绪，请手动打开：{0}",
    }
  : {
      checking: "Checking for DeepSeek Harness updates...",
      installingFirst: "Installing DeepSeek Harness {0}. The first launch may take several minutes.",
      installingUpdate: "Installing DeepSeek Harness {0}...",
      installingProgress: "Installing",
      installComplete: "Installation complete in {0}",
      updateAvailable: "A DeepSeek Harness update is available: {0} -> {1}.",
      prompt: "Install this update now? [y/N] ",
      switched: "Switched to DeepSeek Harness {0}.",
      skipped: "Skipping DeepSeek Harness {0}; continuing with {1}.",
      checkFailed: "Could not check for updates. Continuing with DeepSeek Harness {0}.",
      installFailed: "Could not install DeepSeek Harness {0}; the current version was kept.",
      initialInstallFailed: "Could not install DeepSeek Harness {0}.",
      cleanedVersions: "Removed old DeepSeek Harness versions: {0}.",
      cleanupFailed: "Some old DeepSeek Harness versions could not be removed; continuing startup.",
      lookupFailed: "Could not determine the latest DeepSeek Harness version.",
      currentInvalid: "The managed DeepSeek Harness installation is invalid.",
      usingDsh: "Using DeepSeek Harness {0}.",
      keepOpen: "Keep this window open. Press Ctrl+C to stop.",
      browserOpened: "DSH is ready. Opening: {0}",
      browserOpenFailed: "DSH is ready. Open this URL manually: {0}",
    };

function format(message, ...values) {
  return values.reduce(
    (result, value, index) => result.replace("{" + index + "}", String(value)),
    message,
  );
}

function log(message) {
  process.stderr.write("\n[dsh] " + message + "\n");
}

function isVersion(value) {
  return typeof value === "string" && VERSION_PATTERN.test(value);
}

function isInside(parent, child) {
  const relative = path.relative(path.resolve(parent), path.resolve(child));
  return relative !== "" && relative !== ".." &&
    !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function validateInstallation(directory, expectedVersion) {
  try {
    const resolvedDirectory = path.resolve(directory);
    const packageRoot = path.join(resolvedDirectory, "node_modules", "@deepseek-ai", "dsh");
    const packageJson = readJson(path.join(packageRoot, "package.json"));
    const lock = readJson(path.join(resolvedDirectory, "package-lock.json"));
    const lockedPackage = lock.packages?.["node_modules/@deepseek-ai/dsh"];
    const entry = typeof packageJson.bin === "string" ? packageJson.bin : packageJson.bin?.dsh;
    const entrypoint = path.resolve(packageRoot, entry || "");

    if (
      packageJson.name !== DSH_PACKAGE ||
      !isVersion(packageJson.version) ||
      (expectedVersion && packageJson.version !== expectedVersion) ||
      !Number.isInteger(lock.lockfileVersion) ||
      lockedPackage?.version !== packageJson.version ||
      !entry ||
      !isInside(packageRoot, entrypoint) ||
      !fs.statSync(entrypoint).isFile()
    ) {
      return null;
    }

    return {
      path: resolvedDirectory,
      version: packageJson.version,
      entrypoint,
    };
  } catch {
    return null;
  }
}

function validateExecutable(installation) {
  const result = spawnSync(process.execPath, [installation.entrypoint, "--version"], {
    encoding: "utf8",
    timeout: 10000,
    windowsHide: true,
  });
  return result.status === 0 && result.stdout.trim() === installation.version;
}

function readCurrent() {
  if (!fs.existsSync(currentFile)) {
    return null;
  }

  const directory = fs.readFileSync(currentFile, "utf8").trim();
  const resolvedDirectory = path.resolve(directory);
  const expectedVersion = path.basename(resolvedDirectory);
  if (
    path.dirname(resolvedDirectory) !== path.resolve(dshBase) ||
    !isVersion(expectedVersion)
  ) {
    throw new Error(messages.currentInvalid);
  }

  const installation = validateInstallation(resolvedDirectory, expectedVersion);
  if (!installation) {
    throw new Error(messages.currentInvalid);
  }
  return installation;
}

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporaryFile = file + "." + randomUUID() + ".tmp";
  try {
    fs.writeFileSync(temporaryFile, value, "utf8");
    fs.renameSync(temporaryFile, file);
  } finally {
    fs.rmSync(temporaryFile, { force: true });
  }
}

function setCurrent(installation) {
  writeAtomic(currentFile, installation.path + "\n");
}

function npmInvocation(args) {
  return npmIsJavaScript
    ? { command: process.execPath, args: [npmCommand, ...args] }
    : { command: npmCommand, args };
}

function runNpm(args, options) {
  const invocation = npmInvocation(args);
  return spawnSync(invocation.command, invocation.args, {
    windowsHide: true,
    ...options,
  });
}

function formatDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return minutes + ":" + seconds;
}

function startInstallProgress() {
  if (!process.stderr.isTTY) {
    return { stop() {} };
  }

  const width = 24;
  const segmentWidth = 6;
  const maxPosition = width - segmentWidth;
  const startedAt = Date.now();
  let tick = 0;

  const render = () => {
    const cyclePosition = tick % (maxPosition * 2);
    const position = cyclePosition <= maxPosition
      ? cyclePosition
      : maxPosition * 2 - cyclePosition;
    const cells = Array(width).fill(" ");
    for (let index = 0; index < segmentWidth; index += 1) {
      cells[position + index] = "=";
    }
    process.stderr.write(
      "\r\u001b[2K[dsh] " + messages.installingProgress + " [" +
      cells.join("") + "] " + formatDuration(Date.now() - startedAt),
    );
    tick += 1;
  };

  render();
  const timer = setInterval(render, 250);
  timer.unref();

  return {
    stop(succeeded) {
      clearInterval(timer);
      process.stderr.write("\r\u001b[2K");
      if (succeeded) {
        process.stderr.write(
          "[dsh] [" + "=".repeat(width) + "] " +
          format(messages.installComplete, formatDuration(Date.now() - startedAt)) + "\n",
        );
      }
    },
  };
}

function runNpmInstall(args) {
  const invocation = npmInvocation(args);
  const progress = startInstallProgress();
  return new Promise((resolve, reject) => {
    let output = "";
    const child = spawn(invocation.command, invocation.args, {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    const capture = (chunk) => {
      output = (output + chunk.toString("utf8")).slice(-65536);
    };
    child.stdout.on("data", capture);
    child.stderr.on("data", capture);
    child.once("error", (error) => {
      progress.stop(false);
      reject(error);
    });
    child.once("exit", (code, signal) => {
      const succeeded = code === 0;
      progress.stop(succeeded);
      if (!succeeded && output.trim()) {
        process.stderr.write(output.trimEnd() + "\n");
      }
      resolve({ status: code, signal });
    });
  });
}

function getLatestVersion() {
  const result = runNpm(
    [
      "view",
      DSH_PACKAGE,
      "version",
      "--fetch-retries=0",
      "--fetch-timeout=5000",
    ],
    { encoding: "utf8", timeout: 10000 },
  );
  const version = result.status === 0 ? result.stdout.trim() : "";
  if (!isVersion(version)) {
    throw new Error(messages.lookupFailed);
  }
  return version;
}

function updateDue() {
  try {
    const lastCheck = Number.parseInt(fs.readFileSync(lastCheckFile, "utf8").trim(), 10);
    return !Number.isFinite(lastCheck) ||
      Math.floor(Date.now() / 1000) - lastCheck >= UPDATE_INTERVAL_SECONDS;
  } catch {
    return true;
  }
}

function setLastCheck() {
  writeAtomic(lastCheckFile, String(Math.floor(Date.now() / 1000)) + "\n");
}

function readSkippedVersion() {
  try {
    const version = fs.readFileSync(skippedFile, "utf8").trim();
    return isVersion(version) ? version : null;
  } catch {
    return null;
  }
}

async function installVersion(version) {
  const target = path.join(dshBase, version);
  if (fs.existsSync(target)) {
    const existing = validateInstallation(target, version);
    if (!existing || !validateExecutable(existing)) {
      throw new Error(format(messages.initialInstallFailed, version));
    }
    return existing;
  }

  fs.mkdirSync(dshBase, { recursive: true });
  const staging = path.join(dshBase, ".staging-" + randomUUID());
  try {
    const result = await runNpmInstall([
      "install",
      "--prefix",
      staging,
      "--save-exact",
      "--package-lock=true",
      "--no-audit",
      "--no-fund",
      "--prefer-offline",
      DSH_PACKAGE + "@" + version,
    ]);
    if (result.status !== 0) {
      throw new Error("npm exited with code " + result.status);
    }

    const staged = validateInstallation(staging, version);
    if (!staged || !validateExecutable(staged)) {
      throw new Error("Installed package validation failed.");
    }
    fs.renameSync(staging, target);

    const installed = validateInstallation(target, version);
    if (!installed) {
      throw new Error("Installed package validation failed.");
    }
    return installed;
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}

function pathKey(value) {
  const resolved = path.resolve(value);
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

function cleanupOldVersions(keepInstallations) {
  const keepPaths = new Set(keepInstallations.map((installation) => pathKey(installation.path)));
  const removed = [];
  let failed = false;
  let entries;

  try {
    entries = fs.readdirSync(dshBase, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (!entry.isDirectory() || !isVersion(entry.name)) {
      continue;
    }

    const directory = path.join(dshBase, entry.name);
    if (keepPaths.has(pathKey(directory))) {
      continue;
    }

    try {
      fs.rmSync(directory, { recursive: true, force: true });
      removed.push(entry.name);
    } catch {
      failed = true;
    }
  }

  if (removed.length > 0) {
    log(format(messages.cleanedVersions, removed.join(", ")));
  }
  if (failed) {
    log(messages.cleanupFailed);
  }
}

async function confirmUpgrade() {
  if (!process.stdin.isTTY) {
    return false;
  }

  const prompt = createInterface({ input: process.stdin, output: process.stderr });
  try {
    const answer = await prompt.question(messages.prompt);
    return /^(y|yes|是)$/i.test(answer.trim());
  } finally {
    prompt.close();
  }
}

function findReadyUrl(output) {
  const plainOutput = output.replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "");
  const match = plainOutput.match(/dsh\s+web:\s*(https?:\/\/[^\s]+)/i);
  if (!match) {
    return null;
  }
  try {
    return new URL(match[1]).href;
  } catch {
    return null;
  }
}

function openBrowser(url) {
  if (process.env.DSH_LAUNCHER_NO_BROWSER === "1") {
    return Promise.resolve(true);
  }

  let command;
  let args;
  if (process.platform === "win32") {
    command = "rundll32.exe";
    args = ["url.dll,FileProtocolHandler", url];
  } else if (process.platform === "darwin") {
    command = "open";
    args = [url];
  } else {
    command = "xdg-open";
    args = [url];
  }

  return new Promise((resolve) => {
    const opener = spawn(command, args, {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    });
    opener.once("error", () => resolve(false));
    opener.once("spawn", () => {
      opener.unref();
      resolve(true);
    });
  });
}

function runDsh(installation, args) {
  log(format(messages.usingDsh, installation.version));
  log(messages.keepOpen);

  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [installation.entrypoint, "web", ...args],
      {
        cwd: process.cwd(),
        env: process.env,
        stdio: ["inherit", "pipe", "pipe"],
        windowsHide: false,
      },
    );
    const detectionBuffers = { stdout: "", stderr: "" };
    let browserStarted = false;
    let browserPromise = Promise.resolve();

    const inspectReadyLine = (line) => {
      if (browserStarted) {
        return;
      }
      const url = findReadyUrl(line);
      if (!url) {
        return;
      }

      browserStarted = true;
      browserPromise = openBrowser(url).then((opened) => {
        log(format(opened ? messages.browserOpened : messages.browserOpenFailed, url));
      });
    };

    const relay = (chunk, destination, stream) => {
      destination.write(chunk);
      if (browserStarted) {
        return;
      }

      const lines = (detectionBuffers[stream] + chunk.toString("utf8")).split(/\r\n|\r|\n/);
      detectionBuffers[stream] = lines.pop().slice(-8192);
      for (const line of lines) {
        inspectReadyLine(line);
      }
    };

    child.stdout.on("data", (chunk) => relay(chunk, process.stdout, "stdout"));
    child.stderr.on("data", (chunk) => relay(chunk, process.stderr, "stderr"));
    child.once("error", reject);
    child.once("exit", async (code, signal) => {
      inspectReadyLine(detectionBuffers.stdout);
      inspectReadyLine(detectionBuffers.stderr);
      await browserPromise;
      if (typeof code === "number") {
        resolve(code);
      } else if (signal === "SIGINT") {
        resolve(130);
      } else if (signal === "SIGTERM") {
        resolve(143);
      } else {
        resolve(1);
      }
    });
  });
}

async function ensureInstallation() {
  let current = readCurrent();
  if (!current) {
    log(messages.checking);
    const latest = getLatestVersion();
    setLastCheck();
    log(format(messages.installingFirst, latest));
    try {
      current = await installVersion(latest);
    } catch {
      throw new Error(format(messages.initialInstallFailed, latest));
    }
    setCurrent(current);
    cleanupOldVersions([current]);
    return current;
  }

  if (!updateDue()) {
    return current;
  }

  log(messages.checking);
  let latest;
  try {
    latest = getLatestVersion();
  } catch {
    setLastCheck();
    log(format(messages.checkFailed, current.version));
    return current;
  }
  setLastCheck();

  if (latest === current.version) {
    fs.rmSync(skippedFile, { force: true });
    return current;
  }

  if (readSkippedVersion() === latest) {
    log(format(messages.skipped, latest, current.version));
    return current;
  }

  log(format(messages.updateAvailable, current.version, latest));
  if (!await confirmUpgrade()) {
    writeAtomic(skippedFile, latest + "\n");
    log(format(messages.skipped, latest, current.version));
    return current;
  }

  log(format(messages.installingUpdate, latest));
  try {
    const updated = await installVersion(latest);
    setCurrent(updated);
    cleanupOldVersions([updated, current]);
    fs.rmSync(skippedFile, { force: true });
    log(format(messages.switched, updated.version));
    return updated;
  } catch {
    log(format(messages.installFailed, latest));
    return current;
  }
}

try {
  const current = await ensureInstallation();
  if (mode === "--run") {
    process.exitCode = await runDsh(current, dshArguments);
  } else {
    process.stdout.write(JSON.stringify(current) + "\n");
  }
} catch (error) {
  process.stderr.write("\n[dsh] " + error.message + "\n");
  process.exitCode = 1;
}
