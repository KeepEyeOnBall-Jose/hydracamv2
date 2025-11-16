#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj"

# CLI flags
AUTO_YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--yes|-y]"; exit 0 ;;
    *) echo "Unknown arg: $1"; echo "Usage: $0 [--yes|-y]"; exit 2 ;;
  esac
done

if [ ! -f "$PBX" ]; then
  echo "Cannot find Xcode project file at $PBX"
  exit 1
fi

echo "Backing up $PBX"
cp "$PBX" "$PBX.$(date +%s).bak"

echo "Disabling User Script Sandboxing (ENABLE_USER_SCRIPT_SANDBOXING = NO) where present..."
# Replace explicit YES -> NO occurrences for this key
perl -0777 -pe 's/ENABLE_USER_SCRIPT_SANDBOXING\s*=\s*YES\s*;/ENABLE_USER_SCRIPT_SANDBOXING = NO;/g' -i "$PBX"

echo "Ensuring buildSettings blocks include ENABLE_USER_SCRIPT_SANDBOXING = NO if missing..."
python3 - "$PBX" <<'PY'
import sys,re
path=sys.argv[1]
text=open(path,'r',encoding='utf-8').read()
out=[]
i=0
while True:
    m = re.search(r'buildSettings\s*=\s*\{', text[i:])
    if not m:
        out.append(text[i:])
        break
    start = i + m.start()
    brace = text.find('{', start)
    out.append(text[i:brace+1])
    # find matching closing brace for this block
    j = brace+1
    depth = 1
    while j < len(text) and depth>0:
        if text[j] == '{': depth += 1
        elif text[j] == '}': depth -= 1
        j += 1
    block = text[brace+1:j-1]
    if 'ENABLE_USER_SCRIPT_SANDBOXING' not in block:
        # ensure consistent indentation and semicolon
        block = block + '\n\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n\t\t'
    out.append(block)
    out.append('}')
    i = j
new=''.join(out)
open(path,'w',encoding='utf-8').write(new)
PY

echo "Updated $PBX"

if [ "$AUTO_YES" -eq 1 ]; then
  REPLY=Y
else
  read -p "Clean build folders and DerivedData for this project? [y/N] " -r
fi
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Removing Flutter build output..."
  rm -rf "$REPO_ROOT/build"
  echo "Cleaning iOS build artifacts..."
  (cd "$REPO_ROOT/ios" && xcodebuild -workspace Runner.xcworkspace -scheme Runner clean) || true
  echo "Removing DerivedData entries matching 'Runner' (may require elevated permissions)..."
  rm -rf ~/Library/Developer/Xcode/DerivedData/*Runner* || true
fi

echo "Quitting Xcode if running..."
osascript -e 'tell application "Xcode" to quit' 2>/dev/null || true
sleep 1

echo "Attempting to update RubyGems system (may prompt for sudo password)..."
if sudo gem update --system; then
  echo "RubyGems updated"
else
  echo "gem update --system failed; continuing. This is often fine on recent macOS (system Ruby may be older)."
fi

echo "Installing/Updating CocoaPods (try gem first, then Homebrew)..."
if sudo gem install cocoapods; then
  echo "CocoaPods installed via gem"
elif command -v brew >/dev/null 2>&1 && brew install cocoapods; then
  echo "CocoaPods installed via Homebrew"
else
  echo "Failed to install CocoaPods via sudo gem or Homebrew. Trying user install..."
  gem install --user-install cocoapods || {
    echo "CocoaPods installation failed. Please install manually (e.g. 'brew install cocoapods' or use a Ruby manager)."; exit 1;
  }
fi

echo "Running pod install --repo-update in ios/"
cd "$REPO_ROOT/ios"
pod install --repo-update

echo "Done. Please re-open Xcode and try a build. If you want to revert changes, restore the backup file created next to project.pbxproj." 
