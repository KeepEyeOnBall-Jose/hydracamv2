# Evidence Run: Win11 WSL Authorized Cache Cleanup

- Source: user authorized cleanup of `Ubuntu-22.04` `/home/jose/borrame`, pip
  cache, and mamba cache, with explicit instruction not to delete
  `/home/jose/keob-nodes`.
- Host: `DESKTOP-02NDERS`
- SSH target: `jose@100.110.8.112`
- SSH key: `/Users/jose/Downloads/codex_ssh_key`
- Status: cleanup complete.

## Actions Executed

Deleted inside `Ubuntu-22.04`:

- `/home/jose/borrame`
- `/home/jose/.cache/pip`
- `/home/jose/.local/share/mamba/pkgs/cache`

Did not delete:

- `/home/jose/keob-nodes`

## Evidence

- `cleanup-output.txt`: command output from the guarded cleanup script.
- `post-cleanup-windows-space.txt`: Windows drive-space and VHD-size check
  after cleanup.
- `wsl-list-after.txt`: final WSL state after terminating both inspected
  Ubuntu distros.

## Results

Inside `Ubuntu-22.04`:

| Path | Before | After |
| --- | ---: | --- |
| `/home/jose/borrame` | `4.5G` | missing |
| `/home/jose/.cache/pip` | `3.2G` | missing |
| `/home/jose/.local/share/mamba/pkgs/cache` | `788M` | missing |
| `/home/jose/keob-nodes` | `2.1G` | present, unchanged |

Filesystem usage inside WSL changed from `21G` used / `218G` available to
`13G` used / `226G` available.

Windows host after cleanup:

- C: reported `57.18 GiB` free of `388.76 GiB`.
- `Ubuntu-22.04` `ext4.vhdx` still reported `22.18 GiB`.
- `Ubuntu-20.04`, `Ubuntu-22.04`, and `docker-desktop` were left stopped.
