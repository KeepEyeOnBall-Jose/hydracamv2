param(
  [string]$Repo = "D:\src\work\hydracamv2",
  [string]$Root = "D:\hydracam-evidence\20260609-0245-win11-triple-platform-webcam-upload-matrix"
)

$ErrorActionPreference = "Continue"

$out = Join-Path $Root "android-emulator-webcam0-combined"
$bootOut = Join-Path $Root "android-emulator-boot-webcam0-combined"
New-Item -ItemType Directory -Force -Path $out, $bootOut | Out-Null

$env:ANDROID_HOME = "C:\Users\jose\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = "D:\android-avd"

$emulator = Join-Path $env:ANDROID_HOME "emulator\emulator.exe"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"

Set-Location $Repo

Write-Host "=== windows flutter pub get ==="
flutter pub get | Tee-Object -FilePath (Join-Path $out "windows-pub-get.txt")

Write-Host "=== stop old emulator/adb ==="
Get-Process qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
& $adb kill-server | Out-File -FilePath (Join-Path $bootOut "adb-kill-server.txt") -Encoding utf8

Write-Host "=== start emulator ==="
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

Write-Host "=== android capture probe ==="
& "D:\hydracam-evidence\win11-triple-platform-camera-master-slave\scripts\android_capture_probe.ps1" `
  -Repo $Repo `
  -OutDir $out `
  -Serial "emulator-5554" `
  -TargetId "android-emulator" `
  -Port 6400 `
  -SkipBuild:$false `
  -SkipInstall:$false `
  -UseBackendSession:$true
$exit = $LASTEXITCODE

Write-Host "=== android summary ==="
Get-Content (Join-Path $out "summary.json") -Raw -ErrorAction SilentlyContinue
Write-Host "=== adb final ==="
& $adb devices -l

if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
  Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
}

exit $exit
