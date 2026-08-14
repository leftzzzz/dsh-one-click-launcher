[CmdletBinding()]
param(
    [switch]$PauseOnError,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DshArguments
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$DshPackage = "@deepseek-ai/dsh@latest"
$InstallBase = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "dsh-launcher"
$CurrentFile = Join-Path $InstallBase "current.txt"
$DshLanguage = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "zh") { "zh" } else { "en" }
$DshMessages = @{
    en = @{
        UnsupportedArchitecture = "Unsupported CPU architecture: {0}"
        FindingNode = "Finding the latest Node.js 24 release for win-{0}..."
        NodeDownloadNotFound = "Could not find a compatible Node.js download."
        Downloading = "Downloading {0}..."
        ChecksumFailed = "Node.js checksum verification failed."
        NodeMissing = "Node.js is missing or incompatible. Installing a private copy..."
        NodeInstallFailed = "Node.js installation did not produce a compatible runtime."
        NpxNotFound = "npx was not found next to Node.js."
        UsingNode = "Using Node.js {0}."
        Preparing = "Preparing DeepSeek Harness. The first launch may take several minutes."
        Ready = "DSH is ready when it prints: dsh web: http://127.0.0.1:3080"
        KeepOpen = "Keep this window open. Press Ctrl+C to stop."
        HarnessExited = "DeepSeek Harness exited with code {0}."
        ErrorLabel = "ERROR: "
        ClosePrompt = "Press Enter to close"
    }
    zh = @{
        UnsupportedArchitecture = "不支持的 CPU 架构：{0}"
        FindingNode = "正在查找适用于 win-{0} 的最新 Node.js 24 版本..."
        NodeDownloadNotFound = "找不到兼容的 Node.js 下载包。"
        Downloading = "正在下载 {0}..."
        ChecksumFailed = "Node.js 校验和验证失败。"
        NodeMissing = "未检测到 Node.js 或版本不兼容，正在安装独立副本..."
        NodeInstallFailed = "Node.js 安装完成后仍未获得兼容的运行时。"
        NpxNotFound = "在 Node.js 目录中找不到 npx。"
        UsingNode = "正在使用 Node.js {0}。"
        Preparing = "正在准备 DeepSeek Harness。首次启动可能需要几分钟。"
        Ready = "当出现以下内容时，DSH 已就绪：dsh web: http://127.0.0.1:3080"
        KeepOpen = "使用期间请保持此窗口打开。按 Ctrl+C 可停止。"
        HarnessExited = "DeepSeek Harness 已退出，退出代码：{0}。"
        ErrorLabel = "错误："
        ClosePrompt = "按 Enter 键关闭"
    }
}

function Get-DshText {
    param(
        [string]$Key,
        [object]$Value
    )

    $text = $DshMessages[$DshLanguage][$Key]
    if ($PSBoundParameters.ContainsKey("Value")) {
        return $text -f $Value
    }
    return $text
}

function Write-DshLog {
    param([string]$Message)
    Write-Host "`n[dsh] $Message" -ForegroundColor Cyan
}

function Test-CompatibleNode {
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        return $false
    }

    $versionText = (& $nodeCommand.Source --version 2>$null)
    if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v(?<major>\d+)\.(?<minor>\d+)\.') {
        return $false
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    return ($major -ge 24) -or ($major -eq 22 -and $minor -ge 19)
}

function Enable-LocalNode {
    if (-not (Test-Path -LiteralPath $CurrentFile -PathType Leaf)) {
        return $false
    }

    $nodeDirectory = (Get-Content -LiteralPath $CurrentFile -Encoding UTF8 -TotalCount 1).Trim()
    if (-not (Test-Path -LiteralPath (Join-Path $nodeDirectory "node.exe") -PathType Leaf)) {
        return $false
    }

    $env:PATH = "$nodeDirectory;$env:PATH"
    return $true
}

function Install-LocalNode {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    switch ($architecture) {
        "X64" { $nodeArchitecture = "x64" }
        "Arm64" { $nodeArchitecture = "arm64" }
        default { throw (Get-DshText "UnsupportedArchitecture" $architecture) }
    }

    $baseUrl = "https://nodejs.org/dist/latest-v24.x"
    Write-DshLog (Get-DshText "FindingNode" $nodeArchitecture)
    $checksums = (Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHASUMS256.txt").Content
    $pattern = "(?m)^(?<hash>[a-f0-9]{64})\s+(?<file>node-v[^\s]+-win-$nodeArchitecture\.zip)$"
    $match = [regex]::Match($checksums, $pattern)
    if (-not $match.Success) {
        throw (Get-DshText "NodeDownloadNotFound")
    }

    $fileName = $match.Groups["file"].Value
    $expectedHash = $match.Groups["hash"].Value
    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ("dsh-launcher-" + [guid]::NewGuid())
    $archive = Join-Path $tempDirectory $fileName

    New-Item -ItemType Directory -Path $tempDirectory | Out-Null
    try {
        Write-DshLog (Get-DshText "Downloading" $fileName)
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$fileName" -OutFile $archive

        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw (Get-DshText "ChecksumFailed")
        }

        Expand-Archive -LiteralPath $archive -DestinationPath $tempDirectory
        $folderName = [IO.Path]::GetFileNameWithoutExtension($fileName)
        $extractedDirectory = Join-Path $tempDirectory $folderName
        $targetDirectory = Join-Path $InstallBase $folderName

        New-Item -ItemType Directory -Path $InstallBase -Force | Out-Null
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            Move-Item -LiteralPath $extractedDirectory -Destination $targetDirectory
        }

        Set-Content -LiteralPath $CurrentFile -Value $targetDirectory -Encoding UTF8
        $env:PATH = "$targetDirectory;$env:PATH"
    }
    finally {
        if (Test-Path -LiteralPath $tempDirectory) {
            Remove-Item -LiteralPath $tempDirectory -Recurse -Force
        }
    }
}

try {
    Set-Location -LiteralPath $PSScriptRoot

    if (-not (Test-CompatibleNode)) {
        [void](Enable-LocalNode)
    }

    if (-not (Test-CompatibleNode)) {
        Write-DshLog (Get-DshText "NodeMissing")
        Install-LocalNode
    }

    if (-not (Test-CompatibleNode)) {
        throw (Get-DshText "NodeInstallFailed")
    }

    $nodeCommand = Get-Command node.exe -ErrorAction Stop
    $nodeDirectory = Split-Path -Parent $nodeCommand.Source
    $npxCli = Join-Path $nodeDirectory "node_modules\npm\bin\npx-cli.js"
    if (-not (Test-Path -LiteralPath $npxCli -PathType Leaf)) {
        throw (Get-DshText "NpxNotFound")
    }
    $nodeVersion = (& $nodeCommand.Source --version)

    Write-DshLog (Get-DshText "UsingNode" $nodeVersion)
    Write-DshLog (Get-DshText "Preparing")
    Write-DshLog (Get-DshText "Ready")
    Write-DshLog (Get-DshText "KeepOpen")

    # Avoid cmd shims so Ctrl+C does not traverse nested batch jobs.
    $powerShell = Join-Path $PSHOME "powershell.exe"
    & $nodeCommand.Source $npxCli --script-shell $powerShell --yes $DshPackage web @DshArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin @(0, 130, -1073741510)) {
        throw (Get-DshText "HarnessExited" $exitCode)
    }
}
catch {
    Write-Host "`n[dsh] $(Get-DshText "ErrorLabel")$($_.Exception.Message)" -ForegroundColor Red
    if ($PauseOnError) {
        [void](Read-Host (Get-DshText "ClosePrompt"))
    }
    exit 1
}
