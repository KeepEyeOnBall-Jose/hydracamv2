# Evidence Run: Win11 C Drive Cleanup Plan

- Source: user request to SSH into the Win11 development host and plan C:
  cleanup/dev-environment moveout.
- Host: `DESKTOP-02NDERS`
- SSH target: `jose@100.110.8.112`
- SSH key: `/Users/jose/Downloads/codex_ssh_key`
- Status: plan created; no cleanup or file moveout executed.

## Evidence

- `storage-fast-inventory.json`: current drive sizes, environment variables,
  command locations, known large files, WSL state, and installed dev packages.
- `dev-cache-breakdown.json`: child-size breakdown for C:/D: dev roots,
  Android SDK, Gradle, Pub, Docker, and checkouts.
- `large-root-download-files.csv`: top-level user-root, Downloads, and Desktop
  file listing for large obvious archive candidates.
- `win11-storage-fast-inventory.ps1` and `win11-dev-cache-breakdown.ps1`:
  read-only inventory scripts used for this pass.

## Key Findings

- C: is effectively full: `0.14 GiB` free of `388.76 GiB`.
- D: is the best moveout target: `1755.69 GiB` free of `9313.97 GiB`.
- Major C: relief candidates are WSL Ubuntu (`22.18 GiB`), Android SDK system
  images (`13.81 GiB`), Docker WSL data (`7.82 GiB`), `C:\src` (`6.93 GiB`),
  Downloads (`3.98 GiB`), a PyCharm heap dump (`3.21 GiB`), Gradle/Pub caches,
  and the C: HydraCam checkout (`1.05 GiB`).

## Plan

Durable plan:
`docs/superpowers/plans/2026-06-07-win11-dev-host-storage-cleanup.md`.
