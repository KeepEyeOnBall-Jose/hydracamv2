"""Run the C1 vendor against pinned Git trees with the real phone fixtures."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "scripts/vendor_court_contracts.sh"
DEST = Path("android/app/src/testCourt/resources/court-contracts")
FILES = (
    "fixtures/c1/bad/ack--missing--body.ref.json",
    "fixtures/c1/good/ack.json",
    "json-schema/c1/ack.schema.json",
    "json-schema/index.json",
)

# Serve the two GitHub Git Data reads from local Git objects at the requested SHA.
LOCAL_GH = r"""#!/usr/bin/env bash
set -eu
key=${2##*/}
case "$2" in
  */git/trees/*)
    git -C "$UPSTREAM" ls-tree -r "${key%%\?*}" |
      jq -Rn '{truncated: false, tree: [inputs | split("\t") as [$meta, $path] |
        ($meta | split(" ")) as [$mode, $type, $sha] | {path:$path, type:$type, sha:$sha}]}'
    ;;
  */git/blobs/*) git -C "$UPSTREAM" cat-file blob "$key" | base64 ;;
  *) exit 1 ;;
esac
"""


class VendorCourtContractsTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.upstream = root / "upstream"
        self.consumer = root / "consumer"
        for repo in (self.upstream, self.consumer):
            subprocess.run(["git", "init", "-q", repo], check=True)
        gh = root / "gh"
        gh.write_text(LOCAL_GH)
        gh.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
            "UPSTREAM": str(self.upstream),
        }

    def commit(self):
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=self.upstream, text=True).strip()

        git("add", "-A")
        git(
            "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "-qm", "contract layout",
        )
        return git("rev-parse", "HEAD")

    def fill(self, package):
        for name in FILES:
            path = self.upstream / package / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / DEST / name, path)

    def vendor(self, sha):
        return subprocess.run(
            ["bash", VENDOR, sha], cwd=self.consumer, env=self.env,
            text=True, capture_output=True, timeout=20,
        )

    def test_pins_before_and_after_the_move_produce_the_same_blobs(self):
        legacy = "packages/court-contracts"
        self.fill(legacy)
        old = self.commit()
        (self.upstream / legacy).rename(self.upstream / "contracts")
        new = self.commit()
        for sha, package in [(new, "contracts"), (old, legacy)]:
            with self.subTest(package=package):
                result = self.vendor(sha)
                self.assertEqual(result.returncode, 0, result.stderr)
                manifest = [f"# source: KeepEyeOnBall-Jose/media-timeline@{sha} {package}"]
                for name in FILES:
                    data = (ROOT / DEST / name).read_bytes()
                    self.assertEqual((self.consumer / DEST / name).read_bytes(), data)
                    manifest.append(f"{hashlib.sha256(data).hexdigest()}  {name}")
                written = (self.consumer / DEST / "MANIFEST.sha256").read_text()
                self.assertEqual(written.splitlines(), manifest)

    def test_incomplete_tree_preserves_the_previous_copy(self):
        self.fill("packages/court-contracts")
        (self.upstream / "packages/court-contracts" / FILES[0]).unlink()
        prior = self.consumer / DEST / FILES[0]
        prior.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / DEST / FILES[0], prior)
        result = self.vendor(self.commit())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(prior.read_bytes(), (ROOT / DEST / FILES[0]).read_bytes())


if __name__ == "__main__":
    unittest.main()
