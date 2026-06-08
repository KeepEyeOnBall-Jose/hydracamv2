$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$Repo = "D:\src\work\hydracamv2"
$Flutter = "C:\src\flutter\bin\flutter.bat"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:GRADLE_USER_HOME = "D:\gradle-cache"
$env:PUB_CACHE = "D:\pub-cache"
$env:TEMP = "D:\tmp"
$env:TMP = "D:\tmp"
$env:PATH = "C:\src\flutter\bin;" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
  (Join-Path $AndroidSdk "cmdline-tools\latest\bin") + ";" +
  $env:PATH

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

Section "disk-before"
Get-PSDrive -PSProvider FileSystem |
  Select-Object Name, Used, Free, Root |
  ConvertTo-Csv -NoTypeInformation

Section "prepare-d-drive-checkout"
New-Item -ItemType Directory -Force -Path "D:\src\work", $env:GRADLE_USER_HOME, $env:PUB_CACHE, $env:TEMP | Out-Null
Remove-Item -Recurse -Force $Repo -ErrorAction SilentlyContinue
git clone --no-checkout --filter=blob:none --branch master-jose-2025 https://github.com/KeepEyeOnBall-Jose/hydracamv2.git $Repo
git -C $Repo config core.longpaths true
git -C $Repo config core.filemode false
git -C $Repo sparse-checkout init --no-cone
@(
  "/android/",
  "/ios/",
  "/lib/",
  "/test/",
  "/windows/",
  "/linux/",
  "/web/",
  "/macos/",
  "/integration_test/",
  "/docs/",
  "/automation_scenarios/",
  "/analysis_options.yaml",
  "/pubspec.yaml",
  "/pubspec.lock"
) | git -C $Repo sparse-checkout set --stdin --no-cone
git -C $Repo checkout master-jose-2025
git -C $Repo status -sb --untracked-files=no
git -C $Repo rev-parse HEAD

Section "flutter-pub-get-d"
Push-Location $Repo
& $Flutter pub get
Write-Output ("pub-get-exit-code=" + $LASTEXITCODE)

Section "flutter-build-apk-debug-d"
& $Flutter build apk --debug
$buildExit = $LASTEXITCODE
Write-Output ("apk-build-exit-code=" + $buildExit)
if (Test-Path (Join-Path $Repo "build\app\outputs\flutter-apk")) {
  Get-ChildItem (Join-Path $Repo "build\app\outputs\flutter-apk") |
    Select-Object Name, Length, LastWriteTime |
    ConvertTo-Csv -NoTypeInformation
}
Pop-Location

Section "disk-after"
Get-PSDrive -PSProvider FileSystem |
  Select-Object Name, Used, Free, Root |
  ConvertTo-Csv -NoTypeInformation

exit $buildExit
