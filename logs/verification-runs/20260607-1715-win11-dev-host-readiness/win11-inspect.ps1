$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

function Run($Name, [string]$Command) {
  Write-Output "-- $Name"
  try {
    Invoke-Expression $Command 2>&1 | ForEach-Object { "$_" }
  } catch {
    Write-Output "ERROR: $($_.Exception.Message)"
  }
}

function CommandPath($Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) {
    Write-Output "$Name=$($cmd.Source)"
  } else {
    Write-Output "$Name=<missing>"
  }
}

Section "identity"
Run "hostname" "hostname"
Run "whoami" "whoami"
Run "windows version" "cmd /c ver"
Run "powershell version" "`$PSVersionTable | Format-List"
Run "admin" "[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() | ForEach-Object { `$_.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }"
Run "computer info" "Get-ComputerInfo -Property OsName,OsVersion,OsBuildNumber,OsArchitecture,WindowsProductName,WindowsVersion | Format-List"
Run "disk" "Get-PSDrive -PSProvider FileSystem | Format-Table -AutoSize"

Section "commands"
@(
  "winget",
  "git",
  "pwsh",
  "code",
  "flutter",
  "dart",
  "java",
  "adb",
  "sdkmanager",
  "avdmanager",
  "cmake",
  "ninja",
  "cl",
  "wsl",
  "usbipd",
  "ffmpeg",
  "python",
  "where"
) | ForEach-Object { CommandPath $_ }

Section "versions"
Run "winget --version" "winget --version"
Run "git --version" "git --version"
Run "pwsh --version" "pwsh --version"
Run "code --version" "code --version"
Run "flutter --version" "flutter --version"
Run "flutter config --list" "flutter config --list"
Run "java -version" "java -version"
Run "adb version" "adb version"
Run "sdkmanager --version" "sdkmanager --version"
Run "cmake --version" "cmake --version"
Run "ninja --version" "ninja --version"
Run "ffmpeg -version" "ffmpeg -version"
Run "python --version" "python --version"

Section "visual studio"
Run "vswhere" "`$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\\Installer\\vswhere.exe'; if (Test-Path `$vswhere) { & `$vswhere -all -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath } else { '<missing>' }"
Run "vswhere json" "`$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\\Installer\\vswhere.exe'; if (Test-Path `$vswhere) { & `$vswhere -all -products * -format json } else { '<missing>' }"

Section "android sdk"
Run "env android" "Get-ChildItem Env:ANDROID* | Format-Table -AutoSize"
Run "sdk dirs" "@(`$env:ANDROID_HOME, `$env:ANDROID_SDK_ROOT, Join-Path `$env:LOCALAPPDATA 'Android\\Sdk') | Sort-Object -Unique | ForEach-Object { if (`$_) { Write-Output `$_; if (Test-Path `$_) { Get-ChildItem `$_ -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 80 FullName } } }"

Section "wsl"
Run "wsl status" "wsl --status"
Run "wsl list verbose" "wsl -l -v"

Section "repo"
Run "repo candidate" "`$paths = @(`"$env:USERPROFILE\\src\\work\\hydracamv2`", `"$env:USERPROFILE\\src\\hydracamv2`", `"$env:USERPROFILE\\hydracamv2`"); foreach (`$p in `$paths) { Write-Output `$p; if (Test-Path `$p) { git -C `$p status -sb; git -C `$p remote -v } }"

Section "usb"
Run "adb devices" "adb devices -l"
Run "usbipd list" "usbipd list"
Run "camera pnp" "Get-PnpDevice -PresentOnly | Where-Object { `$_.Class -match 'Camera|Image|Media|USB' -or `$_.FriendlyName -match 'camera|webcam|usb video|android|samsung|xiaomi|adb' } | Sort-Object Class,FriendlyName | Format-Table -AutoSize"
Run "ffmpeg directshow devices" "ffmpeg -hide_banner -list_devices true -f dshow -i dummy"
