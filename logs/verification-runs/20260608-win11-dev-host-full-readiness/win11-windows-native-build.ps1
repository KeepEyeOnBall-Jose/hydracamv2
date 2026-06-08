$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$EvidenceRoot = "C:\Users\jose\codex-win11-dev-host-full-readiness"
$Repo = "D:\src\work\hydracamv2"
$FlutterRoot = "C:\src\flutter"
$Flutter = Join-Path $FlutterRoot "bin\flutter.bat"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$Failures = @()

New-Item -ItemType Directory -Force -Path $EvidenceRoot, "D:\tmp", "D:\pub-cache", "D:\gradle-cache" | Out-Null

$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PUB_CACHE = "D:\pub-cache"
$env:GRADLE_USER_HOME = "D:\gradle-cache"
$env:TEMP = "D:\tmp"
$env:TMP = "D:\tmp"
$env:PATH = (Join-Path $FlutterRoot "bin") + ";" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
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
    if ($exitCode -ne 0) {
      $script:Failures += "$Name exited $exitCode"
    }
  } catch {
    Write-Output "[step-exception] $($_.Exception.Message)"
    $script:Failures += "$Name exception"
  }
}

Section "context"
Write-Output "timestamp=$(Get-Date -Format o)"
Write-Output "repo=$Repo"
Write-Output "flutter=$Flutter"
Write-Output "pub_cache=$env:PUB_CACHE"
Write-Output "gradle_user_home=$env:GRADLE_USER_HOME"
if (-not (Test-Path $Repo)) {
  Write-Output "BLOCKER: repo checkout missing at $Repo"
  exit 1
}
git -C $Repo status -sb --untracked-files=no
git -C $Repo rev-parse HEAD

Run-Step "flutter config enable windows" {
  & $Flutter config --enable-windows-desktop
}

Run-Step "flutter pub get" {
  Push-Location $Repo
  & $Flutter pub get
  Pop-Location
}

Run-Step "flutter analyze" {
  Push-Location $Repo
  & $Flutter analyze
  Pop-Location
}

Run-Step "inspect plugin symlinks" {
  $pluginLinks = Join-Path $Repo "windows\flutter\ephemeral\.plugin_symlinks"
  if (Test-Path $pluginLinks) {
    Get-ChildItem $pluginLinks -Force | ForEach-Object {
      $target = if ($_.Target -is [array]) { $_.Target -join ";" } else { $_.Target }
      Write-Output "plugin-entry=$($_.Name) linkType=$($_.LinkType) target=$target"
    }
  } else {
    Write-Output "plugin-links-dir-missing=$pluginLinks"
  }
}

Run-Step "flutter build windows debug" {
  Push-Location $Repo
  & $Flutter build windows --debug --no-pub
  Pop-Location
}

Section "windows binary"
$exe = Get-ChildItem -Path (Join-Path $Repo "build\windows") -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "\\runner\\Debug\\" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($exe) {
  Write-Output "exe=$($exe.FullName)"
  Write-Output "exe_size=$($exe.Length)"
  try {
    $process = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
    Start-Sleep -Seconds 10
    Write-Output "started_pid=$($process.Id)"
    Write-Output "has_exited_after_10s=$($process.HasExited)"
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
      Write-Output "stopped_pid=$($process.Id)"
    } else {
      Write-Output "process_exit_code=$($process.ExitCode)"
    }
  } catch {
    Write-Output "launch_exception=$($_.Exception.Message)"
    $Failures += "windows binary launch exception"
  }
} else {
  Write-Output "exe=missing"
  $Failures += "windows binary missing"
}

Section "summary"
if ($Failures.Count -eq 0) {
  Write-Output "result=passed"
  exit 0
}

Write-Output "result=partial"
$Failures | ForEach-Object { Write-Output "failure=$_" }
exit 1
