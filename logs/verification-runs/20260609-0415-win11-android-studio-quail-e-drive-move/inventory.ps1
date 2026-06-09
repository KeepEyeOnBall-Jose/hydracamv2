$ErrorActionPreference = "Continue"

function Add-CommandResult {
  param(
    [string]$Name,
    [scriptblock]$Script
  )
  try {
    [pscustomobject]@{
      name = $Name
      status = "ok"
      value = & $Script
    }
  } catch {
    [pscustomobject]@{
      name = $Name
      status = "failed"
      error = $_.Exception.Message
    }
  }
}

$paths = @(
  "C:\Program Files\Android\Android Studio",
  "C:\Program Files\Android\Android Studio Preview",
  "C:\Program Files\Android\jdk",
  "C:\Users\jose\AppData\Local\Android\Sdk",
  "C:\Users\jose\AppData\Local\Programs\Android Studio",
  "D:\src\work\hydracamv2",
  "E:\work-repos",
  "E:\work-repos\hydracamv2"
)

$results = @()

$results += Add-CommandResult "paths" {
  foreach ($path in $paths) {
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    [pscustomobject]@{
      path = $path
      exists = $null -ne $item
      fullName = if ($item) { $item.FullName } else { $null }
      attributes = if ($item) { [string]$item.Attributes } else { $null }
      lastWriteTime = if ($item) { $item.LastWriteTime.ToString("o") } else { $null }
    }
  }
}

$results += Add-CommandResult "drives" {
  foreach ($drive in @("C", "D", "E")) {
    $psDrive = Get-PSDrive -Name $drive -ErrorAction SilentlyContinue
    if ($psDrive) {
      [pscustomobject]@{
        drive = $drive
        root = $psDrive.Root
        freeGB = [math]::Round($psDrive.Free / 1GB, 2)
        usedGB = [math]::Round($psDrive.Used / 1GB, 2)
      }
    }
  }
}

$results += Add-CommandResult "androidStudioRegistry" {
  Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Android Studio*" } |
    Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString
}

$results += Add-CommandResult "androidStudioBinaries" {
  $knownCandidates = @(
    "C:\Program Files\Android\Android Studio\bin\studio64.exe",
    "C:\Program Files\Google\Android Studio\bin\studio64.exe",
    "C:\Users\jose\AppData\Local\Programs\Android Studio\bin\studio64.exe",
    "C:\Users\jose\AppData\Local\JetBrains\Toolbox\apps\AndroidStudio\ch-0\*\bin\studio64.exe",
    "C:\Users\jose\AppData\Local\JetBrains\Toolbox\apps\AndroidStudio\ch-1\*\bin\studio64.exe"
  )
  foreach ($candidate in $knownCandidates) {
    Get-Item -Path $candidate -ErrorAction SilentlyContinue |
      ForEach-Object {
        [pscustomobject]@{
          fullName = $_.FullName
          lastWriteTime = $_.LastWriteTime.ToString("o")
          fileVersion = $_.VersionInfo.FileVersion
          productVersion = $_.VersionInfo.ProductVersion
        }
      }
  }
}

$results += Add-CommandResult "productInfo" {
  $productInfos = @()
  $knownProductInfos = @(
    "C:\Program Files\Android\Android Studio\product-info.json",
    "C:\Program Files\Google\Android Studio\product-info.json",
    "C:\Users\jose\AppData\Local\Programs\Android Studio\product-info.json",
    "C:\Users\jose\AppData\Local\JetBrains\Toolbox\apps\AndroidStudio\ch-0\*\product-info.json",
    "C:\Users\jose\AppData\Local\JetBrains\Toolbox\apps\AndroidStudio\ch-1\*\product-info.json"
  )
  foreach ($candidate in $knownProductInfos) {
    Get-Item -Path $candidate -ErrorAction SilentlyContinue |
      ForEach-Object {
        $productInfos += [pscustomobject]@{
          path = $_.FullName
          json = Get-Content -LiteralPath $_.FullName -Raw
        }
      }
  }
  $productInfos
}

$results += Add-CommandResult "wingetAndroidStudio" {
  $list = (& winget list --id Google.AndroidStudio --accept-source-agreements --disable-interactivity 2>&1 | Out-String).Trim()
  $show = (& winget show --id Google.AndroidStudio -e --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String).Trim()
  [pscustomobject]@{
    list = $list
    show = $show
  }
}

$sdkmanager = "C:\Users\jose\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
$results += Add-CommandResult "androidSdkInstalled" {
  if (Test-Path -LiteralPath $sdkmanager) {
    (& $sdkmanager --list_installed 2>&1 | Out-String).Trim()
  } else {
    "sdkmanager not found at $sdkmanager"
  }
}

$results += Add-CommandResult "toolVersions" {
  [pscustomobject]@{
    java = (& java -version 2>&1 | Out-String).Trim()
    flutter = (& flutter --version 2>&1 | Out-String).Trim()
    git = (& git --version 2>&1 | Out-String).Trim()
  }
}

$results += Add-CommandResult "repoState" {
  $states = @()
  foreach ($repo in @("D:\src\work\hydracamv2", "E:\work-repos\hydracamv2")) {
    if (Test-Path -LiteralPath (Join-Path $repo ".git")) {
      $states += [pscustomobject]@{
        path = $repo
        branch = (& git -C $repo branch --show-current 2>&1 | Out-String).Trim()
        status = (& git -C $repo status -sb 2>&1 | Out-String).Trim()
      }
    }
  }
  $states
}

$results | ConvertTo-Json -Depth 40
