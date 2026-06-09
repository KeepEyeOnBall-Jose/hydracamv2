param(
  [string]$Repo = "E:\work-repos\hydracamv2",
  [string]$Root = "D:\hydracam-evidence\20260609-0245-win11-triple-platform-webcam-upload-matrix",
  [string]$LinuxRepo = "/home/jose/hydracamv2-linux",
  [string]$LinuxSourceRepo = "/mnt/e/work-repos/hydracamv2"
)

$ErrorActionPreference = "Continue"

$PackageName = "com.amaia23.hydracam"
$MainActivity = "$PackageName/.MainActivity"
$WinPort = 6510
$LinuxPort = 6511
$AndroidPort = 6400
$AndroidRemotePort = 4762
$MasterServerPort = 4040
$out = Join-Path $Root "role-matrix"
$winOut = Join-Path $out "windows-standby"
$linuxOutWin = Join-Path $out "linux-standby"
$androidOut = Join-Path $out "android-standby"
$bootOut = Join-Path $out "android-emulator-boot"
New-Item -ItemType Directory -Force -Path $out, $winOut, $linuxOutWin, $androidOut, $bootOut | Out-Null

$rootDrive = $Root.Substring(0, 1).ToLowerInvariant()
$rootTail = $Root.Substring(2).Replace("\", "/")
$wslRoot = "/mnt/$rootDrive$rootTail"
$wslFallbackMedia = "$wslRoot/fallback-media"

$env:ANDROID_HOME = "C:\Users\jose\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = "D:\android-avd"
$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
$emulator = Join-Path $env:ANDROID_HOME "emulator\emulator.exe"

function Write-JsonFile($Path, $Value) {
  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Bridge($BridgeUrl, $Method, $Path, $Body = $null, [int]$TimeoutSec = 10) {
  $uri = "$BridgeUrl$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec $TimeoutSec
  }
  $json = $Body | ConvertTo-Json -Depth 20
  return Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json" -TimeoutSec $TimeoutSec
}

function Wait-Bridge($Target, [int]$TimeoutSec = 240) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastError = $null
  while ((Get-Date) -lt $deadline) {
    try {
      $health = Invoke-Bridge $Target.bridgeUrl "GET" "/healthz" $null 5
      $commands = @($health.commands)
      if ($health.status -eq "ok" -and
          $health.automationTargetId -eq $Target.id -and
          $commands.Contains("set_role")) {
        return $health
      }
    } catch {
      $lastError = $_.Exception.Message
    }
    Start-Sleep -Seconds 1
  }
  throw "Bridge did not become role-switch ready for $($Target.id) at $($Target.bridgeUrl); lastError=$lastError"
}

function Post-Role($Target, $Payload, $RotationDir) {
  $started = Get-Date
  $result = [ordered]@{
    targetId = $Target.id
    bridgeUrl = $Target.bridgeUrl
    payload = $Payload
    startedAt = $started.ToString("o")
  }
  try {
    $response = Invoke-Bridge $Target.bridgeUrl "POST" "/commands/set_role" $Payload 45
    $result.response = $response
    $result.status = "ok"
  } catch {
    $result.status = "failed"
    $result.error = $_.Exception.Message
  }
  $ended = Get-Date
  $result.endedAt = $ended.ToString("o")
  $result.durationMs = [Math]::Round(($ended - $started).TotalMilliseconds, 3)
  Write-JsonFile (Join-Path $RotationDir "set-role-$($Target.id).json") $result
  return $result
}

function Wait-ConnectedClients($MasterTarget, $ExpectedCount, $RotationDir, [int]$TimeoutSec = 45) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $last = $null
  while ((Get-Date) -lt $deadline) {
    try {
      $snapshot = Invoke-Bridge $MasterTarget.bridgeUrl "POST" "/commands/connected_clients" @{} 10
      $last = $snapshot
      $result = $snapshot.result
      $clients = @($result.connectedClients)
      if ($clients.Count -ge $ExpectedCount) {
        Write-JsonFile (Join-Path $RotationDir "connected-clients.json") $snapshot
        return [ordered]@{
          status = "passed"
          connectedClientCount = $clients.Count
          snapshot = $snapshot
        }
      }
    } catch {
      $last = @{ error = $_.Exception.Message }
    }
    Start-Sleep -Seconds 1
  }
  Write-JsonFile (Join-Path $RotationDir "connected-clients.json") $last
  $lastCount = 0
  if ($last -and $last.result) {
    $lastCount = @($last.result.connectedClients).Count
  }
  return [ordered]@{
    status = "failed"
    connectedClientCount = $lastCount
    snapshot = $last
  }
}

function First-NonLoopbackIPv4() {
  $candidate = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -notlike "127.*" -and
      $_.IPAddress -notlike "169.254.*" -and
      $_.PrefixOrigin -ne "WellKnown"
    } |
    Select-Object -First 1
  if ($candidate) {
    return $candidate.IPAddress
  }
  return "127.0.0.1"
}

function WslValue($Command) {
  $value = (& wsl.exe -d Ubuntu-22.04 -- bash -lc $Command 2>$null | Out-String).Trim()
  return $value
}

$processesToStop = Get-Process sport_cam_sync, flutter, dart -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -in @("sport_cam_sync", "flutter", "dart") }
$processesToStop | Stop-Process -Force -ErrorAction SilentlyContinue
& wsl.exe -d Ubuntu-22.04 -- bash -lc "pkill -f sport_cam_sync || true; pkill -f 'flutter run -d linux' || true" | Out-Null
Get-Process qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
& $adb kill-server | Out-File -FilePath (Join-Path $bootOut "adb-kill-server.txt") -Encoding utf8

$linuxPrimeCommand = "set -euo pipefail; mkdir -p '$LinuxRepo'; rsync -a --delete --exclude='.git/' --exclude='.dart_tool/' --exclude='build/' '$LinuxSourceRepo/' '$LinuxRepo/'; cd '$LinuxRepo'; /home/jose/flutter-linux/bin/flutter pub get"
& wsl.exe -d Ubuntu-22.04 -- bash -lc $linuxPrimeCommand 2>&1 |
  Out-File -FilePath (Join-Path $linuxOutWin "prime-linux-checkout.txt") -Encoding utf8

$windowsIp = First-NonLoopbackIPv4
$wslIp = (WslValue "hostname -I | awk '{print `$1}'")
$wslGateway = (WslValue "awk '/nameserver/{print `$2; exit}' /etc/resolv.conf")
$network = [ordered]@{
  windowsIp = $windowsIp
  wslIp = $wslIp
  wslGateway = $wslGateway
  androidHostAlias = "10.0.2.2"
}
Write-JsonFile (Join-Path $out "network-addresses.json") $network

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

$startedProcesses = @()
try {
  $bootDeadline = (Get-Date).AddSeconds(180)
  $boot = ""
  while ((Get-Date) -lt $bootDeadline) {
    Start-Sleep -Seconds 5
    if ($emulatorProcess.HasExited) {
      throw "Android emulator exited before boot"
    }
    $bootRaw = & $adb -s emulator-5554 shell getprop sys.boot_completed 2>$null
    $boot = if ($null -eq $bootRaw) { "" } else { ($bootRaw | Out-String).Trim() }
    if ($boot -eq "1") {
      break
    }
  }
  if ($boot -ne "1") {
    throw "Android emulator boot timeout"
  }

  $apk = Join-Path $Repo "build\app\outputs\flutter-apk\app-debug.apk"
  if (Test-Path -LiteralPath $apk) {
    & $adb -s emulator-5554 install -r $apk |
      Out-File -FilePath (Join-Path $androidOut "install.txt") -Encoding utf8
  }
  foreach ($permission in @(
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO"
  )) {
    & $adb -s emulator-5554 shell pm grant $PackageName $permission 2>$null | Out-Null
  }
  & $adb -s emulator-5554 forward --remove-all | Out-Null
  & $adb -s emulator-5554 forward "tcp:$AndroidPort" "tcp:$AndroidRemotePort" | Out-Null
  & $adb -s emulator-5554 forward "tcp:$MasterServerPort" "tcp:$MasterServerPort" | Out-Null

  $winArgs = @(
    "run",
    "-d", "windows",
    "--debug",
    "--no-pub",
    "--dart-define=HYDRACAM_AUTOMATION=true",
    "--dart-define=HYDRACAM_AUTOMATION_ROLE=standby",
    "--dart-define=HYDRACAM_AUTOMATION_PORT=$WinPort",
    "--dart-define=HYDRACAM_AUTOMATION_TARGET_ID=windows-native",
    "--dart-define=HYDRACAM_MOCK_CAMERA=true",
    "-t", "lib/main.dart"
  )
  $winProcess = Start-Process `
    -FilePath "flutter" `
    -ArgumentList $winArgs `
    -WorkingDirectory $Repo `
    -RedirectStandardOutput (Join-Path $winOut "flutter-run.stdout.txt") `
    -RedirectStandardError (Join-Path $winOut "flutter-run.stderr.txt") `
    -PassThru
  $startedProcesses += $winProcess

  $linuxOut = "$wslRoot/role-matrix/linux-standby"
  $linuxCommand = "mkdir -p '$linuxOut'; cd '$LinuxRepo'; /home/jose/flutter-linux/bin/flutter run -d linux --no-pub --dart-define=HYDRACAM_AUTOMATION=true --dart-define=HYDRACAM_AUTOMATION_ROLE=standby --dart-define=HYDRACAM_AUTOMATION_PORT=$LinuxPort --dart-define=HYDRACAM_AUTOMATION_TARGET_ID=linux-native --dart-define=HYDRACAM_MOCK_CAMERA=true --dart-define=HYDRACAM_MOCK_MEDIA_SOURCE_DIR=$wslFallbackMedia -t lib/main.dart > '$linuxOut/flutter-run.stdout.txt' 2> '$linuxOut/flutter-run.stderr.txt'"
  $linuxProcess = Start-Process `
    -FilePath "wsl.exe" `
    -ArgumentList @("-d", "Ubuntu-22.04", "--", "bash", "-lc", $linuxCommand) `
    -RedirectStandardOutput (Join-Path $linuxOutWin "wsl.stdout.txt") `
    -RedirectStandardError (Join-Path $linuxOutWin "wsl.stderr.txt") `
    -PassThru
  $startedProcesses += $linuxProcess

  & $adb -s emulator-5554 shell am force-stop $PackageName | Out-Null
  & $adb -s emulator-5554 shell am start -n $MainActivity `
    --es role standby `
    --es automationTargetId android-emulator |
    Out-File -FilePath (Join-Path $androidOut "am-start.txt") -Encoding utf8

  $targets = @(
    [ordered]@{ id = "windows-native"; platform = "windows"; bridgeUrl = "http://127.0.0.1:$WinPort" },
    [ordered]@{ id = "linux-native"; platform = "linux"; bridgeUrl = "http://127.0.0.1:$LinuxPort" },
    [ordered]@{ id = "android-emulator"; platform = "android"; bridgeUrl = "http://127.0.0.1:$AndroidPort" }
  )

  $health = [ordered]@{}
  foreach ($target in $targets) {
    try {
      $health[$target.id] = Wait-Bridge $target 300
      Write-JsonFile (Join-Path $out "health-$($target.id).json") $health[$target.id]
    } catch {
      $health[$target.id] = @{ status = "failed"; error = $_.Exception.Message }
      Write-JsonFile (Join-Path $out "health-$($target.id).json") $health[$target.id]
      throw
    }
  }

  $masterAddressBySlave = @{
    "windows-native" = @{
      "linux-native" = $wslGateway
      "android-emulator" = "10.0.2.2"
    }
    "linux-native" = @{
      "windows-native" = $wslIp
      "android-emulator" = $wslIp
    }
    "android-emulator" = @{
      "windows-native" = "127.0.0.1"
      "linux-native" = $wslGateway
    }
  }

  $rotationResults = @()
  foreach ($master in $targets) {
    $rotationDir = Join-Path $out "master-$($master.id)"
    New-Item -ItemType Directory -Force -Path $rotationDir | Out-Null
    $slaves = @($targets | Where-Object { $_.id -ne $master.id })
    $roleResponses = @()

    $roleResponses += Post-Role $master @{ role = "master" } $rotationDir
    Start-Sleep -Seconds 3

    foreach ($slave in $slaves) {
      $preferredMasterIp = $masterAddressBySlave[$master.id][$slave.id]
      $roleResponses += Post-Role $slave @{
        role = "slave"
        preferredMasterIp = $preferredMasterIp
        forceSlaveMode = $true
      } $rotationDir
    }

    $connected = Wait-ConnectedClients $master $slaves.Count $rotationDir 45
    $rotation = [ordered]@{
      masterId = $master.id
      slaveIds = @($slaves | ForEach-Object { $_.id })
      roleResponses = $roleResponses
      connectedClientStatus = $connected.status
      connectedClientCount = $connected.connectedClientCount
      status = if ($connected.status -eq "passed") { "passed" } else { "failed" }
    }
    Write-JsonFile (Join-Path $rotationDir "summary.json") $rotation
    $rotationResults += $rotation
  }

  $passed = @($rotationResults | Where-Object { $_.status -eq "passed" }).Count
  $summary = [ordered]@{
    status = if ($passed -eq $rotationResults.Count) { "passed" } else { "failed" }
    startedAt = (Get-Date).ToString("o")
    network = $network
    rotations = $rotationResults
    passedRotationCount = $passed
    totalRotationCount = $rotationResults.Count
  }
  Write-JsonFile (Join-Path $out "summary.json") $summary
  Get-Content -LiteralPath (Join-Path $out "summary.json") -Raw
} finally {
  foreach ($process in $startedProcesses) {
    if ($process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }
  & wsl.exe -d Ubuntu-22.04 -- bash -lc "pkill -f sport_cam_sync || true; pkill -f 'flutter run -d linux' || true" | Out-Null
  if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
    Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
  }
}
