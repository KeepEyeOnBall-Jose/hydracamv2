$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$FlutterDir = "C:\src\flutter"
$RepoDir = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$Flutter = Join-Path $FlutterDir "bin\flutter.bat"
$Failures = @()

$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PATH = (Join-Path $FlutterDir "bin") + ";" +
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
    if ($exitCode -ne 0) {
      $script:Failures += "$Name exited $exitCode"
    }
  } catch {
    Write-Output "[step-exception] $($_.Exception.Message)"
    $script:Failures += "$Name exception"
  }
}

Section "validation-context"
Write-Output "host=$(hostname)"
Write-Output "repo=$RepoDir"
Write-Output "flutter=$Flutter"
if (Test-Path $RepoDir) {
  git -C $RepoDir status -sb
  git -C $RepoDir rev-parse HEAD
} else {
  Write-Output "BLOCKER: repo checkout missing at $RepoDir"
  exit 1
}

Run-Step "flutter doctor -v" {
  & $Flutter doctor -v
}

Run-Step "flutter config --enable-windows-desktop" {
  & $Flutter config --enable-windows-desktop
}

Run-Step "flutter pub get" {
  Push-Location $RepoDir
  & $Flutter pub get
  Pop-Location
}

Run-Step "flutter analyze" {
  Push-Location $RepoDir
  & $Flutter analyze
  Pop-Location
}

Run-Step "flutter test" {
  Push-Location $RepoDir
  & $Flutter test
  Pop-Location
}

Run-Step "flutter build windows --debug" {
  Push-Location $RepoDir
  & $Flutter build windows --debug
  Pop-Location
}

Run-Step "flutter build apk --debug" {
  Push-Location $RepoDir
  & $Flutter build apk --debug
  Pop-Location
}

Run-Step "flutter devices" {
  & $Flutter devices
}

Section "validation-summary"
if ($Failures.Count -eq 0) {
  Write-Output "result=passed"
  exit 0
}

Write-Output "result=partial"
$Failures | ForEach-Object { Write-Output "failure=$_" }
exit 1
