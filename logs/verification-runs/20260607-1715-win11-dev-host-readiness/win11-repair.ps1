$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$FlutterRevision = "924134a44c"
$FlutterDir = "C:\src\flutter"
$RepoDir = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$CommandLineToolsZip = "https://dl.google.com/android/repository/commandlinetools-win-14742923_latest.zip"
$CommandLineToolsRoot = Join-Path $AndroidSdk "cmdline-tools"
$CommandLineToolsLatest = Join-Path $CommandLineToolsRoot "latest"
$SdkManager = Join-Path $CommandLineToolsLatest "bin\sdkmanager.bat"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

function Add-ProcessPath($PathToAdd) {
  if ((Test-Path $PathToAdd) -and (($env:PATH -split ";") -notcontains $PathToAdd)) {
    $env:PATH = "$PathToAdd;$env:PATH"
  }
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
    [Environment]::SetEnvironmentVariable("Path", ((@($PathToAdd) + $parts) -join ";"), "User")
    Write-Output "added-user-path=$PathToAdd"
  } else {
    Write-Output "user-path-present=$PathToAdd"
  }
}

function Test-AdminToken {
  return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )
}

function Quote-CmdArg($Value) {
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-CmdPipeYes($Name, [string[]]$Arguments, [int]$TimeoutSeconds) {
  Section $Name
  $stdout = Join-Path $env:TEMP ("hydracam-sdkmanager-" + [guid]::NewGuid().ToString() + ".out.txt")
  $stderr = Join-Path $env:TEMP ("hydracam-sdkmanager-" + [guid]::NewGuid().ToString() + ".err.txt")
  $command = "(for /l %i in (1,1,400) do @echo y) | " + (Quote-CmdArg $SdkManager) + " " + (($Arguments | ForEach-Object { Quote-CmdArg $_ }) -join " ")

  Write-Output "command=$command"
  $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $command) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Write-Output "BLOCKER: timed out after ${TimeoutSeconds}s: $Name"
    return $false
  }

  if (Test-Path $stdout) {
    Get-Content $stdout
  }
  if (Test-Path $stderr) {
    Get-Content $stderr
  }
  Remove-Item -Force $stdout, $stderr -ErrorAction SilentlyContinue

  if ($process.ExitCode -ne 0) {
    Write-Output "BLOCKER: exit-code=$($process.ExitCode): $Name"
    return $false
  }
  return $true
}

Section "identity"
Write-Output "host=$(hostname)"
Write-Output "user=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Output "admin-token=$(Test-AdminToken)"
Write-Output "windows-version=$((Get-CimInstance Win32_OperatingSystem).Version)"
Write-Output "windows-caption=$((Get-CimInstance Win32_OperatingSystem).Caption)"

Section "flutter"
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
git -C $FlutterDir checkout -B stable $FlutterRevision
git -C $FlutterDir reset --hard $FlutterRevision
git -C $FlutterDir branch --set-upstream-to=origin/stable stable 2>$null
Add-ProcessPath (Join-Path $FlutterDir "bin")
Add-UserPath (Join-Path $FlutterDir "bin")
flutter --version

Section "java"
if (Test-Path (Join-Path $JbrHome "bin\java.exe")) {
  $env:JAVA_HOME = $JbrHome
  [Environment]::SetEnvironmentVariable("JAVA_HOME", $JbrHome, "User")
  Add-ProcessPath (Join-Path $JbrHome "bin")
  Add-UserPath (Join-Path $JbrHome "bin")
  & (Join-Path $JbrHome "bin\java.exe") -version
} else {
  Write-Output "BLOCKER: Java 17 JBR not found at $JbrHome"
}

Section "android-command-line-tools"
New-Item -ItemType Directory -Force -Path $CommandLineToolsRoot | Out-Null
if (-not (Test-Path $SdkManager)) {
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
Add-ProcessPath (Join-Path $AndroidSdk "emulator")
Add-ProcessPath (Join-Path $CommandLineToolsLatest "bin")
Add-UserPath (Join-Path $AndroidSdk "platform-tools")
Add-UserPath (Join-Path $AndroidSdk "emulator")
Add-UserPath (Join-Path $CommandLineToolsLatest "bin")
& $SdkManager --version

$sdkArgs = @(
  "--sdk_root=$AndroidSdk",
  "cmdline-tools;latest",
  "platform-tools",
  "emulator",
  "platforms;android-36",
  "build-tools;35.0.0",
  "ndk;28.2.13676358"
)
[void](Invoke-CmdPipeYes "android-licenses-before-install" @("--sdk_root=$AndroidSdk", "--licenses") 600)
[void](Invoke-CmdPipeYes "android-sdk-package-install" $sdkArgs 1800)
[void](Invoke-CmdPipeYes "android-licenses-after-install" @("--sdk_root=$AndroidSdk", "--licenses") 600)

Section "visual-studio-and-code"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  & $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
} else {
  Write-Output "BLOCKER: vswhere not found"
}
if (Get-Command code -ErrorAction SilentlyContinue) {
  code --version
} else {
  Write-Output "BLOCKER: code command not found"
}
$wingetCode = winget list --id Microsoft.VisualStudioCode --exact 2>&1
Write-Output $wingetCode
if (($LASTEXITCODE -ne 0) -and (Test-AdminToken)) {
  winget install --id Microsoft.VisualStudioCode --exact --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity
} elseif ($LASTEXITCODE -ne 0) {
  Write-Output "BLOCKER: Microsoft.VisualStudioCode not listed by winget and current token is not elevated; install may still be possible interactively."
}

Section "usbipd"
if (Get-Command usbipd -ErrorAction SilentlyContinue) {
  usbipd --version
} elseif (Test-AdminToken) {
  winget install --id dorssel.usbipd-win --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
  if (Get-Command usbipd -ErrorAction SilentlyContinue) {
    usbipd --version
  } else {
    Write-Output "BLOCKER: usbipd-win install did not expose usbipd on PATH"
  }
} else {
  Write-Output "BLOCKER: usbipd-win missing and current SSH token is not elevated; install requires an admin session."
}

Section "hydracam-checkout"
New-Item -ItemType Directory -Force -Path (Split-Path $RepoDir) | Out-Null
if (Test-Path (Join-Path $RepoDir ".git")) {
  git -C $RepoDir status -sb
  git -C $RepoDir remote -v
} else {
  git clone "https://github.com/KeepEyeOnBall-Jose/hydracamv2.git" $RepoDir
  git -C $RepoDir status -sb
}

Section "final-version-snapshot"
flutter --version
& (Join-Path $JbrHome "bin\java.exe") -version
adb version
& $SdkManager --sdk_root=$AndroidSdk --list_installed
Write-Output "wsl-status-deferred-to-dedicated-validation"
git --version
pwsh --version
