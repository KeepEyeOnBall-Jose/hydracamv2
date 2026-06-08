# Evidence Run: Win11 WSL Worker/Garbage Inventory

- Source: user request to inspect `Ubuntu-20.04` and `Ubuntu-22.04` WSL
  instances for old KEOB worker setup and large temp/log/cache payloads.
- Host: `DESKTOP-02NDERS`
- SSH target: `jose@100.110.8.112`
- SSH key: `/Users/jose/Downloads/codex_ssh_key`
- Status: read-only inventory complete; no cleanup executed.

## WSL State

| Distro | State after run | WSL version | Windows backing store |
| --- | --- | ---: | --- |
| `Ubuntu-20.04` | Stopped | 1 | WSL1 `rootfs` at `C:\Users\jose\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu20.04LTS_79rhkp1fndgsc\LocalState\rootfs`; Windows-side recursive sizing timed out. |
| `Ubuntu-22.04` | Stopped | 2 | WSL2 VHD at `C:\Users\jose\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\LocalState\ext4.vhdx`, size `22.18 GiB`. |

## Ubuntu-20.04 Findings

- `/var/tmp` and `/tmp` are effectively empty.
- `/var/log` is small: `26M`, almost all under `/var/log/keob`.
- This distro does contain a KEOB worker setup:
  - User `ubuntu` has an `@reboot` crontab running
    `/home/ubuntu/bin/keob-nodes/queue-poller/queue-poller.py`.
  - The crontab appends to `/var/log/keob/queue-poller.log`.
  - `/home/ubuntu/bin/keob-nodes` is `2.4G` and includes credentials/SSH-key
    paths, so treat it as sensitive if archived or removed.
- Main space consumers:
  - `/home/ubuntu/venv`: `6.3G`, including old HoHoNet/HorizonNet Python
    environments and duplicated Torch libraries.
  - `/opt`: `9.9G`, including `/opt/bin` `7.0G`, old HoHoNet/HorizonNet zip,
    checkpoint, Blender, and model payloads, plus `/opt/pycharm-2024.3.1.1`
    `2.9G`.
  - `/home/vectorblanco`: `6.1G`, mostly `pycharm` `4.0G`,
    `.vscode-server` `1.2G`, `.cursor-server` `421M`, and IDE caches.
  - `/root/.cache`: `731M`, mostly JetBrains/PyCharm patch/update cache.

## Ubuntu-22.04 Findings

- `/var/tmp` is tiny: `4.0K`.
- `/var/log` is tiny: `1.0M`.
- `/tmp` is large: `3.5G`, dominated by stale pip unpack files under
  `/tmp/pip-unpack-13yyb2of`, including Torch and NVIDIA CUDA wheels from
  2026-02-27.
- KEOB repos exist but no active worker crontab was found:
  - `/home/jose/keob-nodes`: `2.1G`; contains KEOB credentials/SSH-key paths,
    so treat as sensitive.
  - `/home/jose/keob-modeller`: `7.0M`.
- Main space consumers inside the distro:
  - `/home/jose/borrame`: `4.5G`, mostly old Ubuntu 14.04 ISO mirror files.
  - `/home/jose/.cache`: `3.2G`, largely pip HTTP cache for Torch/NVIDIA
    packages.
  - `/home/jose/.local/share/mamba`: `1.9G`.
  - `/home/jose/development/flutter`: `1.6G`, likely current WSL Flutter lane.
  - `/home/jose/.vscode-server`: `463M`.

## Cleanup Candidates

No cleanup was executed. Candidate cleanup order:

1. `Ubuntu-22.04`: remove `/tmp/pip-unpack-*` and `/tmp/tmp*` if no pip process
   is running. Expected relief inside distro: about `3.5G`.
2. `Ubuntu-22.04`: clear pip cache under `/home/jose/.cache/pip` after deciding
   whether to keep offline package cache. Expected relief: up to about `3.2G`.
3. `Ubuntu-22.04`: archive/remove `/home/jose/borrame` old Ubuntu ISO mirror if
   not needed. Expected relief: about `4.5G`.
4. `Ubuntu-22.04`: clean mamba package cache if no active environment needs
   offline package rollback. Expected relief: up to about `1.9G`.
5. `Ubuntu-20.04`: disable the `ubuntu` `@reboot` KEOB queue-poller crontab
   before deleting anything that it references.
6. `Ubuntu-20.04`: archive/remove old HoHoNet/HorizonNet venvs and `/opt/bin`
   model/checkpoint payloads if no longer needed. Expected relief: more than
   `13G`.
7. `Ubuntu-20.04`: remove old PyCharm/VS Code/Cursor remote-server and cache
   payloads for `vectorblanco`, `ubuntu`, and `root` if no active remote IDE
   session depends on them. Expected relief: several GiB.
8. Sensitive KEOB repos (`keob-nodes`) should be archived with restricted
   permissions or left in place until credentials are reviewed.

For WSL2 `Ubuntu-22.04`, deleting files inside Linux will not necessarily shrink
the Windows `ext4.vhdx` immediately. Plan a WSL shutdown and VHD compaction or
export/import after cleanup if the goal is C: free-space recovery.

## Evidence Files

- `wsl-worker-inventory-summary.txt`: Windows identity, WSL list, package
  backing-store facts, and per-distro run metadata.
- `remote-evidence/Ubuntu-20.04-linux-inventory.txt`: first-pass Linux
  inventory for Ubuntu 20.04.
- `remote-evidence/Ubuntu-22.04-linux-inventory.txt`: first-pass Linux
  inventory for Ubuntu 22.04.
- `Ubuntu-20.04-home-breakdown.txt`: focused home/opt/cache breakdown.
- `Ubuntu-22.04-home-breakdown.txt`: focused home/opt/cache breakdown.
- `wsl-list-after.txt`: final WSL state after terminating both inspected
  distros.
