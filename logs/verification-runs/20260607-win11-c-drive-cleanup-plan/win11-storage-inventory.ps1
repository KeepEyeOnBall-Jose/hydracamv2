$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Convert-BytesToGiB([Nullable[Int64]]$Bytes) {
  if ($null -eq $Bytes) {
    return $null
  }
  return [Math]::Round($Bytes / 1GB, 2)
}

function Get-DirectorySize([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return [PSCustomObject]@{
      path = $Path
      exists = $false
      bytes = $null
      gib = $null
      error = $null
    }
  }

  try {
    $sum = Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
      Where-Object { -not $_.PSIsContainer } |
      Measure-Object -Property Length -Sum
    return [PSCustomObject]@{
      path = $Path
      exists = $true
      bytes = [Int64]($sum.Sum)
      gib = Convert-BytesToGiB ([Int64]($sum.Sum))
      error = $null
    }
  } catch {
    return [PSCustomObject]@{
      path = $Path
      exists = $true
      bytes = $null
      gib = $null
      error = $_.Exception.Message
    }
  }
}

function Get-ChildDirectorySizes([string]$Path, [int]$Limit = 25) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  $items = @()
  Get-ChildItem -LiteralPath $Path -Force -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
      $items += Get-DirectorySize $_.FullName
    }

  return @($items | Sort-Object bytes -Descending | Select-Object -First $Limit)
}

function Get-LargeFiles([string[]]$Paths, [int]$Limit = 50) {
  $files = @()
  foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }
    Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge 250MB } |
      ForEach-Object {
        $files += [PSCustomObject]@{
          path = $_.FullName
          bytes = [Int64]$_.Length
          gib = Convert-BytesToGiB ([Int64]$_.Length)
          lastWriteTime = $_.LastWriteTime.ToString("o")
        }
      }
  }

  return @($files | Sort-Object bytes -Descending | Select-Object -First $Limit)
}

function Get-ReparsePoints([string[]]$Paths) {
  $points = @()
  foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }
    Get-ChildItem -LiteralPath $path -Force -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue |
      Select-Object -First 100 |
      ForEach-Object {
        $target = $null
        try {
          $target = $_.Target -join ";"
        } catch {
          $target = $null
        }
        $points += [PSCustomObject]@{
          path = $_.FullName
          type = $_.LinkType
          target = $target
        }
      }
  }
  return @($points)
}

$user = $env:USERPROFILE
$local = $env:LOCALAPPDATA
$roaming = $env:APPDATA
$pathsOfInterest = @(
  "C:\src",
  "C:\src\flutter",
  "C:\src\jdk-17",
  "$user\src",
  "$user\src\work\hydracamv2",
  "$user\.gradle",
  "$local\Android",
  "$local\Android\Sdk",
  "$local\Pub",
  "$local\Pub\Cache",
  "$local\Temp",
  "$local\Programs",
  "$local\Packages",
  "$local\Docker",
  "$local\Microsoft\WindowsApps",
  "$roaming",
  "$user\Downloads",
  "C:\ProgramData\chocolatey",
  "C:\ProgramData\Package Cache",
  "C:\Program Files\Microsoft Visual Studio",
  "C:\Program Files\Android",
  "C:\Program Files\Docker",
  "C:\Windows\SoftwareDistribution\Download",
  "D:\src",
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

$wingetPackages = @()
try {
  $wingetPackages = winget list --accept-source-agreements 2>$null |
    Select-String -Pattern "Android|Flutter|Visual Studio|Docker|WSL|JDK|Java|Temurin|Git|Node|Python|Gradle|Chocolatey|Cursor|Code|VS Code" |
    ForEach-Object { "$_" }
} catch {
  $wingetPackages = @("winget list failed: $($_.Exception.Message)")
}

$wslStatus = @()
try {
  $wslStatus = wsl -l -v 2>$null | ForEach-Object { "$_" }
} catch {
  $wslStatus = @("wsl list failed: $($_.Exception.Message)")
}

$vhdPaths = @()
$vhdSearchRoots = @("$local\Packages", "$local\Docker", "C:\ProgramData\DockerDesktop", "D:\wsl", "D:\docker")
foreach ($root in $vhdSearchRoots) {
  if (Test-Path -LiteralPath $root) {
    Get-ChildItem -LiteralPath $root -Force -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in @(".vhdx", ".vhd") } |
      ForEach-Object {
        $vhdPaths += [PSCustomObject]@{
          path = $_.FullName
          bytes = [Int64]$_.Length
          gib = Convert-BytesToGiB ([Int64]$_.Length)
          lastWriteTime = $_.LastWriteTime.ToString("o")
        }
      }
  }
}

$inventory = [PSCustomObject]@{
  capturedAt = (Get-Date).ToString("o")
  host = hostname
  user = whoami
  adminToken = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  logicalDisks = @($logicalDisks)
  commandSources = @($commands)
  environmentVariables = @($envVars)
  pathSizes = @($pathsOfInterest | ForEach-Object { Get-DirectorySize $_ })
  cUsersJoseTop = @(Get-ChildDirectorySizes $user 40)
  cUsersJoseLocalTop = @(Get-ChildDirectorySizes $local 40)
  cProgramDataTop = @(Get-ChildDirectorySizes "C:\ProgramData" 40)
  cSrcTop = @(Get-ChildDirectorySizes "C:\src" 20)
  dRootTop = @(Get-ChildDirectorySizes "D:\" 40)
  largeFiles = @(Get-LargeFiles @($user, "C:\src", "C:\ProgramData") 60)
  vhdImages = @($vhdPaths | Sort-Object bytes -Descending)
  reparsePoints = @(Get-ReparsePoints @($user, "C:\src", "D:\src"))
  wslStatus = @($wslStatus)
  wingetPackages = @($wingetPackages)
}

$inventory | ConvertTo-Json -Depth 8
