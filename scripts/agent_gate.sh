#!/usr/bin/env bash
# Change-scoped validation gate for agent sessions.
#
# Computes the set of changed files (staged + unstaged + untracked, relative
# to HEAD) unless explicit file paths are passed as arguments, then runs the
# mechanical checks that apply to the files that actually changed:
#   - Always: `git diff --check` (trailing whitespace / conflict markers).
#   - Always: large-file guard — any changed file over 1 MB fails the gate
#     (evidence artifacts must stay out of git).
#   - Any changed `.dart` file: `dart format --set-exit-if-changed` on those
#     files, then `flutter analyze --no-pub`.
#   - Any changed `.md` file outside `docs/control/history/` and `logs/`:
#     `npx --yes markdownlint-cli2` on those files.
#   - Any changed `.sh` file: `shellcheck --severity=error` on those files
#     (skipped with a note if shellcheck is not installed; `.zsh` files are
#     never treated as shellcheck targets).
#   - Any changed `scripts/*.py` file: run its matching unittest file
#     (`scripts/test_foo.py` for a changed `scripts/foo.py`; run directly if
#     the changed file already is a `scripts/test_*.py`). More than 5 matched
#     test files still all run, with a note.
# On a clean tree with no arguments, prints "clean" and exits 0 immediately.
#
# Usage:
#   bash scripts/agent_gate.sh                # auto-detect changed files
#   bash scripts/agent_gate.sh path/one.dart path/two.md   # explicit paths

set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root" || exit 1

changed_files=()

if [ "$#" -gt 0 ]; then
  changed_files=("$@")
else
  # De-duplicate (a file can be both staged and appear again via rename
  # detection, etc.) while preserving first-seen order; avoid bash 4+
  # associative arrays for compatibility with macOS's stock bash 3.2.
  while IFS= read -r line; do
    [ -n "$line" ] && changed_files+=("$line")
  done < <(
    {
      git diff --name-only HEAD
      git status --porcelain | sed -n 's/^?? //p'
    } | awk '!seen[$0]++'
  )
fi

if [ "${#changed_files[@]}" -eq 0 ]; then
  echo "clean"
  exit 0
fi

echo "agent_gate: changed files"
printf '  %s\n' "${changed_files[@]}"

status=0

echo "agent_gate: git diff --check"
if ! git diff --check HEAD; then
  status=1
fi

# Portable file-size probe: macOS/BSD stat uses -f%z, GNU stat uses -c%s.
if stat -f%z "$0" >/dev/null 2>&1; then
  stat_size() { stat -f%z "$1" 2>/dev/null; }
else
  stat_size() { stat -c%s "$1" 2>/dev/null; }
fi

max_bytes=1048576 # 1 MB
echo "agent_gate: large-file guard (> ${max_bytes} bytes)"
for f in "${changed_files[@]}"; do
  if [ -f "$f" ]; then
    size="$(stat_size "$f")"
    if [ -n "$size" ] && [ "$size" -gt "$max_bytes" ]; then
      echo "agent_gate: FAIL ${f} is ${size} bytes (> ${max_bytes}); evidence artifacts must stay out of git"
      status=1
    fi
  fi
done

declare -a dart_files=()
declare -a md_files=()
declare -a sh_files=()
declare -a py_test_files=()

_agent_gate_add_py_test() {
  local candidate="$1"
  local existing
  for existing in "${py_test_files[@]:-}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  py_test_files+=("$candidate")
}

for f in "${changed_files[@]}"; do
  case "$f" in
    *.dart)
      if [ -f "$f" ]; then
        dart_files+=("$f")
      fi
      ;;
    *.md)
      case "$f" in
        docs/control/history/*|logs/*)
          ;;
        *)
          if [ -f "$f" ]; then
            md_files+=("$f")
          fi
          ;;
      esac
      ;;
    *.sh)
      if [ -f "$f" ]; then
        sh_files+=("$f")
      fi
      ;;
    scripts/test_*.py)
      if [ -f "$f" ]; then
        _agent_gate_add_py_test "$f"
      fi
      ;;
    scripts/*.py)
      base="$(basename "$f" .py)"
      candidate="scripts/test_${base}.py"
      if [ -f "$candidate" ]; then
        _agent_gate_add_py_test "$candidate"
      fi
      ;;
  esac
done

if [ "${#dart_files[@]}" -gt 0 ]; then
  echo "agent_gate: dart format --set-exit-if-changed ${dart_files[*]}"
  if ! dart format --set-exit-if-changed "${dart_files[@]}"; then
    status=1
  fi

  echo "agent_gate: flutter analyze --no-pub"
  if ! flutter analyze --no-pub; then
    status=1
  fi
fi

if [ "${#md_files[@]}" -gt 0 ]; then
  echo "agent_gate: npx --yes markdownlint-cli2 ${md_files[*]}"
  if ! npx --yes markdownlint-cli2 "${md_files[@]}"; then
    status=1
  fi
fi

if [ "${#sh_files[@]}" -gt 0 ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    echo "agent_gate: shellcheck --severity=error ${sh_files[*]}"
    if ! shellcheck --severity=error "${sh_files[@]}"; then
      status=1
    fi
  else
    echo "agent_gate: shellcheck not installed; skipping shell lint for ${sh_files[*]}"
  fi
fi

if [ "${#py_test_files[@]}" -gt 0 ]; then
  py_test_count="${#py_test_files[@]}"
  if [ "$py_test_count" -gt 5 ]; then
    echo "agent_gate: ${py_test_count} python test files in scope (cap 5); running all anyway"
  fi
  echo "agent_gate: python3 ${py_test_files[*]}"
  for t in "${py_test_files[@]}"; do
    if ! python3 "$t"; then
      status=1
    fi
  done
fi

if [ "$status" -eq 0 ]; then
  echo "agent_gate: pass"
else
  echo "agent_gate: fail"
fi

exit "$status"
