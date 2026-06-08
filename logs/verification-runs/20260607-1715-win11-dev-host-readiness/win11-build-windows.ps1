$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoDir = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$Flutter = "C:\src\flutter\bin\flutter.bat"
$env:JAVA_HOME = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = "C:\src\flutter\bin;" +
  (Join-Path $env:JAVA_HOME "bin") + ";" +
  (Join-Path $env:ANDROID_HOME "platform-tools") + ";" +
  $env:PATH

Push-Location $RepoDir
& $Flutter pub get
if ($LASTEXITCODE -ne 0) {
  $exitCode = $LASTEXITCODE
  Write-Output "pub_get_exit_code=$exitCode"
  Pop-Location
  exit $exitCode
}

$pluginLinks = Join-Path $RepoDir "windows\flutter\ephemeral\.plugin_symlinks"
if (Test-Path $pluginLinks) {
  Get-ChildItem $pluginLinks -Force | ForEach-Object {
    if ($_.LinkType -eq "SymbolicLink") {
      $target = $_.Target[0]
      $name = $_.Name
      Remove-Item -Force $_.FullName
      Copy-Item -Recurse -Force $target (Join-Path $pluginLinks $name)
      Write-Output "materialized-plugin=$name"
    }
  }
}

& $Flutter build windows --debug --no-pub
$exitCode = $LASTEXITCODE
Write-Output "step_exit_code=$exitCode"
Pop-Location
exit $exitCode
