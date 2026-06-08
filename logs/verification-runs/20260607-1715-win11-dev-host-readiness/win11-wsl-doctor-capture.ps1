$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Output ""
Write-Output "=== wsl flutter doctor captured ==="
wsl -d Ubuntu-22.04 -- bash -lc 'set -euo pipefail; export PATH="$HOME/development/flutter/bin:$PATH"; { flutter --version; flutter doctor -v; } 2>&1 | tee /tmp/hydracam-wsl-flutter-doctor.txt'
Write-Output "[step-exit-code] $LASTEXITCODE"
