$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Convert-BytesToGiB([Nullable[Int64]]$Bytes) {
  if ($null -eq $Bytes) {
    return $null
  }
  return [Math]::Round($Bytes / 1GB, 2)
}

function Measure-PathWithTimeout([string]$Path, [int]$TimeoutSeconds = 12) {
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

function Get-FileSizeIfPresent([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return [PSCustomObject]@{
      path = $Path
      exists = $false
      bytes = $null
      gib = $null
      lastWriteTime = $null
    }
  }

  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return [PSCustomObject]@{
    path = $Path
    exists = $true
    bytes = [Int64]$item.Length
    gib = Convert-BytesToGiB ([Int64]$item.Length)
    lastWriteTime = $item.LastWriteTime.ToString("o")
  }
}

function Get-DirectoryChildren([string]$Path, [int]$Limit = 80) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  return @(
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
      Sort-Object PSIsContainer, Name |
      Select-Object -First $Limit |
      ForEach-Object {
        [PSCustomObject]@{
          parent = $Path
          name = $_.Name
          fullName = $_.FullName
          mode = $_.Mode
          length = if ($_.PSIsContainer) { $null } else { [Int64]$_.Length }
          gib = if ($_.PSIsContainer) { $null } else { Convert-BytesToGiB ([Int64]$_.Length) }
          lastWriteTime = $_.LastWriteTime.ToString("o")
        }
      }
  )
}

$user = $env:USERPROFILE
$local = $env:LOCALAPPDATA
$roaming = $env:APPDATA
$pathsToMeasure = @(
  "C:\src",
  "C:\src\flutter",
  "C:\src\jdk-17",
  "$user\src",
  "$user\src\work",
  "$user\src\work\hydracamv2",
  "$user\.gradle",
  "$local\Android",
  "$local\Android\Sdk",
  "$local\Pub",
  "$local\Pub\Cache",
  "$local\Temp",
  "$local\Programs",
  "$local\Programs\Android Studio",
  "$local\Programs\Android Studio Fixed",
  "$local\Programs\cursor",
  "$local\Programs\Microsoft VS Code",
  "$local\Docker",
  "$roaming\Code",
  "$roaming\Cursor",
  "$user\Downloads",
  "C:\ProgramData\chocolatey",
  "C:\ProgramData\Package Cache",
  "C:\Program Files\Microsoft Visual Studio",
  "C:\Program Files\Android",
  "C:\Windows\SoftwareDistribution\Download",
  "D:\src",
  "D:\src\work",
  "D:\src\work\hydracamv2",
  "D:\gradle-cache",
  "D:\pub-cache",
  "D:\tmp"
) | Sort-Object -Unique

$logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" |
  Select-Object DeviceID, VolumeName, FileSystem,
    @{ Name = "sizeGiB"; Expression = { Convert-BytesToGiB ([Int64]$_.Size) } },
    @{ Name = "freeGiB"; Expression = { Convert-BytesToGiB ([Int64]$_.FreeSpace) } },
    @{ Name = "freePercent"; Expression = { if ($_.Size) { [Math]::Round(100 * $_.FreeSpace / $_.Size, 2) } else { $null } } }

$envVars = @("ANDROID_HOME", "ANDROID_SDK_ROOT", "JAVA_HOME", "JAVA17_HOME", "GRADLE_USER_HOME", "PUB_CACHE", "TEMP", "TMP", "Path") |
  ForEach-Object {
    [PSCustomObject]@{
      name = $_
      user = [Environment]::GetEnvironmentVariable($_, "User")
      machine = [Environment]::GetEnvironmentVariable($_, "Machine")
      process = [Environment]::GetEnvironmentVariable($_, "Process")
    }
  }

$commands = @("flutter", "dart", "java", "adb", "sdkmanager", "gradle", "git", "winget", "wsl", "docker", "code", "pwsh") |
  ForEach-Object {
    $cmd = Get-Command $_ -ErrorAction SilentlyContinue
    [PSCustomObject]@{
      name = $_
      source = if ($cmd) { $cmd.Source } else { $null }
    }
  }

$knownLargeFiles = @(
  "C:\hiberfil.sys",
  "C:\pagefile.sys",
  "C:\swapfile.sys",
  "$local\Docker\wsl\data\ext4.vhdx",
  "$local\Docker\wsl\distro\ext4.vhdx",
  "C:\ProgramData\DockerDesktop\vm-data\DockerDesktop.vhdx"
)

$vhdCandidates = @()
$packageRoots = Get-ChildItem -LiteralPath "$local\Packages" -Force -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "Canonical|Ubuntu|Docker" }
foreach ($packageRoot in $packageRoots) {
  $vhdCandidates += Join-Path $packageRoot.FullName "LocalState\ext4.vhdx"
}

$largeFiles = @($knownLargeFiles + $vhdCandidates | Sort-Object -Unique | ForEach-Object { Get-FileSizeIfPresent $_ })

$children = @()
foreach ($path in @($user, "$user\src", "$user\src\work", $local, "$local\Programs", "$local\Packages", "C:\src", "C:\ProgramData", "D:\")) {
  $children += Get-DirectoryChildren $path
}

$wslStatus = @()
try {
  $wslStatus = wsl -l -v 2>$null | ForEach-Object { "$_" }
} catch {
  $wslStatus = @("wsl list failed: $($_.Exception.Message)")
}

$wingetPackages = @()
try {
  $wingetPackages = winget list --accept-source-agreements 2>$null |
    Select-String -Pattern "Android|Flutter|Visual Studio|Docker|WSL|JDK|Java|Temurin|Git|Node|Python|Gradle|Chocolatey|Cursor|Code|VS Code" |
    ForEach-Object { "$_" }
} catch {
  $wingetPackages = @("winget list failed: $($_.Exception.Message)")
}

$inventory = [PSCustomObject]@{
  capturedAt = (Get-Date).ToString("o")
  host = hostname
  user = whoami
  adminToken = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  logicalDisks = @($logicalDisks)
  commandSources = @($commands)
  environmentVariables = @($envVars)
  measuredPaths = @($pathsToMeasure | ForEach-Object { Measure-PathWithTimeout $_ })
  knownLargeFiles = @($largeFiles)
  sampledChildren = @($children)
  wslStatus = @($wslStatus)
  wingetPackages = @($wingetPackages)
}

$inventory | ConvertTo-Json -Depth 8
