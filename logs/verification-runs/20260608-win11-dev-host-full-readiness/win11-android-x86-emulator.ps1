$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$EvidenceRoot = "C:\Users\jose\codex-win11-dev-host-full-readiness"
$Repo = "D:\src\work\hydracamv2"
$FlutterRoot = "C:\src\flutter"
$Flutter = Join-Path $FlutterRoot "bin\flutter.bat"
$AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$JbrHome = Join-Path $env:LOCALAPPDATA "Programs\Android Studio Fixed\jbr"
$AvdRoot = "D:\android-avd"
$AndroidHome = "D:\android-home"
$AvdName = "HydraCam_API33_x86_64"
$PackageName = "com.amaia23.hydracam"
$Failures = @()

New-Item -ItemType Directory -Force -Path $EvidenceRoot, $AvdRoot, $AndroidHome, "D:\tmp", "D:\pub-cache", "D:\gradle-cache" | Out-Null

$env:JAVA_HOME = $JbrHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_AVD_HOME = $AvdRoot
$env:ANDROID_SDK_HOME = $AndroidHome
$env:PUB_CACHE = "D:\pub-cache"
$env:GRADLE_USER_HOME = "D:\gradle-cache"
$env:TEMP = "D:\tmp"
$env:TMP = "D:\tmp"
$env:PATH = (Join-Path $FlutterRoot "bin") + ";" +
  (Join-Path $JbrHome "bin") + ";" +
  (Join-Path $AndroidSdk "platform-tools") + ";" +
  (Join-Path $AndroidSdk "emulator") + ";" +
  (Join-Path $AndroidSdk "cmdline-tools\latest\bin") + ";" +
  $env:PATH

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

function Run-Step($Name, [scriptblock]$Block) {
  Section $Name
  $global:LASTEXITCODE = 0
  try {
    & $Block
    $exitCode = $global:LASTEXITCODE
    if ($null -eq $exitCode) {
      $exitCode = 0
    }
    Write-Output "[step-exit-code] $exitCode"
    if ($exitCode -ne 0) {
      $script:Failures += "$Name exited $exitCode"
    }
  } catch {
    Write-Output "[step-exception] $($_.Exception.Message)"
    $script:Failures += "$Name exception"
  }
}

Section "context"
Write-Output "timestamp=$(Get-Date -Format o)"
Write-Output "repo=$Repo"
Write-Output "android_sdk=$AndroidSdk"
Write-Output "android_avd_home=$env:ANDROID_AVD_HOME"
Write-Output "android_sdk_home=$env:ANDROID_SDK_HOME"
Write-Output "avd_name=$AvdName"
if (-not (Test-Path $Repo)) {
  Write-Output "BLOCKER: repo checkout missing at $Repo"
  exit 1
}
git -C $Repo status -sb --untracked-files=no
git -C $Repo rev-parse HEAD

Run-Step "sdkmanager list_installed" {
  sdkmanager --list_installed
}

$image = "system-images;android-33;google_apis;x86_64"
$installedImages = sdkmanager --list_installed | Select-String "system-images;android-33;google_apis;x86_64"
if (-not $installedImages) {
  Run-Step "install android 33 x86_64 system image" {
    sdkmanager $image
  }
}

Run-Step "create avd" {
  $existing = avdmanager list avd | Select-String "Name: $AvdName"
  if ($existing) {
    Write-Output "avd_exists=$AvdName"
  } else {
    "no" | avdmanager create avd -n $AvdName -k $image --device "pixel_5" --force
  }
}

Run-Step "emulator accel-check" {
  emulator -accel-check
}

Section "start emulator"
$adb = Join-Path $AndroidSdk "platform-tools\adb.exe"
$emulator = Join-Path $AndroidSdk "emulator\emulator.exe"
& $adb start-server
& $adb devices -l
$running = & $adb devices | Select-String "emulator-"
if ($running) {
  Write-Output "existing_emulator=$running"
} else {
  $stdout = Join-Path $EvidenceRoot "emulator-stdout.txt"
  $stderr = Join-Path $EvidenceRoot "emulator-stderr.txt"
  $args = @(
    "-avd", $AvdName,
    "-no-window",
    "-no-audio",
    "-no-boot-anim",
    "-gpu", "swiftshader_indirect",
    "-netdelay", "none",
    "-netspeed", "full"
  )
  $process = Start-Process -FilePath $emulator -ArgumentList $args -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  Write-Output "emulator_pid=$($process.Id)"
}

Section "wait for boot"
$booted = $false
for ($i = 0; $i -lt 180; $i++) {
  Start-Sleep -Seconds 2
  $devices = & $adb devices
  $deviceLine = $devices | Select-String "emulator-.*device"
  if ($deviceLine) {
    $boot = (& $adb -e shell getprop sys.boot_completed 2>$null).Trim()
    Write-Output "boot_poll=$i boot=$boot"
    if ($boot -eq "1") {
      $booted = $true
      break
    }
  } elseif (($i % 15) -eq 0) {
    Write-Output "boot_poll=$i waiting_for_device"
  }
}

& $adb devices -l
if (-not $booted) {
  Write-Output "BOOT_BLOCKER: emulator did not finish booting"
  $Failures += "emulator boot incomplete"
} else {
  Run-Step "flutter devices with emulator" {
    & $Flutter devices
  }

  Run-Step "flutter clean windows metadata" {
    Push-Location $Repo
    & $Flutter clean
    Pop-Location
  }

  Run-Step "flutter pub get windows metadata" {
    Push-Location $Repo
    & $Flutter pub get
    Pop-Location
  }

  Run-Step "flutter build apk debug android-x64" {
    Push-Location $Repo
    & $Flutter build apk --debug --target-platform android-x64
    Pop-Location
  }

  Run-Step "install apk" {
    $apk = Join-Path $Repo "build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $apk) {
      & $adb -e install -r $apk
    } else {
      Write-Output "apk_missing=$apk"
      exit 1
    }
  }

  Run-Step "launch app package" {
    & $adb -e shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1
  }

  Run-Step "capture emulator state" {
    & $adb -e shell getprop ro.product.cpu.abi
    & $adb -e shell getprop ro.build.version.release
    & $adb -e shell pidof $PackageName
    & $adb -e logcat -d -t 250
  }
}

Section "summary"
if ($Failures.Count -eq 0) {
  Write-Output "result=passed"
  exit 0
}

Write-Output "result=partial"
$Failures | ForEach-Object { Write-Output "failure=$_" }
exit 1
