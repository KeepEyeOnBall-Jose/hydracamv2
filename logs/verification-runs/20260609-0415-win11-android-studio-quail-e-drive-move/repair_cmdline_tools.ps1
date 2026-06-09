$ErrorActionPreference = "Stop"

$Root = "D:\hydracam-evidence\20260609-0415-win11-android-studio-quail-e-drive-move"
$SdkRoot = "C:\Users\jose\AppData\Local\Android\Sdk"
$CmdlineRoot = Join-Path $SdkRoot "cmdline-tools"
$Latest = Join-Path $CmdlineRoot "latest"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = Join-Path $CmdlineRoot "latest-9.0-backup-$Stamp"
$OutDir = Join-Path $Root "cmdline-tools-repair"
$ZipPath = Join-Path $OutDir "commandlinetools-win-14742923_latest.zip"
$ExtractDir = "C:\Temp\android-cmdline-tools-$Stamp"
$Url = "https://dl.google.com/android/repository/commandlinetools-win-14742923_latest.zip"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null
Remove-Item -LiteralPath $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue

Get-Process studio64, studio, java, javaw -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $ZipPath) -or
    (Get-Item -LiteralPath $ZipPath).Length -lt 100MB) {
  Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
  & curl.exe -L --fail --retry 3 --retry-delay 2 -o $ZipPath $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl failed to download command-line tools from $Url"
  }
}
if ((Get-Item -LiteralPath $ZipPath).Length -lt 100MB) {
  throw "Downloaded command-line tools zip is unexpectedly small: $((Get-Item -LiteralPath $ZipPath).Length) bytes"
}

Remove-Item -LiteralPath $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
& tar.exe -xf $ZipPath -C $ExtractDir
if ($LASTEXITCODE -ne 0) {
  throw "tar.exe failed to extract command-line tools zip"
}
$ExtractedTools = Join-Path $ExtractDir "cmdline-tools"
if (-not (Test-Path -LiteralPath (Join-Path $ExtractedTools "bin\sdkmanager.bat"))) {
  throw "Downloaded command-line tools zip did not contain cmdline-tools\bin\sdkmanager.bat"
}

if (Test-Path -LiteralPath $Latest) {
  Move-Item -LiteralPath $Latest -Destination $Backup
}
Move-Item -LiteralPath $ExtractedTools -Destination $Latest

$SdkManager = Join-Path $Latest "bin\sdkmanager.bat"
$Version = (& $SdkManager --version 2>&1 | Out-String).Trim()
$ListInstalled = (& $SdkManager --sdk_root=$SdkRoot --list_installed 2>&1 | Out-String)
$Highlights = $ListInstalled -split "`r?`n" |
  Where-Object {
    $_ -match "cmdline-tools;latest" -or
    $_ -match "build-tools;36\.1\.0" -or
    $_ -match "platform-tools" -or
    $_ -match "emulator" -or
    $_ -match "platforms;android-36"
  }

$Summary = [ordered]@{
  status = "passed"
  url = $Url
  zipPath = $ZipPath
  sdkRoot = $SdkRoot
  backup = $Backup
  sdkmanagerVersion = $Version
  latestSdkmanager = $SdkManager
  highlights = $Highlights
  endedAt = (Get-Date).ToString("o")
}
$Summary | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath (Join-Path $OutDir "summary.json") -Encoding utf8
Get-Content -LiteralPath (Join-Path $OutDir "summary.json") -Raw
