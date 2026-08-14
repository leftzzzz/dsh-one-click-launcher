[CmdletBinding()]
param(
    [switch]$PauseOnError,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DshArguments
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$InstallBase = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "dsh-launcher"
$NodeCurrentFile = Join-Path $InstallBase "node-current.txt"
$LegacyNodeCurrentFile = Join-Path $InstallBase "current.txt"
$DshManagerFile = Join-Path $PSScriptRoot "dsh-manager.mjs"
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
        NpmNotFound = "npm was not found next to Node.js."
        ManagerNotFound = "The DSH manager file is missing."
        ManagerFailed = "DeepSeek Harness setup failed."
        UsingNode = "Using Node.js {0}."
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
        NpmNotFound = "在 Node.js 目录中找不到 npm。"
        ManagerNotFound = "缺少 DSH 管理器文件。"
        ManagerFailed = "DeepSeek Harness 准备失败。"
        UsingNode = "正在使用 Node.js {0}。"
        ErrorLabel = "错误："
        ClosePrompt = "按 Enter 键关闭"
    }
}

function Get-DshText {
    param(
        [string]$Key,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Values
    )

    $text = $DshMessages[$DshLanguage][$Key]
    if ($Values.Count -gt 0) {
        return $text -f $Values
    }
    return $text
}

function Write-DshLog {
    param([string]$Message)
    Write-Host "$([Environment]::NewLine)[dsh] $Message" -ForegroundColor Cyan
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
    $currentFile = if (Test-Path -LiteralPath $NodeCurrentFile -PathType Leaf) {
        $NodeCurrentFile
    }
    elseif (Test-Path -LiteralPath $LegacyNodeCurrentFile -PathType Leaf) {
        $LegacyNodeCurrentFile
    }
    else {
        return $false
    }

    $nodeDirectory = (Get-Content -LiteralPath $currentFile -Encoding UTF8 -TotalCount 1).Trim()
    if (-not (Test-Path -LiteralPath (Join-Path $nodeDirectory "node.exe") -PathType Leaf)) {
        return $false
    }

    if ($currentFile -eq $LegacyNodeCurrentFile) {
        Move-Item -LiteralPath $LegacyNodeCurrentFile -Destination $NodeCurrentFile -Force
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

        Set-Content -LiteralPath $NodeCurrentFile -Value $targetDirectory -Encoding UTF8
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

    if (-not (Test-Path -LiteralPath $DshManagerFile -PathType Leaf)) {
        throw (Get-DshText "ManagerNotFound")
    }

    $nodeCommand = Get-Command node.exe -ErrorAction Stop
    $nodeDirectory = Split-Path -Parent $nodeCommand.Source
    $npmCli = Join-Path $nodeDirectory "node_modules\npm\bin\npm-cli.js"
    if (-not (Test-Path -LiteralPath $npmCli -PathType Leaf)) {
        throw (Get-DshText "NpmNotFound")
    }
    $nodeVersion = (& $nodeCommand.Source --version)
    Write-DshLog (Get-DshText "UsingNode" $nodeVersion)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $nodeCommand.Source $DshManagerFile $InstallBase $DshLanguage $npmCli --run @DshArguments
        $managerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($managerExitCode -notin @(0, 130, -1073741510)) {
        throw (Get-DshText "ManagerFailed")
    }
}
catch {
    Write-Host "$([Environment]::NewLine)[dsh] $(Get-DshText "ErrorLabel")$($_.Exception.Message)" -ForegroundColor Red
    if ($PauseOnError) {
        [void](Read-Host (Get-DshText "ClosePrompt"))
    }
    exit 1
}
