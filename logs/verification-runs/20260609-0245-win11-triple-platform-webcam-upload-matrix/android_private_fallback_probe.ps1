param(
  [string]$Repo = "D:\src\work\hydracamv2",
  [string]$Root = "D:\hydracam-evidence\20260609-0245-win11-triple-platform-webcam-upload-matrix"
)

$ErrorActionPreference = "Continue"

$PackageName = "com.amaia23.hydracam"
$PrivateFallbackDir = "/data/user/0/$PackageName/app_flutter/hydracam-fallback"

$env:ANDROID_HOME = "C:\Users\jose\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = "D:\android-avd"

$emulator = Join-Path $env:ANDROID_HOME "emulator\emulator.exe"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
$out = Join-Path $Root "android-emulator-private-mock-media-fallback"
$bootOut = Join-Path $Root "android-emulator-private-fallback-boot"
$scriptsDir = Join-Path $Root "scripts"
$lenientProbe = Join-Path $scriptsDir "android_capture_probe_lenient_private.ps1"
New-Item -ItemType Directory -Force -Path $out, $bootOut, $scriptsDir | Out-Null

$sourceProbe = "D:\hydracam-evidence\win11-triple-platform-camera-master-slave\scripts\android_capture_probe.ps1"
$probeContent = (Get-Content -LiteralPath $sourceProbe -Raw).Replace(
  '$ErrorActionPreference = "Stop"',
  '$ErrorActionPreference = "Continue"'
).Replace(
  'if ($health.status -eq "ok" -and $health.automationTargetId -eq $TargetId) {',
  'if ($health.status -eq "ok" -and $health.automationTargetId -eq $TargetId -and @($health.commands | Where-Object { $_ -eq "list_cameras" }).Count -gt 0) {'
)
$probeContent | Set-Content -LiteralPath $lenientProbe -Encoding utf8

Set-Location $Repo
$apk = Join-Path $Repo "build\app\outputs\flutter-apk\app-debug.apk"
if (-not (Test-Path -LiteralPath $apk)) {
  flutter build apk --debug --target-platform android-x64 `
    --dart-define=HYDRACAM_AUTOMATION=true `
    --dart-define=HYDRACAM_MOCK_CAMERA=true `
    --dart-define=HYDRACAM_MOCK_MEDIA_SOURCE_DIR=$PrivateFallbackDir
} else {
  Write-Host "Reusing existing APK: $apk"
}

Get-Process qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
& $adb kill-server | Out-File -FilePath (Join-Path $bootOut "adb-kill-server.txt") -Encoding utf8

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

try {
  $deadline = (Get-Date).AddSeconds(180)
  $boot = ""
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ($emulatorProcess.HasExited) {
      throw "emulator exited before boot"
    }
    $bootRaw = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
    $boot = if ($null -eq $bootRaw) { "" } else { ($bootRaw | Out-String).Trim() }
    if ($boot -eq "1") {
      break
    }
  }
  if ($boot -ne "1") {
    throw "emulator boot timeout"
  }

  & $adb -s emulator-5554 uninstall $PackageName |
    Out-File -FilePath (Join-Path $out "uninstall-existing.txt") -Encoding utf8
  & $adb -s emulator-5554 install -r $apk |
    Out-File -FilePath (Join-Path $out "install.txt") -Encoding utf8

  & $adb root |
    Out-File -FilePath (Join-Path $out "adb-root.txt") -Encoding utf8
  Start-Sleep -Seconds 3
  & $adb -s emulator-5554 shell mkdir -p $PrivateFallbackDir |
    Out-File -FilePath (Join-Path $out "mkdir-private-fallback.txt") -Encoding utf8
  & $adb -s emulator-5554 push (Join-Path $Root "fallback-media\mock_photo.jpg") "$PrivateFallbackDir/mock_photo.jpg" |
    Out-File -FilePath (Join-Path $out "push-private-mock-photo.txt") -Encoding utf8
  & $adb -s emulator-5554 push (Join-Path $Root "fallback-media\mock_video.mp4") "$PrivateFallbackDir/mock_video.mp4" |
    Out-File -FilePath (Join-Path $out "push-private-mock-video.txt") -Encoding utf8
  $owner = (& $adb -s emulator-5554 shell stat -c "%u:%g" "/data/user/0/$PackageName" 2>$null | Out-String).Trim()
  if ($owner) {
    & $adb -s emulator-5554 shell chown -R $owner $PrivateFallbackDir | Out-Null
  }
  & $adb -s emulator-5554 shell ls -l $PrivateFallbackDir |
    Out-File -FilePath (Join-Path $out "private-fallback-ls-before.txt") -Encoding utf8

  & $lenientProbe `
    -Repo $Repo `
    -OutDir $out `
    -Serial "emulator-5554" `
    -TargetId "android-emulator" `
    -Port 6400 `
    -SkipBuild:$true `
    -SkipInstall:$true `
    -UseBackendSession:$true

  $summaryPath = Join-Path $out "summary.json"
  $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
  $rootPullDir = Join-Path $out "media-root-pull"
  New-Item -ItemType Directory -Force -Path $rootPullDir | Out-Null
  $photoDestination = Join-Path $rootPullDir "android_private_fallback_photo.jpg"
  $videoDestination = Join-Path $rootPullDir "android_private_fallback_video.mp4"
  & $adb root | Out-Null
  Start-Sleep -Seconds 3
  & $adb -s emulator-5554 pull $summary.photoPath $photoDestination |
    Out-File -FilePath (Join-Path $out "adb-root-pull-private-photo.txt") -Encoding utf8
  & $adb -s emulator-5554 pull $summary.videoPath $videoDestination |
    Out-File -FilePath (Join-Path $out "adb-root-pull-private-video.txt") -Encoding utf8

  $pullSummary = [ordered]@{
    photoPath = $summary.photoPath
    videoPath = $summary.videoPath
    copiedPhoto = $photoDestination
    copiedVideo = $videoDestination
    photoBytes = (Get-Item -LiteralPath $photoDestination -ErrorAction SilentlyContinue).Length
    videoBytes = (Get-Item -LiteralPath $videoDestination -ErrorAction SilentlyContinue).Length
    privateFallbackDir = $PrivateFallbackDir
    owner = $owner
    endedAt = (Get-Date).ToString("o")
  }
  $pullSummary |
    ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath (Join-Path $out "media-root-pull-summary.json") -Encoding utf8
  Get-Content -LiteralPath (Join-Path $out "media-root-pull-summary.json") -Raw
} finally {
  if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
    Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
  }
}
