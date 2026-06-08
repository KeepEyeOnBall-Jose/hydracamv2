# Win11 Development Host Storage Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Free C: on `DESKTOP-02NDERS` enough for reliable HydraCam Windows/Android builds by moving durable development payloads to D: and archiving obvious one-off files.

**Architecture:** Keep C: for Windows, installed applications that should not be file-moved, and small launch shims only. Put repos, SDK payloads, build caches, temporary build output, WSL distros, and Docker data on D:, then update user environment variables and validate from `D:\src\work\hydracamv2`.

**Tech Stack:** Windows 11 Pro over OpenSSH/Tailscale, PowerShell 7/Windows PowerShell, Flutter `3.44.1`, Android SDK/Gradle/Pub, WSL2 Ubuntu, Docker Desktop.

---

## Current Evidence

Evidence was collected over SSH as `jose@100.110.8.112` using
`/Users/jose/Downloads/codex_ssh_key`. The run artifacts are under
`logs/verification-runs/20260607-win11-c-drive-cleanup-plan/`.

| Surface | Current value |
| --- | ---: |
| C: free | 0.14 GiB of 388.76 GiB |
| D: free | 1755.69 GiB of 9313.97 GiB |
| E: free | 26.25 GiB of 86.84 GiB |
| F: free | 1552.36 GiB of 3725.90 GiB |
| G: free | 2018.60 GiB of 3725.99 GiB |
| I: free | 3580.99 GiB of 3725.82 GiB |
| Admin token over SSH | false |

Largest relevant C: candidates:

| Candidate | Size | Disposition |
| --- | ---: | --- |
| WSL Ubuntu 22.04 `ext4.vhdx` | 22.18 GiB | Move with WSL commands only; do not move the VHD file by hand. |
| Android SDK `system-images` | 13.81 GiB | Move whole SDK to D: and update `ANDROID_HOME` / `ANDROID_SDK_ROOT`. |
| Visual Studio Community 2022 | 11.63 GiB | Keep installed; only modify workloads from installer if needed. |
| Docker local WSL data | 7.82 GiB | Move via Docker Desktop settings or documented Docker migration, not by raw file move. |
| `C:\src` | 6.93 GiB | Move/repoint toolchains and repos to D:. |
| `C:\Program Files\Android` | 6.85 GiB | Treat as installed app payload; do not file-move. |
| `C:\Users\jose\AppData\Local\Programs` | 6.03 GiB | Keep installed apps unless explicitly uninstalling duplicates. |
| `C:\Users\jose\Downloads` | 3.98 GiB | Archive old installers/temp files to D:. |
| `C:\src\repos` | 3.53 GiB | Move to D: or archive. |
| `C:\Users\jose\java_error_in_pycharm.hprof` | 3.21 GiB | Archive or delete after approval. |
| `C:\src\flutter` | 2.93 GiB | Move to D: and update PATH. |
| Android SDK `ndk` | 2.12 GiB | Included in SDK move. |
| Gradle wrapper cache | 1.71 GiB | Move Gradle home to D:. |
| Pub cache | 1.30 GiB | Move `PUB_CACHE` to D:. |
| C: HydraCam checkout | 1.05 GiB | Remove after D: checkout/build validation. |
| User temp | 0.57 GiB | Move `TEMP` / `TMP` to D: and clean old C: temp. |

Timed-out but relevant paths: `C:\Users\jose\.gradle\caches`,
`C:\Users\jose\AppData\Local\Android\Sdk\platforms`, and the whole Android SDK
tree. Treat the sizes above as conservative minimums.

## File Structure

- Create on Win11: `D:\_archive\win11-c-drive-cleanup\20260607\` for archived
  one-off files, before deletion.
- Create on Win11: `D:\dev\toolchains\flutter`, `D:\dev\toolchains\jdk-17`,
  `D:\dev\android-sdk`, `D:\dev\gradle-cache`, `D:\dev\pub-cache`,
  `D:\dev\tmp`, `D:\wsl`, and `D:\docker`.
- Keep primary HydraCam checkout on Win11: `D:\src\work\hydracamv2`.
- Keep local evidence in this repo:
  `logs/verification-runs/20260607-win11-c-drive-cleanup-plan/`.

## Non-Negotiable Safety Rules

- Do not manually move or edit WSL `ext4.vhdx` files under AppData. Microsoft
  documents WSL distro VHDs as WSL-managed files and warns against modifying
  them with Windows tools.
- Do not delete personal documents, certificates, keys, or identity files from
  Desktop/Downloads. Only archive obvious installers, temp files, crash dumps,
  and dev cache payloads named in this plan.
- Do not manually file-move `C:\Program Files`, Visual Studio, Android Studio,
  Docker Desktop, or system folders. Use uninstallers/settings only.
- Do not treat C: cleanup as solving Windows symlink privilege. Native Windows
  Flutter builds still need Developer Mode or an elevated session.

WSL references used for this plan:
[Microsoft WSL basic commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
and
[Microsoft WSL disk-space guidance](https://learn.microsoft.com/en-us/windows/wsl/disk-space).

### Task 1: Preflight Snapshot

**Files:**
- Create on Win11: `D:\_archive\win11-c-drive-cleanup\20260607\preflight\`
- Read locally: `logs/verification-runs/20260607-win11-c-drive-cleanup-plan/storage-fast-inventory.json`
- Read locally: `logs/verification-runs/20260607-win11-c-drive-cleanup-plan/dev-cache-breakdown.json`

- [ ] **Step 1: Create the cleanup run folder**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path D:\_archive\win11-c-drive-cleanup\20260607\preflight | Out-Null"'
```

Expected: exit code `0`.

- [ ] **Step 2: Capture drive and environment state**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$out=\"D:\_archive\win11-c-drive-cleanup\20260607\preflight\"; Get-CimInstance Win32_LogicalDisk -Filter \"DriveType = 3\" | Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 (Join-Path $out \"drives-before.csv\"); @(\"ANDROID_HOME\",\"ANDROID_SDK_ROOT\",\"JAVA_HOME\",\"JAVA17_HOME\",\"GRADLE_USER_HOME\",\"PUB_CACHE\",\"TEMP\",\"TMP\",\"Path\") | ForEach-Object { [PSCustomObject]@{ Name=$_; User=[Environment]::GetEnvironmentVariable($_,\"User\"); Machine=[Environment]::GetEnvironmentVariable($_,\"Machine\") } } | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $out \"env-before.json\")"'
```

Expected: `drives-before.csv` shows C: near `0.14 GiB` free; D: has more than
`1700 GiB` free.

- [ ] **Step 3: Confirm checkout state before deleting any checkout**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "git -C C:\Users\jose\src\work\hydracamv2 status -sb; git -C D:\src\work\hydracamv2 status -sb; git -C D:\src\work\hydracamv2 rev-parse HEAD"'
```

Expected: both commands return a status or a clear path error. Do not remove
the C: checkout until the D: checkout has a valid `pubspec.yaml`, `lib\main.dart`,
and a known commit.

### Task 2: Immediate Low-Risk Archive

**Files:**
- Move on Win11: selected one-off files from C: to
  `D:\_archive\win11-c-drive-cleanup\20260607\`
- Validate on Win11: `D:\_archive\win11-c-drive-cleanup\20260607\low-risk-after.csv`

- [ ] **Step 1: Archive the large PyCharm heap dump**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$dest=\"D:\_archive\win11-c-drive-cleanup\20260607\crash-dumps\"; New-Item -ItemType Directory -Force -Path $dest | Out-Null; Move-Item -LiteralPath C:\Users\jose\java_error_in_pycharm.hprof -Destination $dest -ErrorAction Stop"'
```

Expected C: relief: about `3.21 GiB`.

- [ ] **Step 2: Archive obvious installer/temp payloads from Downloads**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$dest=\"D:\_archive\win11-c-drive-cleanup\20260607\downloads\"; New-Item -ItemType Directory -Force -Path $dest | Out-Null; $files=@(\"C:\Users\jose\Downloads\android-studio-2025.3.1.8-windows.exe\",\"C:\Users\jose\Downloads\BITE311.tmp\",\"C:\Users\jose\Downloads\Antigravity.exe\",\"C:\Users\jose\Downloads\ntws-latest-standalone-windows-x64.exe\",\"C:\Users\jose\Downloads\VisualStudioSetup.exe\"); foreach ($file in $files) { if (Test-Path -LiteralPath $file) { Move-Item -LiteralPath $file -Destination $dest -ErrorAction Stop } }"'
```

Expected C: relief: about `2.9 GiB`. This intentionally leaves personal PDFs,
certificates, and business documents untouched.

- [ ] **Step 3: Archive the downloaded Temurin JDK zip**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$dest=\"D:\_archive\win11-c-drive-cleanup\20260607\installers\"; New-Item -ItemType Directory -Force -Path $dest | Out-Null; if (Test-Path C:\src\temurin-jdk17.zip) { Move-Item -LiteralPath C:\src\temurin-jdk17.zip -Destination $dest -ErrorAction Stop }"'
```

Expected C: relief: about `0.18 GiB`.

- [ ] **Step 4: Recheck drive space**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter \"DriveType = 3\" | Select-Object DeviceID,VolumeName,Size,FreeSpace | ConvertTo-Csv -NoTypeInformation"'
```

Expected: C: free should rise from `0.14 GiB` to roughly `6 GiB` or more.

### Task 3: Establish D: Development Roots

**Files:**
- Create on Win11: `D:\dev\toolchains\flutter`
- Create on Win11: `D:\dev\toolchains\jdk-17`
- Create on Win11: `D:\dev\android-sdk`
- Create on Win11: `D:\dev\gradle-cache`
- Create on Win11: `D:\dev\pub-cache`
- Create on Win11: `D:\dev\tmp`

- [ ] **Step 1: Create D: root directories**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path D:\dev\toolchains\flutter,D:\dev\toolchains\jdk-17,D:\dev\android-sdk,D:\dev\gradle-cache,D:\dev\pub-cache,D:\dev\tmp,D:\wsl,D:\docker | Out-Null"'
```

Expected: exit code `0`.

- [ ] **Step 2: Set user-level build cache and temp variables to D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable(\"GRADLE_USER_HOME\",\"D:\dev\gradle-cache\",\"User\"); [Environment]::SetEnvironmentVariable(\"PUB_CACHE\",\"D:\dev\pub-cache\",\"User\"); [Environment]::SetEnvironmentVariable(\"TEMP\",\"D:\dev\tmp\",\"User\"); [Environment]::SetEnvironmentVariable(\"TMP\",\"D:\dev\tmp\",\"User\")"'
```

Expected: new SSH sessions inherit `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`, and
`TMP` on D:.

### Task 4: Move Flutter, JDK 17, and C:\src Repos

**Files:**
- Move on Win11: `C:\src\flutter` to `D:\dev\toolchains\flutter`
- Move on Win11: `C:\src\jdk-17` to `D:\dev\toolchains\jdk-17`
- Move on Win11: `C:\src\repos` to `D:\src\repos`

- [ ] **Step 1: Mirror Flutter and JDK payloads to D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "robocopy C:\src\flutter D:\dev\toolchains\flutter /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; if ($LASTEXITCODE -le 7) { robocopy C:\src\jdk-17 D:\dev\toolchains\jdk-17 /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; if ($LASTEXITCODE -le 7) { exit 0 } }; exit $LASTEXITCODE"'
```

Expected: `robocopy` exit code `0` through `7`, which means copy success.

- [ ] **Step 2: Point user environment to D: toolchains**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable(\"JAVA17_HOME\",\"D:\dev\toolchains\jdk-17\",\"User\"); $old=[Environment]::GetEnvironmentVariable(\"Path\",\"User\") -split \";\"; $kept=$old | Where-Object { $_ -and $_ -ne \"C:\src\flutter\bin\" -and $_ -ne \"C:\src\jdk-17\bin\" }; $new=@(\"D:\dev\toolchains\flutter\bin\",\"D:\dev\toolchains\jdk-17\bin\") + $kept; [Environment]::SetEnvironmentVariable(\"Path\",(($new | Select-Object -Unique) -join \";\"),\"User\")"'
```

Expected: a new SSH session resolves Flutter from `D:\dev\toolchains\flutter`.

- [ ] **Step 3: Validate D: Flutter before deleting C: copies**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "& D:\dev\toolchains\flutter\bin\flutter.bat --version; & D:\dev\toolchains\jdk-17\bin\java.exe -version"'
```

Expected: Flutter reports `3.44.1`; Java reports `17.0.19`.

- [ ] **Step 4: Rename old C: payloads, then delete after one successful build**

Run from macOS after Step 3 passes:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "Rename-Item C:\src\flutter flutter.c-moved-20260607 -ErrorAction Stop; Rename-Item C:\src\jdk-17 jdk-17.c-moved-20260607 -ErrorAction Stop"'
```

Expected: C: gains no space yet. Delete these renamed directories only after
Task 7 passes:

```powershell
Remove-Item -Recurse -Force C:\src\flutter.c-moved-20260607,C:\src\jdk-17.c-moved-20260607
```

- [ ] **Step 5: Move C:\src\repos to D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path D:\src | Out-Null; if (Test-Path C:\src\repos) { robocopy C:\src\repos D:\src\repos /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; if ($LASTEXITCODE -le 7) { Rename-Item C:\src\repos repos.c-moved-20260607; exit 0 }; exit $LASTEXITCODE }"'
```

Expected C: relief after final deletion: about `3.53 GiB`.

### Task 5: Move Android SDK to D:

**Files:**
- Move on Win11: `C:\Users\jose\AppData\Local\Android\Sdk` to
  `D:\dev\android-sdk`
- Modify user environment: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and PATH

- [ ] **Step 1: Mirror the Android SDK**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$src=Join-Path $env:LOCALAPPDATA \"Android\Sdk\"; robocopy $src D:\dev\android-sdk /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; if ($LASTEXITCODE -le 7) { exit 0 }; exit $LASTEXITCODE"'
```

Expected: `robocopy` exit code `0` through `7`.

- [ ] **Step 2: Update Android SDK environment**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable(\"ANDROID_HOME\",\"D:\dev\android-sdk\",\"User\"); [Environment]::SetEnvironmentVariable(\"ANDROID_SDK_ROOT\",\"D:\dev\android-sdk\",\"User\"); $old=[Environment]::GetEnvironmentVariable(\"Path\",\"User\") -split \";\"; $kept=$old | Where-Object { $_ -and $_ -notlike \"C:\Users\jose\AppData\Local\Android\Sdk*\" }; $new=@(\"D:\dev\android-sdk\platform-tools\",\"D:\dev\android-sdk\cmdline-tools\latest\bin\",\"D:\dev\android-sdk\emulator\") + $kept; [Environment]::SetEnvironmentVariable(\"Path\",(($new | Select-Object -Unique) -join \";\"),\"User\")"'
```

Expected: new SSH sessions resolve `adb` and `sdkmanager` from D:.

- [ ] **Step 3: Validate Android SDK from D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$env:ANDROID_HOME=\"D:\dev\android-sdk\"; $env:ANDROID_SDK_ROOT=\"D:\dev\android-sdk\"; $env:PATH=\"D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\cmdline-tools\latest\bin;D:\dev\toolchains\flutter\bin;\" + $env:PATH; adb version; sdkmanager --list_installed; flutter doctor -v"'
```

Expected: `adb version` passes; `sdkmanager --list_installed` lists Android
platforms/build tools; `flutter doctor -v` still has only previously known
non-storage issues.

- [ ] **Step 4: Rename old C: SDK and delete after Task 7 passes**

Run from macOS after Step 3 passes:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$src=Join-Path $env:LOCALAPPDATA \"Android\Sdk\"; Rename-Item $src Sdk.c-moved-20260607 -ErrorAction Stop"'
```

Expected C: relief after final deletion: at least `17 GiB`, probably more
because SDK `platforms` timed out during sizing.

### Task 6: Move Gradle, Pub, and Temp Workloads to D:

**Files:**
- Move on Win11: `C:\Users\jose\.gradle` to `D:\dev\gradle-cache`
- Move on Win11: `C:\Users\jose\AppData\Local\Pub\Cache` to
  `D:\dev\pub-cache`
- Modify user environment: `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`, `TMP`

- [ ] **Step 1: Seed D: Gradle and Pub caches**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "robocopy C:\Users\jose\.gradle D:\dev\gradle-cache /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; $gradleExit=$LASTEXITCODE; robocopy C:\Users\jose\AppData\Local\Pub\Cache D:\dev\pub-cache /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2; $pubExit=$LASTEXITCODE; if ($gradleExit -le 7 -and $pubExit -le 7) { exit 0 }; exit 1"'
```

Expected: exit code `0`.

- [ ] **Step 2: Validate the env values in a new SSH session**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "Write-Output \"GRADLE_USER_HOME=$env:GRADLE_USER_HOME\"; Write-Output \"PUB_CACHE=$env:PUB_CACHE\"; Write-Output \"TEMP=$env:TEMP\"; Write-Output \"TMP=$env:TMP\""'
```

Expected: all four values point to `D:\dev\...`.

- [ ] **Step 3: Rename old C: Gradle and Pub caches**

Run from macOS after Step 2 passes:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "Rename-Item C:\Users\jose\.gradle .gradle.c-moved-20260607 -ErrorAction Stop; Rename-Item C:\Users\jose\AppData\Local\Pub\Cache Cache.c-moved-20260607 -ErrorAction Stop"'
```

Expected C: relief after final deletion: at least `3 GiB`, plus unknown
additional relief from timed-out `C:\Users\jose\.gradle\caches`.

- [ ] **Step 4: Clean old user temp files after TEMP/TMP point to D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$old=\"C:\Users\jose\AppData\Local\Temp\"; Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"'
```

Expected C: relief: up to `0.57 GiB`. Active temp files may remain, and that is
acceptable.

### Task 7: Promote the D: HydraCam Checkout

**Files:**
- Use on Win11: `D:\src\work\hydracamv2`
- Remove after validation: `C:\Users\jose\src\work\hydracamv2`

- [ ] **Step 1: Run pub get and analyze from D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$env:ANDROID_HOME=\"D:\dev\android-sdk\"; $env:ANDROID_SDK_ROOT=\"D:\dev\android-sdk\"; $env:GRADLE_USER_HOME=\"D:\dev\gradle-cache\"; $env:PUB_CACHE=\"D:\dev\pub-cache\"; $env:TEMP=\"D:\dev\tmp\"; $env:TMP=\"D:\dev\tmp\"; $env:PATH=\"D:\dev\toolchains\flutter\bin;D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\cmdline-tools\latest\bin;\" + $env:PATH; Set-Location D:\src\work\hydracamv2; flutter pub get; flutter analyze"'
```

Expected: `flutter pub get` passes; `flutter analyze` reports no issues, matching
the prior C: checkout result.

- [ ] **Step 2: Run the Android debug APK build from D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$env:ANDROID_HOME=\"D:\dev\android-sdk\"; $env:ANDROID_SDK_ROOT=\"D:\dev\android-sdk\"; $env:GRADLE_USER_HOME=\"D:\dev\gradle-cache\"; $env:PUB_CACHE=\"D:\dev\pub-cache\"; $env:TEMP=\"D:\dev\tmp\"; $env:TMP=\"D:\dev\tmp\"; $env:PATH=\"D:\dev\toolchains\flutter\bin;D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\cmdline-tools\latest\bin;\" + $env:PATH; Set-Location D:\src\work\hydracamv2; flutter build apk --debug"'
```

Expected: the previous `Espacio en disco insuficiente` error is gone. If the
build fails for a non-storage reason, record that error separately.

- [ ] **Step 3: Remove the C: checkout after D: validation passes**

Run from macOS only after Steps 1 and 2 pass:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "Remove-Item -Recurse -Force C:\Users\jose\src\work\hydracamv2"'
```

Expected C: relief: about `1.05 GiB`.

### Task 8: Move WSL Ubuntu 22.04 to D:

**Files:**
- Move with WSL: Ubuntu 22.04 distro currently backed by
  `C:\Users\jose\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\LocalState\ext4.vhdx`
- Create on Win11: `D:\wsl\Ubuntu-22.04`
- Create on Win11: `D:\wsl\exports\Ubuntu-22.04-20260607.tar`

- [ ] **Step 1: Verify WSL distro list and Linux default user**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "wsl -l -v; wsl -d Ubuntu-22.04 -e bash -lc \"whoami; df -h /\""'
```

Expected: `Ubuntu-22.04` is listed as WSL2 and `whoami` prints `jose`.

- [ ] **Step 2: Shut down WSL and export Ubuntu 22.04**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path D:\wsl\exports,D:\wsl\Ubuntu-22.04 | Out-Null; wsl --shutdown; wsl --export Ubuntu-22.04 D:\wsl\exports\Ubuntu-22.04-20260607.tar"'
```

Expected: export completes and `D:\wsl\exports\Ubuntu-22.04-20260607.tar`
exists. Stop here if export fails.

- [ ] **Step 3: Import the distro on D: only after export succeeds**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "wsl --unregister Ubuntu-22.04; wsl --import Ubuntu-22.04 D:\wsl\Ubuntu-22.04 D:\wsl\exports\Ubuntu-22.04-20260607.tar --version 2; wsl --set-default Ubuntu-22.04"'
```

Expected: `wsl -l -v` lists `Ubuntu-22.04` as WSL2.

- [ ] **Step 4: Restore default Linux user and validate Flutter**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "wsl -d Ubuntu-22.04 -u root -- bash -lc \"id -u jose >/dev/null 2>&1 && printf ''[user]\ndefault=jose\n'' > /etc/wsl.conf\"; wsl --terminate Ubuntu-22.04; wsl -d Ubuntu-22.04 -e bash -lc \"whoami; /home/jose/development/flutter/bin/flutter --version; df -h /\""'
```

Expected: `whoami` prints `jose`; Flutter reports `3.44.1`; Linux build lane is
still available.

Expected C: relief after successful import: about `22.18 GiB`.

### Task 9: Move Docker Data with Docker-Supported Controls

**Files:**
- Current evidence: `C:\Users\jose\AppData\Local\Docker\wsl` is about `7.82 GiB`
- Target: `D:\docker`

- [ ] **Step 1: Decide whether Docker is needed on this Win11 host**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "docker --version; docker ps -a; docker images"'
```

Expected: if Docker is unused, plan an uninstall instead of a move. If Docker
has active HydraCam/backend dependencies, keep it and move through Docker
Desktop UI/settings in an interactive admin session.

- [ ] **Step 2: Do not raw-move Docker VHD files**

Operator action in the Windows UI:

```text
Docker Desktop -> Settings -> Resources -> Advanced -> Disk image location -> D:\docker
Apply & Restart
```

Expected: Docker Desktop restarts and stores its WSL data on D:. If this setting
is unavailable, export needed images/volumes, uninstall Docker Desktop, reinstall
with D: data location, then import only required images.

Expected C: relief: about `7.82 GiB`.

### Task 10: Final Cleanup and Validation

**Files:**
- Delete after validation: `C:\src\flutter.c-moved-20260607`
- Delete after validation: `C:\src\jdk-17.c-moved-20260607`
- Delete after validation: `C:\src\repos.c-moved-20260607`
- Delete after validation: `C:\Users\jose\.gradle.c-moved-20260607`
- Delete after validation: `C:\Users\jose\AppData\Local\Pub\Cache.c-moved-20260607`
- Delete after validation: `C:\Users\jose\AppData\Local\Android\Sdk.c-moved-20260607`

- [ ] **Step 1: Validate current toolchain and builds from D:**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$env:PATH=\"D:\dev\toolchains\flutter\bin;D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\cmdline-tools\latest\bin;\" + $env:PATH; flutter doctor -v; Set-Location D:\src\work\hydracamv2; flutter pub get; flutter analyze; flutter build apk --debug"'
```

Expected: `flutter build apk --debug` no longer fails from C: exhaustion.
Windows desktop build may still fail until symlink privilege is fixed.

- [ ] **Step 2: Delete renamed C: payloads**

Run from macOS only after Step 1 passes:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$paths=@(\"C:\src\flutter.c-moved-20260607\",\"C:\src\jdk-17.c-moved-20260607\",\"C:\src\repos.c-moved-20260607\",\"C:\Users\jose\.gradle.c-moved-20260607\",\"C:\Users\jose\AppData\Local\Pub\Cache.c-moved-20260607\",\"C:\Users\jose\AppData\Local\Android\Sdk.c-moved-20260607\"); foreach ($path in $paths) { if (Test-Path -LiteralPath $path) { Remove-Item -Recurse -Force -LiteralPath $path } }"'
```

Expected C: relief: at least `35 GiB` without WSL/Docker, and at least `60 GiB`
if WSL and Docker are also moved.

- [ ] **Step 3: Capture final disk snapshot**

Run from macOS:

```bash
ssh -i /Users/jose/Downloads/codex_ssh_key -o IdentitiesOnly=yes -o BatchMode=yes jose@100.110.8.112 'powershell -NoProfile -Command "$out=\"D:\_archive\win11-c-drive-cleanup\20260607\"; Get-CimInstance Win32_LogicalDisk -Filter \"DriveType = 3\" | Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace | ConvertTo-Csv -NoTypeInformation | Set-Content -Encoding UTF8 (Join-Path $out \"drives-after.csv\"); Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID = ''C:''\" | Select-Object DeviceID,Size,FreeSpace | ConvertTo-Json"'
```

Expected: C: has at least `50 GiB` free. If it is still below `30 GiB`, inspect
Visual Studio workloads, Android Studio duplication, old Python/Anaconda
installations, and Windows component cleanup in an elevated session.

## Expected Outcome

- Low-risk archive only: about `6 GiB` C: relief.
- Dev toolchain/cache move without WSL/Docker: at least `35 GiB` C: relief.
- Full move including WSL and Docker: at least `60 GiB` C: relief.
- HydraCam Android builds should run from `D:\src\work\hydracamv2` with
  Gradle/Pub/temp output on D:.
- Known separate blocker remains: Windows native Flutter build symlink privilege
  still needs Developer Mode or an elevated/admin session.
