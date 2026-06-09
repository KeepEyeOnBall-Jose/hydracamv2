#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

REMOTE_SPEC=""
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_DIR=""
PASSWORD_FILE=""
SSH_PORT="22"
VALIDATION="quick"
DELETE_REMOTE=1
SYNC_REPO=1
INSTALL_HOMEBREW=1
ENABLE_REMOTE_LOGIN=0
SETUP_ANDROID=1
SETUP_IOS=1
SETUP_MACOS=1
DRY_RUN=0
FLUTTER_DIR=""
CONNECT_TIMEOUT="10"
SSH_OPTIONS=()

usage() {
  cat <<'EOF'
Deploy the current HydraCam checkout to a reachable macOS host and prepare it
to build, run, and debug the app.

Usage:
  scripts/deploy_macos_dev_host.zsh [options] <user@host>

One-click examples:
  scripts/deploy_macos_dev_host.zsh jose@new-mac.tail6ce139.ts.net
  scripts/deploy_macos_dev_host.zsh --password-file tempass.txt jose@new-mac.tail6ce139.ts.net

Options:
  --host <host>                 SSH host or Tailscale MagicDNS name.
  --user <user>                 SSH user when <user@host> is not used.
  --remote-dir <dir>            Remote checkout path. Defaults to /Users/<user>/src/work/hydracamv2.
  --password-file <file>        Use sshpass for SSH and feed the first sudo prompt from this file.
  --port <port>                 SSH port. Defaults to 22.
  --validation <quick|full|none>
                                quick: doctor, analyze, test, macOS build, macOS debug launch.
                                full: quick plus Android APK and iOS no-codesign debug builds.
                                none: sync and bootstrap only.
  --no-delete                   Do not delete remote files that disappeared locally.
  --skip-sync                   Do not rsync the checkout before bootstrapping.
  --no-install-homebrew         Require Homebrew to already exist on the remote host.
  --enable-remote-login         Ask the remote host to enable macOS Remote Login.
  --skip-android                Skip Android SDK setup and Android validation.
  --skip-ios                    Skip Xcode/CocoaPods/iOS setup and iOS validation.
  --skip-macos                  Skip macOS desktop validation.
  --flutter-dir <dir>           Remote Flutter SDK path.
  --ssh-option <option>         Extra ssh -o option. Can be repeated.
  --dry-run                     Print the rsync and remote commands without running them.
  -h, --help                    Show this help.

Prerequisites:
  The target Mac must already be reachable by SSH, for example through Tailscale
  SSH or macOS Remote Login. Xcode.app must be installed before iOS builds can pass.
EOF
}

log() {
  print -r -- "[hydra-dev-host-deploy] $*"
}

fail() {
  print -ru2 -- "[hydra-dev-host-deploy] ERROR: $*"
  exit 1
}

shell_quote() {
  printf "%q" "$1"
}

quote_join() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(shell_quote "$arg")")
  done
  print -r -- "${(j: :)quoted}"
}

run_cmd() {
  log "Running: $(quote_join "$@")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print -r -- "[hydra-dev-host-deploy] DRY RUN: $(quote_join "$@")"
    return 0
  fi
  "$@"
}

parse_remote_spec() {
  if [[ -n "$REMOTE_SPEC" ]]; then
    if [[ "$REMOTE_SPEC" == *@* ]]; then
      REMOTE_USER="${REMOTE_SPEC%@*}"
      REMOTE_HOST="${REMOTE_SPEC#*@}"
    else
      REMOTE_HOST="$REMOTE_SPEC"
    fi
  fi

  if [[ -z "$REMOTE_HOST" ]]; then
    fail "Missing remote host. Pass <user@host> or --host <host>."
  fi

  if [[ -z "$REMOTE_USER" ]]; then
    REMOTE_USER="${USER:-jose}"
  fi

  if [[ -z "$REMOTE_DIR" ]]; then
    REMOTE_DIR="/Users/$REMOTE_USER/src/work/hydracamv2"
  fi
}

make_ssh_base() {
  local ssh_base=()
  if [[ -n "$PASSWORD_FILE" ]]; then
    if [[ "$DRY_RUN" -eq 0 ]] && ! command -v sshpass >/dev/null 2>&1; then
      fail "--password-file requires sshpass on the local machine."
    fi
    ssh_base=(sshpass -f "$PASSWORD_FILE" ssh \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o BatchMode=no)
  else
    ssh_base=(ssh)
  fi

  ssh_base+=(
    -o "ConnectTimeout=$CONNECT_TIMEOUT"
    -o StrictHostKeyChecking=accept-new
    -p "$SSH_PORT"
  )

  local option
  for option in "${SSH_OPTIONS[@]}"; do
    ssh_base+=(-o "$option")
  done

  print -r -- "$(quote_join "${ssh_base[@]}")"
}

run_remote_command() {
  local label="$1"
  local command="$2"
  local needs_sudo="${3:-0}"
  local remote_target="$REMOTE_USER@$REMOTE_HOST"
  local remote_script
  local remote_command

  if [[ "$needs_sudo" -eq 1 && -n "$PASSWORD_FILE" ]]; then
    remote_script=$'set -euo pipefail\nsudo -S -v\n(\n  while true; do\n    sudo -n -v || exit\n    sleep 60\n  done\n) &\nhydra_sudo_keepalive_pid=$!\ntrap \'kill "$hydra_sudo_keepalive_pid" 2>/dev/null || true\' EXIT\n'
    remote_script+="$command"
  else
    remote_script=$'set -euo pipefail\n'
    remote_script+="$command"
  fi

  remote_command="zsh -lc $(shell_quote "$remote_script")"
  log "Remote: $label"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print -r -- "[hydra-dev-host-deploy] DRY RUN remote command:"
    print -r -- "$remote_script"
    return 0
  fi

  if [[ "$needs_sudo" -eq 1 && -n "$PASSWORD_FILE" ]]; then
    "${SSH_BASE[@]}" "$remote_target" "$remote_command" < "$PASSWORD_FILE"
  else
    "${SSH_BASE[@]}" "$remote_target" "$remote_command"
  fi
}

macos_debug_probe_command() {
  cat <<'EOF'
print -r -- "[hydra-dev-host-deploy:remote] Running: flutter run -d macos --debug --no-pub"
python3 - <<'PY'
import subprocess
import sys
import time

command_display = "flutter run -d macos --debug --no-pub --dart-define=HYDRACAM_AUTOMATION=true --dart-define=HYDRACAM_AUTOMATION_ROLE=master"
cmd = command_display.split()
proc = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    stdin=subprocess.PIPE,
    text=True,
    bufsize=1,
)
deadline = time.time() + 240
success = False
try:
    while True:
        line = proc.stdout.readline()
        if line:
            sys.stdout.write(line)
            sys.stdout.flush()
            if "Syncing files to device macOS" in line or "An Observatory debugger" in line:
                success = True
                break
        if proc.poll() is not None:
            break
        if time.time() > deadline:
            break
    if success:
        print("FLUTTER_RUN_STATUS=debug-session-started")
        try:
            proc.stdin.write("q\n")
            proc.stdin.flush()
        except BrokenPipeError:
            pass
    else:
        print("FLUTTER_RUN_STATUS=marker-not-seen")
    stop_deadline = time.time() + 30
    while proc.poll() is None and time.time() < stop_deadline:
        line = proc.stdout.readline()
        if line:
            sys.stdout.write(line)
            sys.stdout.flush()
        else:
            time.sleep(0.2)
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=10)
    print(f"FLUTTER_RUN_EXIT={proc.returncode}")
    sys.exit(0 if success else 1)
finally:
    if proc.poll() is None:
        proc.kill()
PY
EOF
}

build_validation_command() {
  local quoted_remote_dir="$1"
  local command
  command="cd $quoted_remote_dir
source \"\$HOME/.zprofile\"
run_remote() {
  print -r -- \"[hydra-dev-host-deploy:remote] Running: \$*\"
  \"\$@\"
}
run_remote flutter doctor -v
run_remote flutter analyze
run_remote flutter test
"

  if [[ "$SETUP_MACOS" -eq 1 ]]; then
    command+="run_remote flutter build macos --debug
"
    command+="$(macos_debug_probe_command)
"
  fi

  if [[ "$VALIDATION" == "full" ]]; then
    if [[ "$SETUP_ANDROID" -eq 1 ]]; then
      command+="run_remote flutter build apk --debug
"
    fi
    if [[ "$SETUP_IOS" -eq 1 ]]; then
      command+="run_remote flutter build ios --debug --no-codesign
"
    fi
  fi

  command+="run_remote df -h /System/Volumes/Data
"
  print -r -- "$command"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="${2:?--host needs a value}"
      shift 2
      ;;
    --user)
      REMOTE_USER="${2:?--user needs a value}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:?--remote-dir needs a value}"
      shift 2
      ;;
    --password-file)
      PASSWORD_FILE="${2:?--password-file needs a path}"
      shift 2
      ;;
    --port)
      SSH_PORT="${2:?--port needs a value}"
      shift 2
      ;;
    --validation)
      VALIDATION="${2:?--validation needs quick, full, or none}"
      shift 2
      ;;
    --no-delete)
      DELETE_REMOTE=0
      shift
      ;;
    --skip-sync)
      SYNC_REPO=0
      shift
      ;;
    --no-install-homebrew)
      INSTALL_HOMEBREW=0
      shift
      ;;
    --enable-remote-login)
      ENABLE_REMOTE_LOGIN=1
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
    --ssh-option)
      SSH_OPTIONS+=("${2:?--ssh-option needs a value}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [[ -n "$REMOTE_SPEC" ]]; then
        fail "Only one remote target can be passed."
      fi
      REMOTE_SPEC="$1"
      shift
      ;;
  esac
done

case "$VALIDATION" in
  quick|full|none)
    ;;
  *)
    fail "--validation must be quick, full, or none."
    ;;
esac

parse_remote_spec

if [[ -n "$PASSWORD_FILE" ]]; then
  PASSWORD_FILE="${PASSWORD_FILE:A}"
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    fail "Password file does not exist: $PASSWORD_FILE"
  fi
fi

if [[ "$SYNC_REPO" -eq 1 ]] && ! command -v rsync >/dev/null 2>&1; then
  fail "rsync is required for deploy sync."
fi

remote_target="$REMOTE_USER@$REMOTE_HOST"
quoted_remote_dir="$(shell_quote "$REMOTE_DIR")"
SSH_BASE_STRING="$(make_ssh_base)"
SSH_BASE=(${(z)SSH_BASE_STRING})

run_cmd "${SSH_BASE[@]}" "$remote_target" "mkdir -p $quoted_remote_dir"

if [[ "$SYNC_REPO" -eq 1 ]]; then
  rsync_args=(
    -az
    --exclude=.git/
    --exclude=tempass.txt
    --exclude=.dart_tool/
    --exclude=build/
    --exclude=android/.gradle/
    --exclude=android/app/build/
    --exclude=ios/Pods/
    --exclude=macos/Pods/
    --exclude=.worktrees/
    --exclude=worktrees/
    --exclude=logs/verification-runs/
    --exclude=.DS_Store
  )

  if [[ "$DELETE_REMOTE" -eq 1 ]]; then
    rsync_args+=(--delete)
  fi

  run_cmd rsync "${rsync_args[@]}" -e "$SSH_BASE_STRING" "$REPO_ROOT/" "$remote_target:$REMOTE_DIR/"
fi

prepare_args=(
  scripts/prepare_macos_dev_host.zsh
  --repo-dir
  "$REMOTE_DIR"
  --skip-validation
)

if [[ "$INSTALL_HOMEBREW" -eq 1 ]]; then
  prepare_args+=(--install-homebrew)
fi
if [[ "$ENABLE_REMOTE_LOGIN" -eq 1 ]]; then
  prepare_args+=(--enable-remote-login)
fi
if [[ "$SETUP_ANDROID" -eq 0 ]]; then
  prepare_args+=(--skip-android)
fi
if [[ "$SETUP_IOS" -eq 0 ]]; then
  prepare_args+=(--skip-ios)
fi
if [[ "$SETUP_MACOS" -eq 0 ]]; then
  prepare_args+=(--skip-macos)
fi
if [[ -n "$FLUTTER_DIR" ]]; then
  prepare_args+=(--flutter-dir "$FLUTTER_DIR")
fi

prepare_command="cd $quoted_remote_dir
$(quote_join "${prepare_args[@]}")
"
run_remote_command "bootstrap toolchains" "$prepare_command" 1

if [[ "$VALIDATION" != "none" ]]; then
  validation_command="$(build_validation_command "$quoted_remote_dir")"
  run_remote_command "validate HydraCam checkout ($VALIDATION)" "$validation_command" 0
fi

log "Done. Remote checkout: $remote_target:$REMOTE_DIR"
