param(
  [string]$Repo = "D:\src\work\hydracamv2",
  [string]$OutDir = "D:\hydracam-evidence\win11-triple-platform-camera-master-slave\windows",
  [string]$DeviceId = "windows",
  [string]$TargetId = "windows-native",
  [int]$Port = 4762,
  [bool]$MockCamera = $false,
  [bool]$UseBackendSession = $true,
  [string]$CourtGuid = "a2387237-cb34-428a-81cd-49a4563d2768"
)

$ErrorActionPreference = "Stop"

function Write-JsonFile($Path, $Value) {
  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Bridge($Method, $Path, $Body = $null, [int]$TimeoutSec = 30) {
  $uri = "http://127.0.0.1:$Port$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec $TimeoutSec
  }
  $json = $Body | ConvertTo-Json -Depth 20
  return Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json" -TimeoutSec $TimeoutSec
}

function Wait-Bridge([int]$TimeoutSec = 180) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastError = $null
  while ((Get-Date) -lt $deadline) {
    try {
      $health = Invoke-Bridge "GET" "/healthz" $null 5
      if ($health.status -eq "ok" -and $health.automationTargetId -eq $TargetId) {
        return $health
      }
    } catch {
      $lastError = $_.Exception.Message
    }
    Start-Sleep -Seconds 1
  }
  throw "Automation bridge did not become healthy on port $Port; lastError=$lastError"
}

function Wait-SessionState($Predicate, [int]$TimeoutSec, [string]$Label) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $last = $null
  while ((Get-Date) -lt $deadline) {
    $last = Invoke-Bridge "GET" "/session" $null 10
    if (& $Predicate $last) {
      return $last
    }
    Start-Sleep -Milliseconds 500
  }
  Write-JsonFile (Join-Path $OutDir "timeout-$Label.json") $last
  throw "Timed out waiting for session state: $Label"
}

function Wait-UploadTerminal([int]$TimeoutSec = 120) {
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

function Copy-IfExists($Path, $DestinationDir) {
  if ($Path -and (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Copy-Item -LiteralPath $Path -Destination $DestinationDir -Force
    return Join-Path $DestinationDir (Split-Path -Leaf $Path)
  }
  return $null
}

function Extract-MediaPaths($Logs) {
  $lines = @($Logs.persistedLogLines) + @($Logs.logs | ForEach-Object { $_.message })
  $photo = $null
  $video = $null
  foreach ($line in $lines) {
    if ($null -eq $photo -and $line -match "Photo saved to session path:\s*(.+?\.jpg)\b") {
      $photo = $Matches[1].Trim()
    }
    if ($null -eq $photo -and $line -match "Mock photo saved to session path:\s*(.+?\.jpg)\b") {
      $photo = $Matches[1].Trim()
    }
    if ($null -eq $video -and $line -match "Video saved to session path:\s*(.+?\.mp4)\b") {
      $video = $Matches[1].Trim()
    }
    if ($null -eq $video -and $line -match "Mock video saved to session path:\s*(.+?\.mp4)\b") {
      $video = $Matches[1].Trim()
    }
  }
  return @{
    photo = $photo
    video = $video
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "media") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "screenshots") | Out-Null

Set-Location $Repo

Get-Process sport_cam_sync,flutter,dart -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -like "*hydracam*" -or $_.ProcessName -in @("sport_cam_sync") } |
  Stop-Process -Force -ErrorAction SilentlyContinue

$flutterArgs = @(
  "run",
  "-d", $DeviceId,
  "--debug",
  "--no-pub",
  "--dart-define=HYDRACAM_AUTOMATION=true",
  "--dart-define=HYDRACAM_AUTOMATION_ROLE=master",
  "--dart-define=HYDRACAM_AUTOMATION_PORT=$Port",
  "--dart-define=HYDRACAM_AUTOMATION_TARGET_ID=$TargetId",
  "--dart-define=HYDRACAM_MOCK_CAMERA=$($MockCamera.ToString().ToLowerInvariant())",
  "-t", "lib/main.dart"
)

$stdout = Join-Path $OutDir "flutter-run.stdout.txt"
$stderr = Join-Path $OutDir "flutter-run.stderr.txt"
$process = Start-Process -FilePath "flutter" -ArgumentList $flutterArgs -WorkingDirectory $Repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$status = "failed"
$summary = @{
  platform = "windows"
  deviceId = $DeviceId
  targetId = $TargetId
  port = $Port
  mockCamera = $MockCamera
  useBackendSession = $UseBackendSession
  processId = $process.Id
  startedAt = (Get-Date).ToString("o")
}

try {
  $health = Wait-Bridge 240
  Write-JsonFile (Join-Path $OutDir "health.json") $health
  $supportsScreenshot =
    @($health.commands | Where-Object { $_ -eq "capture_screenshot" }).Count -gt 0

  $listCameras = Invoke-Bridge "POST" "/commands/list_cameras" @{} 60
  Write-JsonFile (Join-Path $OutDir "list-cameras.json") $listCameras
  $cameraNames = @($listCameras.result.cameras | ForEach-Object { $_.name })
  $preferredCameraMatches =
    @($cameraNames | Where-Object { $_ -match "USB2.0|UVC|DroidCam|OBS" })
  $preferredCamera = $null
  if ($preferredCameraMatches.Count -gt 0) {
    $preferredCamera = [string]$preferredCameraMatches[0]
  }
  if (-not $preferredCamera -and $cameraNames.Count -gt 0) {
    $preferredCamera = [string]$cameraNames[0]
  }

  $settingsPayload = @{
    masterShouldRecord = $true
    timerDuration = 0
    autoplayVideoOnMaster = $false
    flashForVideoAnnounce = $false
    autoUploadMaterials = $true
    deleteLocalAfterUpload = $false
    videoCaptureProfile = "dataSaver480p30"
  }
  if ($preferredCamera) {
    $settingsPayload.selectedCameraName = $preferredCamera
  } else {
    $settingsPayload.cameraLensPreference = "autoBack"
  }
  $settings = Invoke-Bridge "POST" "/settings" $settingsPayload 60
  Write-JsonFile (Join-Path $OutDir "settings.json") $settings

  $sessionId = "codex-$TargetId-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
  if ($UseBackendSession) {
    $start = Invoke-Bridge "POST" "/commands/start_session" @{
      sessionId = $sessionId
      courtGuid = $CourtGuid
    } 90
  } else {
    $start = Invoke-Bridge "POST" "/commands/start_local_session" @{
      sessionId = $sessionId
    } 30
  }
  Write-JsonFile (Join-Path $OutDir "start-session.json") $start
  if (-not $start.result.isActive) {
    $summary.backendSessionFailed = $true
    $start = Invoke-Bridge "POST" "/commands/start_local_session" @{
      sessionId = "$sessionId-local-fallback"
    } 30
    Write-JsonFile (Join-Path $OutDir "start-local-session-fallback.json") $start
  }
  Wait-SessionState { param($s) $s.isActive -eq $true } 30 "active" | Out-Null

  if ($supportsScreenshot) {
    $screenBefore = Invoke-Bridge "POST" "/commands/capture_screenshot" @{
      name = "$TargetId-before-capture"
      pixelRatio = 1.0
    } 30
    Write-JsonFile (Join-Path $OutDir "screenshot-before.json") $screenBefore
    Copy-IfExists $screenBefore.result.filePath (Join-Path $OutDir "screenshots") | Out-Null
  } else {
    Write-JsonFile (Join-Path $OutDir "screenshot-before.json") @{
      status = "skipped"
      reason = "capture_screenshot command is not available in this remote checkout"
    }
  }

  $photo = Invoke-Bridge "POST" "/commands/take_photo" @{
    showCountdown = $false
  } 90
  Write-JsonFile (Join-Path $OutDir "take-photo.json") $photo
  Wait-SessionState { param($s) [int]$s.photoCount -ge 1 } 60 "photo-count" | Out-Null

  $recordStart = Invoke-Bridge "POST" "/commands/start_recording" @{} 90
  Write-JsonFile (Join-Path $OutDir "start-recording.json") $recordStart
  Wait-SessionState { param($s) $s.isRecording -eq $true } 60 "recording-started" | Out-Null
  Start-Sleep -Seconds 4
  $recordStop = Invoke-Bridge "POST" "/commands/stop_recording" @{} 90
  Write-JsonFile (Join-Path $OutDir "stop-recording.json") $recordStop
  Wait-SessionState { param($s) ([int]$s.videoCount -ge 1) -and ($s.isRecording -eq $false) } 90 "video-count" | Out-Null

  $uploadTerminal = Wait-UploadTerminal 150
  Write-JsonFile (Join-Path $OutDir "upload-terminal.json") $uploadTerminal

  if ($supportsScreenshot) {
    $screenAfter = Invoke-Bridge "POST" "/commands/capture_screenshot" @{
      name = "$TargetId-after-capture"
      pixelRatio = 1.0
    } 30
    Write-JsonFile (Join-Path $OutDir "screenshot-after.json") $screenAfter
    Copy-IfExists $screenAfter.result.filePath (Join-Path $OutDir "screenshots") | Out-Null
  } else {
    Write-JsonFile (Join-Path $OutDir "screenshot-after.json") @{
      status = "skipped"
      reason = "capture_screenshot command is not available in this remote checkout"
    }
  }

  $logs = Invoke-Bridge "GET" "/logs" $null 30
  Write-JsonFile (Join-Path $OutDir "logs.json") $logs
  $mediaPaths = Extract-MediaPaths $logs
  $copiedPhoto = Copy-IfExists $mediaPaths.photo (Join-Path $OutDir "media")
  $copiedVideo = Copy-IfExists $mediaPaths.video (Join-Path $OutDir "media")

  $end = Invoke-Bridge "POST" "/commands/end_session" @{} 60
  Write-JsonFile (Join-Path $OutDir "end-session.json") $end

  $status = "passed"
  $summary.photoPath = $mediaPaths.photo
  $summary.videoPath = $mediaPaths.video
  $summary.copiedPhoto = $copiedPhoto
  $summary.copiedVideo = $copiedVideo
  $summary.uploadedLineCount = $uploadTerminal.uploadedLineCount
  $summary.failedUploadLineCount = $uploadTerminal.failedLineCount
  $summary.failedUploadLines = $uploadTerminal.failedLines
  $summary.selectedCameraName = $preferredCamera
  $summary.cameraNames = $cameraNames
  $summary.supportsScreenshot = $supportsScreenshot
} catch {
  $summary.error = $_.Exception.Message
  try {
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
  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}
