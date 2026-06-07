$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$FlutterDir = "C:\src\flutter"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$Flutter = Join-Path $FlutterDir "bin\flutter.bat"
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

Section "android-devices"
adb devices -l

Section "flutter-devices"
& $Flutter devices

Section "windows-pnp-camera-usb-android"
Get-PnpDevice -PresentOnly |
  Where-Object {
    $_.Class -match "Camera|Image|Media|USB|Android" -or
    $_.FriendlyName -match "camera|webcam|usb video|android|samsung|xiaomi|google|adb"
  } |
  Select-Object Class, FriendlyName, InstanceId, Status |
  ConvertTo-Csv -NoTypeInformation

Section "ffmpeg-directshow-devices"
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
  ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1
} else {
  Write-Output "BLOCKER: ffmpeg missing"
}

Section "usbipd-list"
if (Get-Command usbipd -ErrorAction SilentlyContinue) {
  usbipd list
} else {
  Write-Output "BLOCKER: usbipd missing"
}

Section "wsl-usb-visibility"
wsl -d Ubuntu-22.04 -- bash -lc "set +e; command -v lsusb; lsusb; command -v v4l2-ctl; v4l2-ctl --list-devices"
