$ErrorActionPreference = "Continue"

$Root = "D:\hydracam-evidence\20260609-0415-win11-android-studio-quail-e-drive-move"
$SdkRoot = "C:\Users\jose\AppData\Local\Android\Sdk"
$SdkManager = Join-Path $SdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
$OutDir = Join-Path $Root "sdk-update"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $SdkManager)) {
  throw "sdkmanager not found: $SdkManager"
}

$licenseInput = Join-Path $OutDir "yes-input.txt"
Set-Content -LiteralPath $licenseInput -Value (("y`r`n" * 120)) -Encoding ascii

cmd.exe /c "type `"$licenseInput`" | `"$SdkManager`" --sdk_root=`"$SdkRoot`" --licenses" `
  > (Join-Path $OutDir "licenses.stdout.txt") `
  2> (Join-Path $OutDir "licenses.stderr.txt")
$licensesExitCode = $LASTEXITCODE

cmd.exe /c "type `"$licenseInput`" | `"$SdkManager`" --sdk_root=`"$SdkRoot`" --install `"cmdline-tools;latest`" `"build-tools;36.1.0`" `"platforms;android-36`" `"platform-tools`" `"emulator`"" `
  > (Join-Path $OutDir "install.stdout.txt") `
  2> (Join-Path $OutDir "install.stderr.txt")
$installExitCode = $LASTEXITCODE

cmd.exe /c "`"$SdkManager`" --sdk_root=`"$SdkRoot`" --list_installed" `
  > (Join-Path $OutDir "list-installed.stdout.txt") `
  2> (Join-Path $OutDir "list-installed.stderr.txt")
$listExitCode = $LASTEXITCODE

$summary = [ordered]@{
  sdkRoot = $SdkRoot
  sdkManager = $SdkManager
  licensesExitCode = $licensesExitCode
  installExitCode = $installExitCode
  listExitCode = $listExitCode
  installedHighlights = Select-String -LiteralPath (Join-Path $OutDir "list-installed.stdout.txt") -Pattern "cmdline-tools;latest|build-tools;36.1.0|platform-tools|emulator|platforms;android-36" |
    ForEach-Object { $_.Line.Trim() }
  stderr = @{
    licenses = Get-Content -LiteralPath (Join-Path $OutDir "licenses.stderr.txt") -Raw
    install = Get-Content -LiteralPath (Join-Path $OutDir "install.stderr.txt") -Raw
    list = Get-Content -LiteralPath (Join-Path $OutDir "list-installed.stderr.txt") -Raw
  }
  endedAt = (Get-Date).ToString("o")
}
$summary | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath (Join-Path $OutDir "summary.json") -Encoding utf8
Get-Content -LiteralPath (Join-Path $OutDir "summary.json") -Raw
