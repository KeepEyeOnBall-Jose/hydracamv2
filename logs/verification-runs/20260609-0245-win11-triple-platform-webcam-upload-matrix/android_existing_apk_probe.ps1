param(
  [string]$Repo = "D:\src\work\hydracamv2",
  [string]$Root = "D:\hydracam-evidence\20260609-0245-win11-triple-platform-webcam-upload-matrix"
)

$ErrorActionPreference = "Continue"

$env:ANDROID_HOME = "C:\Users\jose\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = "D:\android-avd"

$emulator = Join-Path $env:ANDROID_HOME "emulator\emulator.exe"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
$out = Join-Path $Root "android-emulator-mock-media-fallback"
$bootOut = Join-Path $Root "android-emulator-existing-apk-boot"
$scriptsDir = Join-Path $Root "scripts"
$lenientProbe = Join-Path $scriptsDir "android_capture_probe_lenient.ps1"
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

$bootSummary = [ordered]@{
  startedAt = (Get-Date).ToString("o")
  processId = $emulatorProcess.Id
  avd = "HydraCam_API33_x86_64"
  args = $emulatorArgs
  status = "booting"
}

try {
  $deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ($emulatorProcess.HasExited) {
      $bootSummary.status = "exited-before-boot"
      $bootSummary.exitCode = $emulatorProcess.ExitCode
      break
    }
    $devices = & $adb devices -l
    $devices | Out-File -FilePath (Join-Path $bootOut "adb-devices-latest.txt") -Encoding utf8
    $bootRaw = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
    $boot = if ($null -eq $bootRaw) { "" } else { ($bootRaw | Out-String).Trim() }
    if ($boot -eq "1") {
      $bootSummary.status = "booted"
      $bootSummary.bootCompleted = "1"
      break
    }
  }

  if ($bootSummary.status -eq "booting") {
    $bootSummary.status = "boot-timeout"
  }
  $bootSummary.endedAt = (Get-Date).ToString("o")
  $bootSummary |
    ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath (Join-Path $bootOut "summary.json") -Encoding utf8
  Get-Content (Join-Path $bootOut "summary.json") -Raw

  if ($bootSummary.status -ne "booted") {
    throw "emulator did not stay booted: $($bootSummary.status)"
  }

  & $adb -s emulator-5554 uninstall "com.amaia23.hydracam" |
    Out-File -FilePath (Join-Path $out "uninstall-existing.txt") -Encoding utf8
  & $adb -s emulator-5554 shell mkdir -p "/sdcard/Download/hydracam-fallback" |
    Out-File -FilePath (Join-Path $out "mkdir-fallback-media.txt") -Encoding utf8
  & $adb -s emulator-5554 push (Join-Path $Root "fallback-media\mock_photo.jpg") "/sdcard/Download/hydracam-fallback/mock_photo.jpg" |
    Out-File -FilePath (Join-Path $out "push-mock-photo.txt") -Encoding utf8
  & $adb -s emulator-5554 push (Join-Path $Root "fallback-media\mock_video.mp4") "/sdcard/Download/hydracam-fallback/mock_video.mp4" |
    Out-File -FilePath (Join-Path $out "push-mock-video.txt") -Encoding utf8

  & $lenientProbe `
    -Repo $Repo `
    -OutDir $out `
    -Serial "emulator-5554" `
    -TargetId "android-emulator" `
    -Port 6400 `
    -SkipBuild:$true `
    -SkipInstall:$false `
    -UseBackendSession:$true
} finally {
  if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
    Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
  }
}
