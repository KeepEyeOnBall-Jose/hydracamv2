$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$Repo = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$Flutter = "C:\src\flutter\bin\flutter.bat"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PATH = "C:\src\flutter\bin;" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
  $env:PATH

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

Section "generic-symlink-test"
$Tmp = Join-Path $env:TEMP "hydracam-symlink-test"
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $Tmp "target\windows") | Out-Null
"ok" | Set-Content -Path (Join-Path $Tmp "target\windows\marker.txt")
try {
  New-Item -ItemType SymbolicLink -Path (Join-Path $Tmp "link") -Target (Join-Path $Tmp "target") | Format-List FullName,LinkType,Target
  Write-Output ("link-child-exists=" + (Test-Path (Join-Path $Tmp "link\windows\marker.txt")))
} catch {
  Write-Output ("symlink-exception=" + $_.Exception.Message)
}

Section "clean-windows-plugin-symlinks"
Remove-Item -Recurse -Force (Join-Path $Repo "windows\flutter\ephemeral\.plugin_symlinks") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $Repo "build\windows") -ErrorAction SilentlyContinue

Section "flutter-build-windows-diagnostic"
Push-Location $Repo
& $Flutter build windows --debug
Write-Output ("build-exit-code=" + $LASTEXITCODE)
Pop-Location

Section "plugin-symlink-state"
$SymlinkRoot = Join-Path $Repo "windows\flutter\ephemeral\.plugin_symlinks"
if (Test-Path $SymlinkRoot) {
  Get-ChildItem $SymlinkRoot | ForEach-Object {
    $WindowsChild = Join-Path $_.FullName "windows"
    [pscustomobject]@{
      Name = $_.Name
      Mode = $_.Mode
      LinkType = $_.LinkType
      Target = ($_.Target -join ";")
      WindowsChildExists = (Test-Path $WindowsChild)
      FullName = $_.FullName
    }
  } | ConvertTo-Csv -NoTypeInformation
} else {
  Write-Output "plugin-symlink-root-missing"
}

exit 0
