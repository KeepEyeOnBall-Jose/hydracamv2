$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyaZaM3VqO349vKpcy6kQx9P83wvxKoa76GfSzQ3b0R codex-client-2026-06-07"
$SystemSid = "*S-1-5-18"
$AdminsSid = "*S-1-5-32-544"
$CurrentSid = "*" + ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

function Section($Name) {
  Write-Output ""
  Write-Output "=== $Name ==="
}

Section "identity"
Write-Output "whoami=$(whoami)"
Write-Output "sid=$CurrentSid"

Section "user-authorized-keys"
$UserSsh = Join-Path $env:USERPROFILE ".ssh"
$UserAuth = Join-Path $UserSsh "authorized_keys"
New-Item -ItemType Directory -Force -Path $UserSsh | Out-Null
Set-Content -Path $UserAuth -Value $PublicKey -Encoding ascii
icacls.exe $UserSsh /inheritance:r
icacls.exe $UserSsh /grant "${CurrentSid}:(OI)(CI)F" "${SystemSid}:(OI)(CI)F"
icacls.exe $UserAuth /inheritance:r
icacls.exe $UserAuth /grant "${CurrentSid}:F" "${SystemSid}:F"
Write-Output "user_auth=$UserAuth"
Get-Content $UserAuth

Section "administrators-authorized-keys"
$AdminAuth = "$env:ProgramData\ssh\administrators_authorized_keys"
Set-Content -Path $AdminAuth -Value $PublicKey -Encoding ascii
icacls.exe $AdminAuth /inheritance:r
icacls.exe $AdminAuth /grant "${AdminsSid}:F" "${SystemSid}:F"
Write-Output "admin_auth=$AdminAuth"
Get-Content $AdminAuth

Section "sshd-config-relevant"
Get-Content "$env:ProgramData\ssh\sshd_config" |
  Select-String "PubkeyAuthentication|AuthorizedKeysFile|Match|administrators_authorized_keys"

Section "restart"
Restart-Service sshd
Get-Service sshd | Select-Object Status,Name,StartType | ConvertTo-Csv -NoTypeInformation
