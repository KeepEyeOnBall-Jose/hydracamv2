$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$Flutter = "C:\src\flutter\bin\flutter.bat"
$SdkManager = Join-Path $AndroidSdk "cmdline-tools\latest\bin\sdkmanager.bat"

$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PATH = (Join-Path "C:\src\flutter" "bin") + ";" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
  (Join-Path $AndroidSdk "emulator") + ";" +
  (Join-Path $AndroidSdk "cmdline-tools\latest\bin") + ";" +
  $env:PATH

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

Section "sdkmanager-licenses"
if (Test-Path $SdkManager) {
  $yesAnswers = 1..200 | ForEach-Object { "y" }
  $yesAnswers | & $SdkManager --sdk_root=$AndroidSdk --licenses
  Write-Output "[sdkmanager-exit-code] $LASTEXITCODE"
} else {
  Write-Output "BLOCKER: sdkmanager missing at $SdkManager"
}

Section "flutter-doctor-after-licenses"
& $Flutter doctor -v
Write-Output "[flutter-doctor-exit-code] $LASTEXITCODE"
exit 0
