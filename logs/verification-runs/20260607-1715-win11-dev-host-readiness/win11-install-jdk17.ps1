$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$JdkRoot = "C:\src\jdk-17"
$ZipPath = "C:\src\temurin-jdk17.zip"
$ExtractRoot = "C:\src\temurin-jdk17-extract"
$DownloadUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"

Write-Output ""
Write-Output "=== user-local-jdk17 ==="
New-Item -ItemType Directory -Force -Path "C:\src" | Out-Null

if (-not (Test-Path (Join-Path $JdkRoot "bin\java.exe"))) {
  Remove-Item -Recurse -Force $ExtractRoot -ErrorAction SilentlyContinue
  Remove-Item -Force $ZipPath -ErrorAction SilentlyContinue
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath
  Expand-Archive -Path $ZipPath -DestinationPath $ExtractRoot -Force
  $Inner = Get-ChildItem $ExtractRoot -Directory | Select-Object -First 1
  if ($null -eq $Inner) {
    throw "No JDK directory found after extracting $ZipPath"
  }
  Remove-Item -Recurse -Force $JdkRoot -ErrorAction SilentlyContinue
  Move-Item -Path $Inner.FullName -Destination $JdkRoot
}

[Environment]::SetEnvironmentVariable("JAVA17_HOME", $JdkRoot, "User")
Write-Output "JAVA17_HOME=$JdkRoot"
& (Join-Path $JdkRoot "bin\java.exe") -version
