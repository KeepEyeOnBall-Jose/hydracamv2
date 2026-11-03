#!/usr/bin/env bash
# Vendors the C1 part of media-timeline's court-contracts package (JSON Schema +
# good/bad fixtures) into the court flavor's test resources, with a sha256
# manifest. CourtContractsConformanceTest checks K1 against it and fails when the
# copy drifts from the manifest.
#
# Do not edit the vendored copy. To take a contract change, re-run this with a
# newer sha; the diff of the folder is the contract change.
#
# Usage:
#   bash scripts/vendor_court_contracts.sh <media-timeline commit sha>

set -euo pipefail

sha="${1:?usage: vendor_court_contracts.sh <media-timeline commit sha>}"
repo="KeepEyeOnBall-Jose/media-timeline"
pkg="packages/court-contracts"
root="$(git rev-parse --show-toplevel)"
dest="$root/android/app/src/testCourt/resources/court-contracts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh api "repos/$repo/git/trees/$sha?recursive=1" > "$tmp/tree.json"
if [ "$(jq -r .truncated "$tmp/tree.json")" != "false" ]; then
  echo "vendor_court_contracts: tree listing truncated" >&2
  exit 1
fi
jq -r '.tree[] | select(.type == "blob") | .path + " " + .sha' "$tmp/tree.json" |
  grep -E "^$pkg/(json-schema/index\.json|json-schema/c1/|fixtures/c1/)" > "$tmp/list"

while read -r path blob; do
  out="$tmp/files/${path#"$pkg"/}"
  mkdir -p "$(dirname "$out")"
  gh api "repos/$repo/git/blobs/$blob" --jq .content | base64 --decode > "$out"
  if [ "$(git hash-object "$out")" != "$blob" ]; then
    echo "vendor_court_contracts: blob mismatch for $path" >&2
    exit 1
  fi
done < "$tmp/list"

rm -rf "$dest"
mkdir -p "$dest"
cp -R "$tmp/files/." "$dest/"
{
  echo "# source: $repo@$sha $pkg"
  (cd "$dest" && find . -type f ! -name MANIFEST.sha256 | sed 's|^\./||' | LC_ALL=C sort |
    while read -r file; do shasum -a 256 "$file"; done)
} > "$dest/MANIFEST.sha256"

echo "vendor_court_contracts: $(wc -l < "$tmp/list" | tr -d ' ') files from $repo@$sha"
