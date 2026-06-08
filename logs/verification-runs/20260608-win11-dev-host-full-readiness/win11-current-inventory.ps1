$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$EvidenceRoot = "C:\Users\jose\codex-win11-dev-host-full-readiness"
$FlutterRoot = "C:\src\flutter"
$Flutter = Join-Path $FlutterRoot "bin\flutter.bat"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$DRepo = "D:\src\work\hydracamv2"
$CRepo = Join-Path $env:USERPROFILE "src\work\hydracamv2"

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PATH = (Join-Path $FlutterRoot "bin") + ";" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
  (Join-Path $AndroidSdk "emulator") + ";" +
  (Join-Path $AndroidSdk "cmdline-tools\latest\bin") + ";" +
  $env:PATH

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

function Run-Step($Name, [scriptblock]$Block) {
  Section $Name
  $global:LASTEXITCODE = 0
  try {
    & $Block
    $exitCode = $global:LASTEXITCODE
    if ($null -eq $exitCode) {
      $exitCode = 0
    }
    Write-Output "[step-exit-code] $exitCode"
  } catch {
    Write-Output "[step-exception] $($_.Exception.Message)"
  }
}

Section "host"
Write-Output "timestamp=$(Get-Date -Format o)"
Write-Output "hostname=$(hostname)"
Write-Output "whoami=$(whoami)"
Write-Output "os=$((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)"
Write-Output "powershell=$($PSVersionTable.PSVersion)"

Section "drives"
Get-PSDrive -PSProvider FileSystem |
  Sort-Object Name |
  ForEach-Object {
    $usedGiB = [math]::Round($_.Used / 1GB, 2)
    $freeGiB = [math]::Round($_.Free / 1GB, 2)
    $sizeGiB = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
    Write-Output "$($_.Name): used=${usedGiB}GiB free=${freeGiB}GiB size=${sizeGiB}GiB root=$($_.Root)"
  }

Section "developer-mode-and-symlink"
$devMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -ErrorAction SilentlyContinue
if ($devMode) {
  Write-Output "AllowDevelopmentWithoutDevLicense=$($devMode.AllowDevelopmentWithoutDevLicense)"
  Write-Output "AllowAllTrustedApps=$($devMode.AllowAllTrustedApps)"
} else {
  Write-Output "AppModelUnlock registry key not present"
}

$linkTestRoot = Join-Path $env:TEMP "codex-symlink-test"
Remove-Item -Recurse -Force $linkTestRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $linkTestRoot | Out-Null
Set-Content -Path (Join-Path $linkTestRoot "target.txt") -Value "target"
try {
  New-Item -ItemType SymbolicLink -Path (Join-Path $linkTestRoot "link.txt") -Target (Join-Path $linkTestRoot "target.txt") -ErrorAction Stop | Out-Null
  Write-Output "generic-symlink=passed"
} catch {
  Write-Output "generic-symlink=failed"
  Write-Output "generic-symlink-error=$($_.Exception.Message)"
}

Section "wsl"
wsl -l -v

Section "repositories"
foreach ($repo in @($CRepo, $DRepo)) {
  Write-Output "repo=$repo exists=$(Test-Path $repo)"
  if (Test-Path $repo) {
    git -C $repo status -sb --untracked-files=no
    git -C $repo rev-parse HEAD
  }
}

Run-Step "flutter doctor -v" {
  & $Flutter doctor -v
}

Run-Step "flutter devices" {
  & $Flutter devices
}

Run-Step "sdkmanager list_installed" {
  sdkmanager --list_installed
}

Run-Step "avdmanager list avd" {
  avdmanager list avd
}

Run-Step "emulator accel-check" {
  emulator -accel-check
}

Section "done"
