$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptPath = "/mnt/c/Users/jose/codex-win11-dev-host-full-readiness/win11-wsl-linux-clean-build.sh"

Write-Output "timestamp=$(Get-Date -Format o)"
Write-Output "script=$ScriptPath"
wsl -d Ubuntu-22.04 -u jose -- bash $ScriptPath
Write-Output "wsl_linux_clean_build_exit_code=$LASTEXITCODE"
exit $LASTEXITCODE
