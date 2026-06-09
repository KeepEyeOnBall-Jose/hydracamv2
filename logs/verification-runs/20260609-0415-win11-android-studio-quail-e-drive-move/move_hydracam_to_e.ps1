$ErrorActionPreference = "Stop"

$Root = "D:\hydracam-evidence\20260609-0415-win11-android-studio-quail-e-drive-move"
$Source = "D:\src\work\hydracamv2"
$DestinationRoot = "E:\work-repos"
$Destination = Join-Path $DestinationRoot "hydracamv2"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MovedAside = "D:\src\work\hydracamv2.moved-to-e-$Stamp"
$LogDir = Join-Path $Root "repo-move"
$EmptyDir = Join-Path $LogDir "empty"
New-Item -ItemType Directory -Force -Path $LogDir, $EmptyDir, $DestinationRoot | Out-Null

Get-Process studio64, studio, java, javaw, flutter, dart, sport_cam_sync, qemu-system-x86_64, emulator -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Source repo does not exist: $Source"
}
if (Test-Path -LiteralPath $Destination) {
  $existing = Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existing) {
    throw "Destination exists and is not empty: $Destination"
  }
}

$copyLog = Join-Path $LogDir "robocopy-copy.log"
robocopy $Source $Destination /MIR /COPY:DAT /DCOPY:DAT /XJ /R:2 /W:2 /MT:16 /NP /LOG:$copyLog
$copyExit = $LASTEXITCODE
if ($copyExit -gt 7) {
  throw "robocopy copy failed with exit code $copyExit; see $copyLog"
}

$verifyLog = Join-Path $LogDir "robocopy-verify-dry-run.log"
robocopy $Source $Destination /MIR /L /BYTES /NP /NFL /NDL /XJ /R:0 /W:0 /LOG:$verifyLog
$verifyExit = $LASTEXITCODE
if ($verifyExit -gt 7) {
  throw "robocopy verify failed with exit code $verifyExit; see $verifyLog"
}

$destGitTop = (& git -C $Destination rev-parse --show-toplevel 2>&1 | Out-String).Trim()
$destBranch = (& git -C $Destination branch --show-current 2>&1 | Out-String).Trim()
$destStatus = (& git -C $Destination status -sb 2>&1 | Out-String).Trim()
if ($destGitTop -ne $Destination) {
  throw "Destination git toplevel mismatch: $destGitTop"
}

Rename-Item -LiteralPath $Source -NewName (Split-Path -Leaf $MovedAside)
cmd.exe /c "mklink /J `"$Source`" `"$Destination`"" |
  Set-Content -LiteralPath (Join-Path $LogDir "mklink-junction.txt") -Encoding utf8

$deleteLog = Join-Path $LogDir "robocopy-delete-old-source.log"
robocopy $EmptyDir $MovedAside /MIR /XJ /R:1 /W:1 /NP /LOG:$deleteLog
$deleteExit = $LASTEXITCODE
if ($deleteExit -gt 7) {
  throw "robocopy delete-old-source failed with exit code $deleteExit; see $deleteLog"
}
Remove-Item -LiteralPath $MovedAside -Force -ErrorAction SilentlyContinue

$sourceItem = Get-Item -LiteralPath $Source
$destinationItem = Get-Item -LiteralPath $Destination
$summary = [ordered]@{
  status = "passed"
  source = $Source
  destination = $Destination
  movedAside = $MovedAside
  sourceAttributes = [string]$sourceItem.Attributes
  destinationExists = $destinationItem.Exists
  copyExitCode = $copyExit
  verifyExitCode = $verifyExit
  deleteExitCode = $deleteExit
  destGitTop = $destGitTop
  destBranch = $destBranch
  destStatus = $destStatus
  copyLog = $copyLog
  verifyLog = $verifyLog
  deleteLog = $deleteLog
  endedAt = (Get-Date).ToString("o")
}
$summary | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath (Join-Path $LogDir "summary.json") -Encoding utf8
Get-Content -LiteralPath (Join-Path $LogDir "summary.json") -Raw
