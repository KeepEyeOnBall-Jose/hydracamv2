$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$Failures = @()

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
    if ($exitCode -ne 0) {
      $script:Failures += "$Name exited $exitCode"
    }
  } catch {
    Write-Output "[step-exception] $($_.Exception.Message)"
    $script:Failures += "$Name exception"
  }
}

Run-Step "wsl list" {
  wsl -l -v
}

Run-Step "wsl set default Ubuntu-22.04" {
  wsl --set-default Ubuntu-22.04
}

Run-Step "wsl linux dependencies" {
  wsl -d Ubuntu-22.04 -u root -- bash -lc "apt-get update && apt-get install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev usbutils v4l-utils"
}

$linuxSetup = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
mkdir -p "$HOME/development" "$HOME/src/work"
if [ -d "$HOME/development/flutter/.git" ]; then
  git -C "$HOME/development/flutter" remote set-url origin https://github.com/flutter/flutter.git
  git -C "$HOME/development/flutter" fetch --tags --prune origin
else
  git clone https://github.com/flutter/flutter.git "$HOME/development/flutter"
fi
git -C "$HOME/development/flutter" checkout -B stable 924134a44c
git -C "$HOME/development/flutter" reset --hard 924134a44c
if [ -d "$HOME/src/work/hydracamv2/.git" ]; then
  git -C "$HOME/src/work/hydracamv2" status -sb
else
  git clone https://github.com/KeepEyeOnBall-Jose/hydracamv2.git "$HOME/src/work/hydracamv2"
fi
grep -F 'export PATH="$HOME/development/flutter/bin:$PATH"' "$HOME/.bashrc" >/dev/null 2>&1 || echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/development/flutter/bin:$PATH"
flutter --version
flutter config --enable-linux-desktop
cd "$HOME/src/work/hydracamv2"
flutter doctor -v
flutter pub get
flutter build linux --debug
'@

Run-Step "wsl flutter linux build" {
  wsl -d Ubuntu-22.04 -- bash -lc $linuxSetup
}

Section "wsl-validation-summary"
if ($Failures.Count -eq 0) {
  Write-Output "result=passed"
  exit 0
}

Write-Output "result=partial"
$Failures | ForEach-Object { Write-Output "failure=$_" }
exit 1
