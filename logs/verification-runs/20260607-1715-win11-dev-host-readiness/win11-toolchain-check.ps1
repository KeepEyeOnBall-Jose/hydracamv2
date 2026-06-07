$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Say($Name, $Value) {
  Write-Output "$Name=$Value"
}

Say "hostname" (hostname)
Say "user" ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say "admin_token" $isAdmin

Write-Output "=== local administrators ==="
try {
  Get-LocalGroupMember -Group "Administrators" | ForEach-Object {
    Write-Output "$($_.ObjectClass) $($_.Name)"
  }
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
}

Write-Output "=== visual studio ==="
$programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
$vswhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
Say "vswhere" $vswhere
if (Test-Path $vswhere) {
  & $vswhere -all -products * -format json
  Write-Output "=== native desktop workload ==="
  & $vswhere -all -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
} else {
  Write-Output "<missing>"
}

Write-Output "=== command lookup ==="
foreach ($name in @("cl", "cmake", "ninja", "msbuild", "devenv", "vswhere")) {
  Write-Output "-- $name"
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) {
    Write-Output $cmd.Source
  } else {
    Write-Output "<missing>"
  }
}

Write-Output "=== paths ==="
Say "PATH" $env:PATH
Say "ANDROID_HOME" $env:ANDROID_HOME
Say "ANDROID_SDK_ROOT" $env:ANDROID_SDK_ROOT
Say "JAVA_HOME" $env:JAVA_HOME
