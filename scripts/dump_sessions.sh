#!/usr/bin/env bash
set -euo pipefail
serial=${1:-emulator-5554}
package=${2:-com.amaia23.hydracam}
outdir=${3:-evidence/device_sessions}
mkdir -p "$outdir"
out="$outdir/${serial}.txt"
echo "=== $serial ===" > "$out"
if adb -s "$serial" shell "run-as $package true" >/dev/null 2>&1; then
  # Get listing of session dirs
  dirs=$(adb -s "$serial" shell run-as "$package" ls -1 files/sessions || true)
  if [ -n "$dirs" ]; then
    echo "$dirs" | while IFS= read -r d; do
      echo "--- files/sessions/$d ---" >> "$out"
      if adb -s "$serial" shell run-as "$package" test -f "files/sessions/$d/metadata.json" >/dev/null 2>&1; then
        echo "METADATA:" >> "$out"
        adb -s "$serial" shell run-as "$package" cat "files/sessions/$d/metadata.json" >> "$out" 2>&1 || true
      fi
    done
  fi
else
  echo "run-as failed, trying /data/data" >> "$out"
  adb -s "$serial" shell ls -la /data/data/$package/files/sessions >> "$out" 2>&1 || true
  # attempt to read metadata files directly
  dirs2=$(adb -s "$serial" shell ls -1 /data/data/$package/files/sessions || true)
  if [ -n "$dirs2" ]; then
    echo "$dirs2" | while IFS= read -r d; do
      echo "--- /data/data/$package/files/sessions/$d ---" >> "$out"
      if adb -s "$serial" shell test -f "/data/data/$package/files/sessions/$d/metadata.json" >/dev/null 2>&1; then
        echo "METADATA:" >> "$out"
        adb -s "$serial" shell cat "/data/data/$package/files/sessions/$d/metadata.json" >> "$out" 2>&1 || true
      fi
    done
  fi
fi

echo "--- written to $out"
echo
echo "--- grep for quad-1763406579 ---"
grep -R "quad-1763406579" "$out" || echo "not found"
