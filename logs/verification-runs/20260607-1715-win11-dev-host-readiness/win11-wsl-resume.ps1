$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

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

Run-Step "wsl list" {
  wsl -l -v
}

Run-Step "wsl repair interrupted package state" {
  wsl -d Ubuntu-22.04 -u root -- bash -lc "export DEBIAN_FRONTEND=noninteractive; dpkg --configure -a"
}

Run-Step "wsl install linux desktop deps" {
  wsl -d Ubuntu-22.04 -u root -- bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev usbutils v4l-utils"
}

Run-Step "wsl usb tools smoke" {
  wsl -d Ubuntu-22.04 -- bash -lc "command -v lsusb; lsusb; command -v v4l2-ctl; v4l2-ctl --list-devices || true"
}

Run-Step "wsl flutter version" {
  wsl -d Ubuntu-22.04 -- bash -lc "set -e; mkdir -p \$HOME/development; if [ ! -d \$HOME/development/flutter/.git ]; then git clone --depth 1 --branch stable https://github.com/flutter/flutter.git \$HOME/development/flutter; fi; export PATH=\$HOME/development/flutter/bin:\$PATH; flutter --version"
}

Run-Step "wsl flutter doctor" {
  wsl -d Ubuntu-22.04 -- bash -lc "set -e; export PATH=\$HOME/development/flutter/bin:\$PATH; flutter config --enable-linux-desktop; flutter doctor -v"
}
