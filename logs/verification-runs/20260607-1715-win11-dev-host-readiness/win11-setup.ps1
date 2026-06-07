$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$FlutterRevision = "924134a44c"
$FlutterDir = "C:\src\flutter"
$RepoDir = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$CommandLineToolsZip = "https://dl.google.com/android/repository/commandlinetools-win-14742923_latest.zip"
$CommandLineToolsRoot = Join-Path $AndroidSdk "cmdline-tools"
$CommandLineToolsLatest = Join-Path $CommandLineToolsRoot "latest"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

function Run-Step($Name, [scriptblock]$Block) {
  Section $Name
  & $Block
}

function Add-UserPath($PathToAdd) {
  if (-not (Test-Path $PathToAdd)) {
    Write-Output "path-missing=$PathToAdd"
    return
  }

  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = @()
  if ($current) {
    $parts = $current -split ";" | Where-Object { $_ }
  }
  if ($parts -notcontains $PathToAdd) {
    $newValue = (@($PathToAdd) + $parts) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newValue, "User")
    Write-Output "added-user-path=$PathToAdd"
  } else {
    Write-Output "user-path-present=$PathToAdd"
  }
}

function Add-ProcessPath($PathToAdd) {
  if ((Test-Path $PathToAdd) -and (($env:PATH -split ";") -notcontains $PathToAdd)) {
    $env:PATH = "$PathToAdd;$env:PATH"
  }
}

Run-Step "identity" {
  Write-Output "host=$(hostname)"
  Write-Output "user=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Write-Output "admin-token=$isAdmin"
}

Run-Step "flutter 3.44.1" {
  New-Item -ItemType Directory -Force -Path (Split-Path $FlutterDir) | Out-Null
  if (Test-Path (Join-Path $FlutterDir ".git")) {
    git -C $FlutterDir remote set-url origin "https://github.com/flutter/flutter.git"
    git -C $FlutterDir fetch --tags --prune origin
  } else {
    if (Test-Path $FlutterDir) {
      Rename-Item $FlutterDir "$FlutterDir.old.$(Get-Date -Format yyyyMMddHHmmss)"
    }
    git clone "https://github.com/flutter/flutter.git" $FlutterDir
  }
  git -C $FlutterDir checkout $FlutterRevision
  git -C $FlutterDir reset --hard $FlutterRevision
  Add-ProcessPath (Join-Path $FlutterDir "bin")
  Add-UserPath (Join-Path $FlutterDir "bin")
  flutter --version
}

Run-Step "java 17" {
  if (Test-Path (Join-Path $JbrHome "bin\java.exe")) {
    $env:JAVA_HOME = $JbrHome
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JbrHome, "User")
    Add-ProcessPath (Join-Path $JbrHome "bin")
    Add-UserPath (Join-Path $JbrHome "bin")
    & (Join-Path $JbrHome "bin\java.exe") -version
  } else {
    Write-Output "BLOCKER: existing Android Studio JBR not found at $JbrHome"
    Write-Output "BLOCKER: install JDK 17 manually or provide an admin/elevated install path"
  }
}

Run-Step "android command line tools" {
  New-Item -ItemType Directory -Force -Path $CommandLineToolsRoot | Out-Null
  $sdkManager = Join-Path $CommandLineToolsLatest "bin\sdkmanager.bat"
  if (-not (Test-Path $sdkManager)) {
    $zipPath = Join-Path $env:TEMP "commandlinetools-win-latest.zip"
    $extractRoot = Join-Path $env:TEMP "android-commandlinetools"
    Remove-Item -Recurse -Force $extractRoot -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $CommandLineToolsZip -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    Remove-Item -Recurse -Force $CommandLineToolsLatest -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $CommandLineToolsLatest | Out-Null
    Copy-Item -Recurse -Force (Join-Path $extractRoot "cmdline-tools\*") $CommandLineToolsLatest
  }

  $env:ANDROID_HOME = $AndroidSdk
  $env:ANDROID_SDK_ROOT = $AndroidSdk
  [Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidSdk, "User")
  [Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidSdk, "User")
  Add-ProcessPath (Join-Path $AndroidSdk "platform-tools")
  Add-ProcessPath (Join-Path $CommandLineToolsLatest "bin")
  Add-UserPath (Join-Path $AndroidSdk "platform-tools")
  Add-UserPath (Join-Path $AndroidSdk "emulator")
  Add-UserPath (Join-Path $CommandLineToolsLatest "bin")

  & $sdkManager --version
}

Run-Step "android sdk packages" {
  $sdkManager = Join-Path $CommandLineToolsLatest "bin\sdkmanager.bat"
  $packages = @(
    "cmdline-tools;latest",
    "platform-tools",
    "emulator",
    "platforms;android-36",
    "build-tools;35.0.0",
    "ndk;28.2.13676358"
  )
  & $sdkManager --sdk_root=$AndroidSdk @packages
  cmd /c "for /l %i in (1,1,100) do @echo y" | & $sdkManager --sdk_root=$AndroidSdk --licenses
}

Run-Step "flutter config" {
  flutter config --enable-windows-desktop
  flutter doctor -v
}

Run-Step "wsl setup" {
  wsl --update
  wsl --set-default Ubuntu-22.04
  wsl -l -v
}

Run-Step "wsl linux dependencies" {
  wsl -d Ubuntu-22.04 -u root -- bash -lc "apt-get update && apt-get install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev usbutils v4l-utils"
}

Run-Step "wsl flutter" {
  $linuxCommand = @'
set -euo pipefail
mkdir -p "$HOME/development"
if [ -d "$HOME/development/flutter/.git" ]; then
  git -C "$HOME/development/flutter" remote set-url origin https://github.com/flutter/flutter.git
  git -C "$HOME/development/flutter" fetch --tags --prune origin
else
  git clone https://github.com/flutter/flutter.git "$HOME/development/flutter"
fi
git -C "$HOME/development/flutter" checkout 924134a44c
git -C "$HOME/development/flutter" reset --hard 924134a44c
grep -F 'export PATH="$HOME/development/flutter/bin:$PATH"' "$HOME/.bashrc" >/dev/null 2>&1 || echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/development/flutter/bin:$PATH"
flutter config --enable-linux-desktop
flutter --version
'@
  wsl -d Ubuntu-22.04 -- bash -lc $linuxCommand
}

Run-Step "usbipd-win" {
  if (Get-Command usbipd -ErrorAction SilentlyContinue) {
    usbipd --version
  } else {
    Write-Output "Attempting noninteractive winget install for usbipd-win."
    winget install --id dorssel.usbipd-win --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
    if (Get-Command usbipd -ErrorAction SilentlyContinue) {
      usbipd --version
    } else {
      Write-Output "BLOCKER: usbipd-win still missing. This installer commonly requires an elevated/admin session."
    }
  }
}

Run-Step "final versions" {
  flutter --version
  java -version
  adb version
  sdkmanager --version
  wsl --status
  git --version
}
