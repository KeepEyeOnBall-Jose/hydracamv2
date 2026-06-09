param(
  [string]$Repo = "D:\src\work\hydracamv2",
  [string]$OutDir = "D:\hydracam-evidence\win11-triple-platform-camera-master-slave\android-emulator",
  [string]$Serial = "emulator-5554",
  [string]$TargetId = "android-emulator",
  [int]$Port = 6400,
  [bool]$SkipBuild = $false,
  [bool]$SkipInstall = $false,
  [bool]$UseBackendSession = $true,
  [string]$CourtGuid = "a2387237-cb34-428a-81cd-49a4563d2768"
)

$ErrorActionPreference = "Stop"
$PackageName = "com.amaia23.hydracam"
$MainActivity = "$PackageName/.MainActivity"
$RemotePort = 4762
$Adb = "C:\Users\jose\AppData\Local\Android\Sdk\platform-tools\adb.exe"

function Write-JsonFile($Path, $Value) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Bridge($Method, $Path, $Body = $null, [int]$TimeoutSec = 30) {
  $uri = "http://127.0.0.1:$Port$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec $TimeoutSec
  }
  return Invoke-RestMethod -Method $Method -Uri $uri `
    -Body ($Body | ConvertTo-Json -Depth 20) `
    -ContentType "application/json" -TimeoutSec $TimeoutSec
}

function Wait-Bridge([int]$TimeoutSec = 120) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastError = $null
  while ((Get-Date) -lt $deadline) {
    try {
      $health = Invoke-Bridge "GET" "/healthz" $null 5
      if ($health.status -eq "ok" -and $health.automationTargetId -eq $TargetId) {
        return $health
      }
    } catch { $lastError = $_.Exception.Message }
    Start-Sleep -Seconds 1
  }
  throw "Automation bridge did not become healthy on localhost:$Port; lastError=$lastError"
}

function Wait-SessionState($Predicate, [int]$TimeoutSec, [string]$Label) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $last = $null
  while ((Get-Date) -lt $deadline) {
    $last = Invoke-Bridge "GET" "/session" $null 10
    if (& $Predicate $last) { return $last }
    Start-Sleep -Milliseconds 500
  }
  Write-JsonFile (Join-Path $OutDir "timeout-$Label.json") $last
  throw "Timed out waiting for session state: $Label"
}

function Wait-UploadTerminal([int]$TimeoutSec = 150) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastLogs = $null
  while ((Get-Date) -lt $deadline) {
    $session = Invoke-Bridge "GET" "/session" $null 10
    $lastLogs = Invoke-Bridge "GET" "/logs" $null 20
    $lines = @($lastLogs.persistedLogLines) + @($lastLogs.logs | ForEach-Object { $_.message })
    $uploaded = @($lines | Where-Object { $_ -match "Media uploaded:" -or $_ -match "Media uploaded successfully" })
    $failed = @($lines | Where-Object { $_ -match "Failed to upload media:" -or $_ -match "Error uploading media:" })
    if (($uploaded.Count -ge 2 -or $failed.Count -gt 0) -and -not $session.isUploading -and [int]$session.queueLength -eq 0) {
      return @{
        session = $session
        logs = $lastLogs
        uploadedLineCount = $uploaded.Count
        failedLineCount = $failed.Count
        failedLines = $failed
      }
    }
    Start-Sleep -Seconds 2
  }
  return @{
    session = Invoke-Bridge "GET" "/session" $null 10
    logs = $lastLogs
    uploadedLineCount = 0
    failedLineCount = -1
    failedLines = @("upload terminal state timeout")
  }
}

function Extract-MediaPaths($Logs) {
  $lines = @($Logs.persistedLogLines) + @($Logs.logs | ForEach-Object { $_.message })
  $photo = $null
  $video = $null
  foreach ($line in $lines) {
    if ($null -eq $photo -and $line -match "Photo saved to session path:\s*(.+?\.jpg)\b") { $photo = $Matches[1].Trim() }
    if ($null -eq $video -and $line -match "Video saved to session path:\s*(.+?\.mp4)\b") { $video = $Matches[1].Trim() }
  }
  return @{ photo = $photo; video = $video }
}

function Pull-AppFile($DevicePath, $DestinationDir) {
  if (-not $DevicePath) { return $null }
  New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
  $leaf = Split-Path -Leaf $DevicePath
  $sdcard = "/sdcard/Download/$leaf"
  & $Adb -s $Serial shell run-as $PackageName cp "`"$DevicePath`"" $sdcard | Out-Null
  $dest = Join-Path $DestinationDir $leaf
  & $Adb -s $Serial pull $sdcard $dest | Out-Null
  & $Adb -s $Serial shell rm $sdcard | Out-Null
  if (Test-Path -LiteralPath $dest) { return $dest }
  return $null
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "media") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "screenshots") | Out-Null
Set-Location $Repo

$summary = [ordered]@{
  platform = "android"
  serial = $Serial
  targetId = $TargetId
  bridgePort = $Port
  useBackendSession = $UseBackendSession
  startedAt = (Get-Date).ToString("o")
}
$status = "failed"

try {
  if (-not $SkipBuild) {
    flutter build apk --debug --target-platform android-x64 `
      --dart-define=HYDRACAM_AUTOMATION=true `
      --dart-define=HYDRACAM_MOCK_CAMERA=false
  }
  $apk = Join-Path $Repo "build\app\outputs\flutter-apk\app-debug.apk"
  if (-not (Test-Path -LiteralPath $apk)) { throw "APK missing: $apk" }
  if (-not $SkipInstall) {
    & $Adb -s $Serial install -r $apk
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
    & $Adb -s $Serial shell pm grant $PackageName $permission 2>$null | Out-Null
  }
  & $Adb -s $Serial shell am force-stop $PackageName | Out-Null
  & $Adb -s $Serial forward --remove-all | Out-Null
  & $Adb -s $Serial forward "tcp:$Port" "tcp:$RemotePort" | Out-Null
  & $Adb -s $Serial logcat -c | Out-Null
  & $Adb -s $Serial shell am start -n $MainActivity `
    --es role master `
    --es automationTargetId $TargetId | Out-Null

  $health = Wait-Bridge 120
  Write-JsonFile (Join-Path $OutDir "health.json") $health

  $listCameras = Invoke-Bridge "POST" "/commands/list_cameras" @{} 60
  Write-JsonFile (Join-Path $OutDir "list-cameras.json") $listCameras
  $settings = Invoke-Bridge "POST" "/settings" @{
    masterShouldRecord = $true
    timerDuration = 0
    autoplayVideoOnMaster = $false
    flashForVideoAnnounce = $false
    autoUploadMaterials = $true
    deleteLocalAfterUpload = $false
    cameraLensPreference = "autoBack"
    videoCaptureProfile = "dataSaver480p30"
  } 60
  Write-JsonFile (Join-Path $OutDir "settings.json") $settings

  $sessionId = "codex-$TargetId-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
  if ($UseBackendSession) {
    $start = Invoke-Bridge "POST" "/commands/start_session" @{
      sessionId = $sessionId
      courtGuid = $CourtGuid
    } 90
  } else {
    $start = Invoke-Bridge "POST" "/commands/start_local_session" @{ sessionId = $sessionId } 30
  }
  Write-JsonFile (Join-Path $OutDir "start-session.json") $start
  if (-not $start.result.isActive) {
    $summary.backendSessionFailed = $true
    $start = Invoke-Bridge "POST" "/commands/start_local_session" @{ sessionId = "$sessionId-local-fallback" } 30
    Write-JsonFile (Join-Path $OutDir "start-local-session-fallback.json") $start
  }
  Wait-SessionState { param($s) $s.isActive -eq $true } 30 "active" | Out-Null

  & $Adb -s $Serial exec-out screencap -p > (Join-Path $OutDir "screenshots\before.png")

  $photo = Invoke-Bridge "POST" "/commands/take_photo" @{ showCountdown = $false } 90
  Write-JsonFile (Join-Path $OutDir "take-photo.json") $photo
  Wait-SessionState { param($s) [int]$s.photoCount -ge 1 } 90 "photo-count" | Out-Null

  $recordStart = Invoke-Bridge "POST" "/commands/start_recording" @{} 90
  Write-JsonFile (Join-Path $OutDir "start-recording.json") $recordStart
  Wait-SessionState { param($s) $s.isRecording -eq $true } 90 "recording-started" | Out-Null
  Start-Sleep -Seconds 4
  $recordStop = Invoke-Bridge "POST" "/commands/stop_recording" @{} 120
  Write-JsonFile (Join-Path $OutDir "stop-recording.json") $recordStop
  Wait-SessionState { param($s) ([int]$s.videoCount -ge 1) -and ($s.isRecording -eq $false) } 120 "video-count" | Out-Null

  $uploadTerminal = Wait-UploadTerminal 180
  Write-JsonFile (Join-Path $OutDir "upload-terminal.json") $uploadTerminal

  & $Adb -s $Serial exec-out screencap -p > (Join-Path $OutDir "screenshots\after.png")
  & $Adb -s $Serial logcat -d -t 1200 > (Join-Path $OutDir "logcat-tail.txt")

  $logs = Invoke-Bridge "GET" "/logs" $null 30
  Write-JsonFile (Join-Path $OutDir "logs.json") $logs
  $mediaPaths = Extract-MediaPaths $logs
  $copiedPhoto = Pull-AppFile $mediaPaths.photo (Join-Path $OutDir "media")
  $copiedVideo = Pull-AppFile $mediaPaths.video (Join-Path $OutDir "media")

  $end = Invoke-Bridge "POST" "/commands/end_session" @{} 60
  Write-JsonFile (Join-Path $OutDir "end-session.json") $end

  $status = "passed"
  $summary.backendSessionGuid = $start.result.sessionGuid
  $summary.photoPath = $mediaPaths.photo
  $summary.videoPath = $mediaPaths.video
  $summary.copiedPhoto = $copiedPhoto
  $summary.copiedVideo = $copiedVideo
  $summary.uploadedLineCount = $uploadTerminal.uploadedLineCount
  $summary.failedUploadLineCount = $uploadTerminal.failedLineCount
  $summary.failedUploadLines = $uploadTerminal.failedLines
  $summary.cameras = $listCameras.result.cameras
} catch {
  $summary.error = $_.Exception.Message
  try {
    & $Adb -s $Serial logcat -d -t 1200 > (Join-Path $OutDir "logcat-tail-after-error.txt")
    $logs = Invoke-Bridge "GET" "/logs" $null 10
    Write-JsonFile (Join-Path $OutDir "logs-after-error.json") $logs
  } catch {
    $summary.logCollectionError = $_.Exception.Message
  }
  throw
} finally {
  $summary.status = $status
  $summary.endedAt = (Get-Date).ToString("o")
  Write-JsonFile (Join-Path $OutDir "summary.json") $summary
  & $Adb -s $Serial shell am force-stop $PackageName 2>$null | Out-Null
}
