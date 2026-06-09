#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMEBREW_RUBY_BIN="${HOMEBREW_RUBY_BIN:-/opt/homebrew/opt/ruby/bin}"
HOMEBREW_RUBY_GEMS_BIN="${HOMEBREW_RUBY_GEMS_BIN:-/opt/homebrew/lib/ruby/gems/3.4.0/bin}"

export PATH="$HOMEBREW_RUBY_BIN:$HOMEBREW_RUBY_GEMS_BIN:$PATH"

cd "$ROOT_DIR/ios"
exec bundle exec fastlane "$@"
