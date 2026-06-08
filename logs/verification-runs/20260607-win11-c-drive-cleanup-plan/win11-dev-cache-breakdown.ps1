$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Convert-BytesToGiB([Nullable[Int64]]$Bytes) {
  if ($null -eq $Bytes) {
    return $null
  }
  return [Math]::Round($Bytes / 1GB, 2)
}

function Measure-PathWithTimeout([string]$Path, [int]$TimeoutSeconds = 8) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return [PSCustomObject]@{
      path = $Path
      exists = $false
      timedOut = $false
      bytes = $null
      gib = $null
      fileCount = $null
      error = $null
    }
  }

  $job = Start-Job -ScriptBlock {
    param([string]$JobPath)
    $files = Get-ChildItem -LiteralPath $JobPath -Force -Recurse -File -ErrorAction SilentlyContinue
    $sum = $files | Measure-Object -Property Length -Sum
    [PSCustomObject]@{
      bytes = [Int64]$sum.Sum
      fileCount = [Int64]$sum.Count
    }
  } -ArgumentList $Path

  $finished = Wait-Job $job -Timeout $TimeoutSeconds
  if ($null -eq $finished) {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return [PSCustomObject]@{
      path = $Path
      exists = $true
      timedOut = $true
      bytes = $null
      gib = $null
      fileCount = $null
      error = "Timed out after $TimeoutSeconds seconds"
    }
  }

  try {
    $result = Receive-Job $job -ErrorAction Stop
    return [PSCustomObject]@{
      path = $Path
      exists = $true
      timedOut = $false
      bytes = [Int64]$result.bytes
      gib = Convert-BytesToGiB ([Int64]$result.bytes)
      fileCount = [Int64]$result.fileCount
      error = $null
    }
  } catch {
    return [PSCustomObject]@{
      path = $Path
      exists = $true
      timedOut = $false
      bytes = $null
      gib = $null
      fileCount = $null
      error = $_.Exception.Message
    }
  } finally {
    Remove-Job $job -Force -ErrorAction SilentlyContinue
  }
}

function Measure-ImmediateChildren([string]$Root, [int]$TimeoutSeconds = 8) {
  if (-not (Test-Path -LiteralPath $Root)) {
    return @([PSCustomObject]@{
      root = $Root
      path = $Root
      exists = $false
      timedOut = $false
      bytes = $null
      gib = $null
      fileCount = $null
      error = $null
    })
  }

  $children = Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction SilentlyContinue
  return @(
    foreach ($child in $children) {
      $measurement = Measure-PathWithTimeout $child.FullName $TimeoutSeconds
      [PSCustomObject]@{
        root = $Root
        path = $measurement.path
        exists = $measurement.exists
        timedOut = $measurement.timedOut
        bytes = $measurement.bytes
        gib = $measurement.gib
        fileCount = $measurement.fileCount
        error = $measurement.error
      }
    }
  )
}

$user = $env:USERPROFILE
$local = $env:LOCALAPPDATA
$roots = @(
  "$user\.gradle",
  "$local\Android",
  "$local\Android\Sdk",
  "$local\Pub",
  "$local\Pub\Cache",
  "$local\Docker",
  "$user\src",
  "$user\src\work",
  "C:\src",
  "D:\src",
  "D:\src\work",
  "D:\gradle-cache",
  "D:\pub-cache"
) | Sort-Object -Unique

$breakdown = @()
foreach ($root in $roots) {
  $breakdown += Measure-ImmediateChildren $root 8
}

$breakdown | ConvertTo-Json -Depth 5
