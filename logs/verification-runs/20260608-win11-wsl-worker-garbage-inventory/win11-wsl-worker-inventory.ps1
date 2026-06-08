$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Section($Name) {
  Write-Output ""
  Write-Output "### $Name"
}

function Convert-BytesToGiB([Nullable[Int64]]$Bytes) {
  if ($null -eq $Bytes) {
    return $null
  }
  return [Math]::Round($Bytes / 1GB, 2)
}

function Measure-PathWithTimeout([string]$Path, [int]$TimeoutSeconds = 15) {
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

function Get-PackageRootCandidates {
  $localPackages = Join-Path $env:LOCALAPPDATA "Packages"
  if (-not (Test-Path -LiteralPath $localPackages)) {
    return @()
  }

  Get-ChildItem -LiteralPath $localPackages -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "Ubuntu|Canonical|Docker" } |
    ForEach-Object {
      $localState = Join-Path $_.FullName "LocalState"
      $vhd = Join-Path $localState "ext4.vhdx"
      $rootfs = Join-Path $localState "rootfs"
      $vhdItem = if (Test-Path -LiteralPath $vhd) { Get-Item -LiteralPath $vhd -Force } else { $null }
      [PSCustomObject]@{
        package = $_.Name
        path = $_.FullName
        localState = $localState
        hasVhd = [bool]$vhdItem
        vhdPath = if ($vhdItem) { $vhdItem.FullName } else { $null }
        vhdGiB = if ($vhdItem) { Convert-BytesToGiB ([Int64]$vhdItem.Length) } else { $null }
        vhdLastWriteTime = if ($vhdItem) { $vhdItem.LastWriteTime.ToString("o") } else { $null }
        rootfs = if (Test-Path -LiteralPath $rootfs) { $rootfs } else { $null }
      }
    }
}

$runRoot = "D:\_archive\win11-wsl-worker-garbage-inventory\20260608"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$scriptWindows = Join-Path $env:USERPROFILE "win11-wsl-worker-inventory.sh"
$scriptWsl = "/mnt/c/Users/jose/win11-wsl-worker-inventory.sh"
$distros = @("Ubuntu-20.04", "Ubuntu-22.04")

Section "windows-identity"
hostname
whoami
cmd /c ver

Section "wsl-list"
wsl -l -v

Section "package-root-candidates"
$packageCandidates = @(Get-PackageRootCandidates)
$packageCandidates | ConvertTo-Json -Depth 5

Section "package-root-sizes"
$packageCandidates |
  Where-Object { $_.rootfs } |
  ForEach-Object { Measure-PathWithTimeout $_.rootfs 20 } |
  ConvertTo-Json -Depth 5

Section "per-distro-linux-inventory"
foreach ($distro in $distros) {
  Write-Output ""
  Write-Output "#### $distro"
  $outFile = Join-Path $runRoot "$($distro)-linux-inventory.txt"
  $errFile = Join-Path $runRoot "$($distro)-linux-inventory.stderr.txt"
  $exists = $false
  $list = wsl -l -q 2>$null
  foreach ($line in $list) {
    if (($line -replace "`0", "").Trim() -eq $distro) {
      $exists = $true
    }
  }
  if (-not $exists) {
    Write-Output "missing=$distro"
    continue
  }

  $start = Get-Date
  wsl -d $distro -u root -- bash $scriptWsl > $outFile 2> $errFile
  $exitCode = $LASTEXITCODE
  $end = Get-Date
  [PSCustomObject]@{
    distro = $distro
    exitCode = $exitCode
    startedAt = $start.ToString("o")
    endedAt = $end.ToString("o")
    outputFile = $outFile
    errorFile = $errFile
  } | ConvertTo-Json -Depth 4
}

Section "run-root"
Write-Output $runRoot
