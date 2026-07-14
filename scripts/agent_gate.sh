#!/usr/bin/env bash
# Change-scoped validation gate for agent sessions.
#
# Computes the set of changed files (staged + unstaged + untracked, relative
# to HEAD) unless explicit file paths are passed as arguments, then runs the
# mechanical checks that apply to the files that actually changed:
#   - Always: `git diff --check` (trailing whitespace / conflict markers).
#   - Any changed `.dart` file: `dart format --set-exit-if-changed` on those
#     files, then `flutter analyze --no-pub`.
#   - Any changed `.md` file outside `docs/control/history/` and `logs/`:
#     `npx --yes markdownlint-cli2` on those files.
# On a clean tree with no arguments, prints "clean" and exits 0 immediately.
#
# Usage:
#   bash scripts/agent_gate.sh                # auto-detect changed files
#   bash scripts/agent_gate.sh path/one.dart path/two.md   # explicit paths

set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

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

declare -a dart_files=()
declare -a md_files=()
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

if [ "$status" -eq 0 ]; then
  echo "agent_gate: pass"
else
  echo "agent_gate: fail"
fi

exit "$status"
