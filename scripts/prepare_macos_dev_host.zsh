#!/usr/bin/env zsh

set -euo pipefail

REPO_URL="https://github.com/KeepEyeOnBall-Jose/hydracamv2.git"
REPO_DIR=""
CLONE_IF_MISSING=0
INSTALL_HOMEBREW=0
ENABLE_REMOTE_LOGIN=0
RUN_VALIDATION=1
SETUP_ANDROID=1
SETUP_IOS=1
SETUP_MACOS=1
FLUTTER_DIR="$HOME/development/flutter"
EXPECTED_FLUTTER_VERSION="3.44.1"

usage() {
  cat <<'EOF'
Prepare an Apple Silicon macOS host to build, run, and debug HydraCam.

Usage:
  scripts/prepare_macos_dev_host.zsh [options]

Options:
  --repo-dir <dir>          Existing or target HydraCam checkout.
  --repo-url <url>          Git URL to clone when --clone-if-missing is used.
  --clone-if-missing        Clone the repo if --repo-dir does not exist.
  --install-homebrew        Install Homebrew if it is missing.
  --enable-remote-login     Enable macOS Remote Login for future Tailscale SSH.
  --skip-validation         Install/check tooling only; do not run Flutter gates.
  --skip-android            Skip Android SDK setup and Android build validation.
  --skip-ios                Skip Xcode/CocoaPods setup and iOS build validation.
  --skip-macos              Skip macOS desktop enablement/build validation.
  --flutter-dir <dir>       Flutter SDK path to use or create.
  -h, --help                Show this help.

Examples:
  scripts/prepare_macos_dev_host.zsh --install-homebrew --enable-remote-login
  scripts/prepare_macos_dev_host.zsh --repo-dir ~/src/work/hydracamv2 --clone-if-missing
EOF
}

log() {
  print -r -- "[hydra-dev-host] $*"
}

warn() {
  print -ru2 -- "[hydra-dev-host] WARN: $*"
}

fail() {
  print -ru2 -- "[hydra-dev-host] ERROR: $*"
  exit 1
}

run() {
  log "Running: $*"
  "$@"
}

append_line_once() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    print -r -- "$line" >> "$file"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="${2:?--repo-dir needs a directory}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:?--repo-url needs a URL}"
      shift 2
      ;;
    --clone-if-missing)
      CLONE_IF_MISSING=1
      shift
      ;;
    --install-homebrew)
      INSTALL_HOMEBREW=1
      shift
      ;;
    --enable-remote-login)
      ENABLE_REMOTE_LOGIN=1
      shift
      ;;
    --skip-validation)
      RUN_VALIDATION=0
      shift
      ;;
    --skip-android)
      SETUP_ANDROID=0
      shift
      ;;
    --skip-ios)
      SETUP_IOS=0
      shift
      ;;
    --skip-macos)
      SETUP_MACOS=0
      shift
      ;;
    --flutter-dir)
      FLUTTER_DIR="${2:?--flutter-dir needs a directory}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This script is for macOS hosts."
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  warn "This host is not reporting Apple Silicon arm64; continuing anyway."
fi

if [[ -z "$REPO_DIR" ]]; then
  if git -C . rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_DIR="$(git -C . rev-parse --show-toplevel)"
  else
    REPO_DIR="$HOME/src/work/hydracamv2"
  fi
fi

REPO_DIR="${REPO_DIR:A}"
FLUTTER_DIR="${FLUTTER_DIR:A}"

if [[ "$ENABLE_REMOTE_LOGIN" -eq 1 ]]; then
  run sudo systemsetup -setremotelogin on
fi

if ! command -v brew >/dev/null 2>&1; then
  if [[ "$INSTALL_HOMEBREW" -ne 1 ]]; then
    fail "Homebrew is missing. Re-run with --install-homebrew to install it."
  fi

  tmp_brew_install="$(mktemp)"
  run curl --fail --location --show-error --connect-timeout 20 --max-time 300 \
    -o "$tmp_brew_install" \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  run env NONINTERACTIVE=1 /bin/bash "$tmp_brew_install"
  rm -f "$tmp_brew_install"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew still is not available after setup."
fi

append_line_once "$HOME/.zprofile" 'eval "$(/opt/homebrew/bin/brew shellenv)"'

run brew update

run brew install git ruby openjdk@17 cocoapods
if [[ "$SETUP_ANDROID" -eq 1 ]]; then
  run brew install --cask android-commandlinetools
fi

export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/opt/openjdk@17/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export GRADLE_OPTS="-Djava.net.preferIPv4Stack=true"
append_line_once "$HOME/.zprofile" 'export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/opt/openjdk@17/bin:$PATH"'
append_line_once "$HOME/.zprofile" 'export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"'
append_line_once "$HOME/.zprofile" 'export GRADLE_OPTS="-Djava.net.preferIPv4Stack=true"'

if [[ "$SETUP_ANDROID" -eq 1 ]]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  append_line_once "$HOME/.zprofile" 'export ANDROID_HOME="$HOME/Library/Android/sdk"'
  append_line_once "$HOME/.zprofile" 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
  append_line_once "$HOME/.zprofile" 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"'
  mkdir -p "$HOME/.gradle"
  touch "$HOME/.gradle/gradle.properties"
  tmp_gradle_properties="$(mktemp)"
  grep -v "^org\\.gradle\\.jvmargs=" "$HOME/.gradle/gradle.properties" > "$tmp_gradle_properties"
  print -r -- "org.gradle.jvmargs=-Xmx4096m -Djava.net.preferIPv4Stack=true" >> "$tmp_gradle_properties"
  mv "$tmp_gradle_properties" "$HOME/.gradle/gradle.properties"

  mkdir -p "$ANDROID_HOME"
  sdkmanager_path=""
  for candidate in \
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager" \
    "/opt/homebrew/share/android-commandlinetools/cmdline-tools/bin/sdkmanager"; do
    if [[ -x "$candidate" ]]; then
      sdkmanager_path="$candidate"
      break
    fi
  done

  if [[ -z "$sdkmanager_path" ]]; then
    fail "sdkmanager not found after installing android-commandlinetools."
  fi

  run "$sdkmanager_path" --sdk_root="$ANDROID_HOME" \
    "cmdline-tools;latest" \
    "platform-tools" \
    "platforms;android-36" \
    "build-tools;28.0.3" \
    "build-tools;35.0.0" \
    "ndk;28.2.13676358"
  set +o pipefail
  yes | "$sdkmanager_path" --sdk_root="$ANDROID_HOME" --licenses
  license_status=$?
  set -o pipefail
  if [[ "$license_status" -ne 0 ]]; then
    fail "Android SDK license acceptance failed."
  fi
fi

if [[ "$SETUP_IOS" -eq 1 ]]; then
  if [[ -d /Applications/Xcode.app ]]; then
    current_xcode_path="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$current_xcode_path" != "/Applications/Xcode.app/Contents/Developer" ]]; then
      run sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
    fi
  else
    warn "Xcode.app is missing. Install Xcode from the App Store before iOS builds."
  fi

  if command -v xcodebuild >/dev/null 2>&1; then
    if ! xcodebuild -license check >/dev/null 2>&1; then
      warn "Xcode license is not accepted. Run: sudo xcodebuild -license"
    fi
    run sudo xcodebuild -runFirstLaunch
  fi

  if ! command -v pod >/dev/null 2>&1; then
    fail "CocoaPods is missing after brew install."
  fi
fi

if [[ ! -d "$FLUTTER_DIR/.git" ]]; then
  run mkdir -p "$(dirname "$FLUTTER_DIR")"
  run git clone --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
append_line_once "$HOME/.zprofile" "export PATH=\"$FLUTTER_DIR/bin:\$PATH\""

if ! command -v flutter >/dev/null 2>&1; then
  fail "Flutter is not available after adding $FLUTTER_DIR/bin to PATH."
fi

actual_flutter_version="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([^ ]*\).*/\1/p' | head -n 1)"
if [[ -n "$actual_flutter_version" && "$actual_flutter_version" != "$EXPECTED_FLUTTER_VERSION" ]]; then
  warn "Expected Flutter $EXPECTED_FLUTTER_VERSION from current HydraCam validation; found $actual_flutter_version."
fi

run flutter config --enable-macos-desktop
run flutter precache --ios --android --macos

if [[ ! -d "$REPO_DIR/.git" ]]; then
  if [[ "$CLONE_IF_MISSING" -ne 1 ]]; then
    fail "$REPO_DIR is not a Git checkout. Re-run with --clone-if-missing or pass --repo-dir."
  fi
  run mkdir -p "$(dirname "$REPO_DIR")"
  run git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

run flutter pub get

if [[ "$RUN_VALIDATION" -eq 1 ]]; then
  run flutter doctor -v
  run flutter analyze
  run flutter test

  if [[ "$SETUP_MACOS" -eq 1 ]]; then
    run flutter build macos --debug
  fi

  if [[ "$SETUP_ANDROID" -eq 1 ]]; then
    run flutter build apk --debug
  fi

  if [[ "$SETUP_IOS" -eq 1 ]]; then
    run flutter build ios --debug --simulator
  fi
fi

if command -v tailscale >/dev/null 2>&1; then
  log "Tailscale status:"
  tailscale status
elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
  log "Tailscale status:"
  /Applications/Tailscale.app/Contents/MacOS/Tailscale status
else
  warn "Tailscale CLI was not found; install or open Tailscale before remote debugging over the tailnet."
fi

log "Done. Open a new shell or run: source ~/.zprofile"
