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
        default { throw "Unsupported CPU architecture: $architecture" }
    }

    $baseUrl = "https://nodejs.org/dist/latest-v24.x"
    Write-DshLog "Finding the latest Node.js 24 release for win-$nodeArchitecture..."
    $checksums = (Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHASUMS256.txt").Content
    $pattern = "(?m)^(?<hash>[a-f0-9]{64})\s+(?<file>node-v[^\s]+-win-$nodeArchitecture\.zip)$"
    $match = [regex]::Match($checksums, $pattern)
    if (-not $match.Success) {
        throw "Could not find a compatible Node.js download."
    }

    $fileName = $match.Groups["file"].Value
    $expectedHash = $match.Groups["hash"].Value
    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ("dsh-launcher-" + [guid]::NewGuid())
    $archive = Join-Path $tempDirectory $fileName

    New-Item -ItemType Directory -Path $tempDirectory | Out-Null
    try {
        Write-DshLog "Downloading $fileName..."
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$fileName" -OutFile $archive

        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Node.js checksum verification failed."
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
        Write-DshLog "Node.js is missing or incompatible. Installing a private copy..."
        Install-LocalNode
    }

    if (-not (Test-CompatibleNode)) {
        throw "Node.js installation did not produce a compatible runtime."
    }

    $nodeCommand = Get-Command node.exe -ErrorAction Stop
    $npxCommand = Get-Command npx.cmd -ErrorAction Stop
    $nodeVersion = (& $nodeCommand.Source --version)

    Write-DshLog "Using Node.js $nodeVersion."
    Write-DshLog "Starting DeepSeek Harness at http://127.0.0.1:3080"
    Write-DshLog "Keep this window open. Press Ctrl+C to stop."

    & $npxCommand.Source --yes $DshPackage web @DshArguments
    if ($LASTEXITCODE -ne 0) {
        throw "DeepSeek Harness exited with code $LASTEXITCODE."
    }
}
catch {
    Write-Host "`n[dsh] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($PauseOnError) {
        [void](Read-Host "Press Enter to close")
    }
    exit 1
}
