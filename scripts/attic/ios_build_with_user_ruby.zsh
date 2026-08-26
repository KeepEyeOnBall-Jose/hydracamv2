#!/usr/bin/env zsh

set -euo pipefail

echo "[ios_build] Using SHELL: $SHELL"
echo "[ios_build] HOME: $HOME"

# Prefer Homebrew Ruby and gems like in your terminal session
export PATH=/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH

if [ -f "$HOME/.zprofile" ]; then
  source "$HOME/.zprofile"
elif [ -f "$HOME/.bash_profile" ]; then
  source "$HOME/.bash_profile"
fi

echo "[ios_build] RUBY: $(which ruby)"
echo "[ios_build] ruby -v: $(ruby -v)"
echo "[ios_build] POD: $(which pod)"
echo "[ios_build] pod --version: $(pod --version)"

cd "$(dirname "$0")/.."

echo "[ios_build] Running: flutter clean"
flutter clean

echo "[ios_build] Running: flutter pub get"
flutter pub get

echo "[ios_build] Running: pod install in ios via user Ruby"
cd ios
pod install

cd ..
echo "[ios_build] Running: flutter build ios --debug"
flutter build ios --debug

echo "[ios_build] Completed iOS build with user Ruby."
