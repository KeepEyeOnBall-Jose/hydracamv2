# macOS Development Host Deploy

Last refreshed: 2026-06-07.

Use this when a new Mac on the tailnet needs to become a HydraCam build, run,
and debug host. The wrapper deploys the current checkout, runs the macOS
toolchain bootstrap on the remote host, and then performs a validation pass.

## One Command

```bash
scripts/deploy_macos_dev_host.zsh --password-file tempass.txt jose@new-mac.tail6ce139.ts.net
```

For SSH-key or Tailscale-SSH hosts that do not need a password file:

```bash
scripts/deploy_macos_dev_host.zsh jose@new-mac.tail6ce139.ts.net
```

## What It Does

1. Creates `/Users/<user>/src/work/hydracamv2` on the remote Mac.
2. Syncs the current checkout with `rsync`, excluding secrets, `.git/`,
   generated Flutter/Gradle/CocoaPods build outputs, local worktrees, and
   verification-run artifacts.
3. Runs `scripts/prepare_macos_dev_host.zsh --skip-validation` remotely to
   install or configure Homebrew, Flutter, Android SDK pieces, Xcode first
   launch/iOS platform, CocoaPods, JDK 17, Gradle heap/IPv4 settings, and
   `flutter pub get`. Android SDK setup includes platform `android-36`,
   build-tools `28.0.3` and `35.0.0`, NDK `28.2.13676358`, and CMake `3.22.1`.
4. Runs validation from the wrapper.

Default validation is `--validation quick`:

- `flutter doctor -v`
- `flutter analyze`
- `flutter test`
- `flutter build macos --debug`
- `flutter run -d macos --debug --no-pub` until the VM service/debug session is
  visible, then the harness exits.

Use `--validation full` only when the host has enough disk and mobile builds are
needed immediately. It adds:

- `flutter build apk --debug`
- `flutter build ios --debug --no-codesign`

Use `--validation none` to sync and install toolchains only.

## Prerequisites

- The Mac must already be reachable by SSH, either through Tailscale SSH or
  macOS Remote Login.
- The SSH user must be an administrator/sudoer for first-launch, Remote Login,
  and Xcode platform setup.
- `Xcode.app` must already be installed before iOS builds can pass. The script
  can run first launch and download the iOS platform, but it does not install
  Xcode from the App Store.
- If using `--password-file`, keep the file local and ignored. `tempass.txt` is
  ignored by `.gitignore` and is excluded from deploy syncs.
- Keep at least 10 GB free for a comfortable full validation pass. The MBA M1
  run finished with 3.5 GiB free only after cache cleanup and without Android
  emulator images.

## Dry Run

```bash
scripts/deploy_macos_dev_host.zsh --dry-run --password-file tempass.txt jose@new-mac.tail6ce139.ts.net
```

The dry run prints the `ssh`, `rsync`, bootstrap, and validation commands
without opening a network connection or printing the password contents.
