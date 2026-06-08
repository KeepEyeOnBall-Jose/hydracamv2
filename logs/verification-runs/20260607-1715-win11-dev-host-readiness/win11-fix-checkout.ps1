$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoDir = Join-Path $env:USERPROFILE "src\work\hydracamv2"
$RepoUrl = "https://github.com/KeepEyeOnBall-Jose/hydracamv2.git"

Write-Output "repo=$RepoDir"
if (Test-Path $RepoDir) {
  if (Test-Path (Join-Path $RepoDir ".git")) {
    Write-Output "removing-broken-windows-checkout=$RepoDir"
    git -C $RepoDir status -sb
  }
  Remove-Item -Recurse -Force $RepoDir
}

New-Item -ItemType Directory -Force -Path (Split-Path $RepoDir) | Out-Null
git clone --filter=blob:none --no-checkout --branch master-jose-2025 $RepoUrl $RepoDir
git -C $RepoDir sparse-checkout init --cone
git -C $RepoDir sparse-checkout set android ios lib test windows linux web macos integration_test docs automation_scenarios
git -C $RepoDir checkout -f master-jose-2025
git -C $RepoDir status -sb
git -C $RepoDir rev-parse HEAD
git -C $RepoDir sparse-checkout list
