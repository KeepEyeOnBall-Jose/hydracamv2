param(
  [string]$Root = "D:\hydracam-evidence\20260609-0245-win11-triple-platform-webcam-upload-matrix"
)

$ErrorActionPreference = "Continue"

$out = Join-Path $Root "android-emulator-mock-media-fallback"
$media = Join-Path $out "media-root-pull"
$bootOut = Join-Path $Root "android-emulator-root-pull-boot"
New-Item -ItemType Directory -Force -Path $media, $bootOut | Out-Null

$env:ANDROID_HOME = "C:\Users\jose\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = "D:\android-avd"
$emulator = Join-Path $env:ANDROID_HOME "emulator\emulator.exe"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"

$photo = "/data/user/0/com.amaia23.hydracam/app_flutter/session_cc8627fd-6427-40bf-80e2-fae5c247bf22/mock_1_2026-06-09T01-44-28-289155.jpg"
$video = "/data/user/0/com.amaia23.hydracam/app_flutter/session_cc8627fd-6427-40bf-80e2-fae5c247bf22/mock_2_2026-06-09T01-44-34-914838.mp4"

Get-Process qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
& $adb kill-server | Out-Null

$emulatorArgs = @(
  "-avd", "HydraCam_API33_x86_64",
  "-no-window",
  "-no-snapshot-load",
  "-no-snapshot-save",
  "-no-boot-anim",
  "-gpu", "swiftshader_indirect",
  "-camera-back", "webcam0",
  "-camera-front", "none"
)
$emulatorProcess = Start-Process `
  -FilePath $emulator `
  -ArgumentList $emulatorArgs `
  -RedirectStandardOutput (Join-Path $bootOut "emulator.stdout.txt") `
  -RedirectStandardError (Join-Path $bootOut "emulator.stderr.txt") `
  -PassThru

$deadline = (Get-Date).AddSeconds(180)
$boot = ""
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  if ($emulatorProcess.HasExited) {
    break
  }
  $bootRaw = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
  $boot = if ($null -eq $bootRaw) { "" } else { ($bootRaw | Out-String).Trim() }
  if ($boot -eq "1") {
    break
  }
}

$summary = [ordered]@{
  startedAt = (Get-Date).ToString("o")
  bootCompleted = $boot
  emulatorExited = $emulatorProcess.HasExited
  photoPath = $photo
  videoPath = $video
}

if ($boot -eq "1") {
  $summary.adbRoot = (& $adb root 2>&1 | Out-String).Trim()
  Start-Sleep -Seconds 3
  $summary.photoLs = (& $adb -s emulator-5554 shell ls -l $photo 2>&1 | Out-String).Trim()
  $summary.videoLs = (& $adb -s emulator-5554 shell ls -l $video 2>&1 | Out-String).Trim()

  $photoDestination = Join-Path $media "android_fallback_mock_photo.jpg"
  $videoDestination = Join-Path $media "android_fallback_mock_video.mp4"
  & $adb -s emulator-5554 pull $photo $photoDestination |
    Out-String |
    Set-Content -LiteralPath (Join-Path $out "adb-pull-photo.txt") -Encoding utf8
  & $adb -s emulator-5554 pull $video $videoDestination |
    Out-String |
    Set-Content -LiteralPath (Join-Path $out "adb-pull-video.txt") -Encoding utf8

  $summary.copiedPhoto = $photoDestination
  $summary.copiedVideo = $videoDestination
  $summary.photoBytes = (Get-Item $photoDestination -ErrorAction SilentlyContinue).Length
  $summary.videoBytes = (Get-Item $videoDestination -ErrorAction SilentlyContinue).Length
}

$summary.endedAt = (Get-Date).ToString("o")
$summary |
  ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath (Join-Path $out "media-root-pull-summary.json") -Encoding utf8
Get-Content (Join-Path $out "media-root-pull-summary.json") -Raw

if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
  Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
}
