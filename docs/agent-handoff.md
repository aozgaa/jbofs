# Agent Handoff

This file is a high-signal handoff for a subsequent agent or LLM working in this repo. It is intentionally redundant with some other docs so a future agent can bootstrap quickly without reconstructing decisions from commit history.

## Repo Purpose

`jbofs` is a "just bunch of file systems" workflow for:

- one filesystem per selected storage device
- explicit physical file placement
- a separate logical symlink namespace
- small helper scripts for copy/remove/repair

The repo is not implementing a new filesystem. It is codifying an operational model and a set of helper commands around ordinary XFS filesystems.

## Current Architecture

Physical storage:

- canonical mounts: `/srv/jbofs/raw/<stable-id>/...`
- short aliases: `/srv/jbofs/aliased/disk-N`

Logical namespace:

- symlinks under `/srv/jbofs/logical/...`

Core command surface:

- `scripts/jbofs-cp.sh`
- `scripts/jbofs-rm.sh`
- `scripts/jbofs-sync.sh`
- `scripts/jbofs-prune.sh`

Setup/provisioning scripts:

- `scripts/setup/01_inventory.py`
- `scripts/setup/02_plan.py`
- `scripts/setup/03_apply.sh`
- `scripts/setup/04_verify.py`
- `scripts/setup/05_fio_bench.sh`
- `scripts/setup/06_report.py`
- `scripts/setup/07_aliases.sh`
- `scripts/setup/lib_inventory.py`
- `scripts/setup/lib_plan.py`

## Documentation Map

- [README.md](/home/fozga/r/art/nvme/README.md): front door only
- [docs/design.md](/home/fozga/r/art/nvme/docs/design.md): architecture and rationale
- [docs/comparison.md](/home/fozga/r/art/nvme/docs/comparison.md): comparison to ZFS, RAID, mergerfs, Stow, etc.
- [docs/setup-guide.md](/home/fozga/r/art/nvme/docs/setup-guide.md): bring-up flow
- [docs/user-guide.md](/home/fozga/r/art/nvme/docs/user-guide.md): day-to-day operations
- [docs/benchmarking.md](/home/fozga/r/art/nvme/docs/benchmarking.md): fio and reporting
- [docs/developer-guide.md](/home/fozga/r/art/nvme/docs/developer-guide.md): package install, tests, edge cases
- this file: compact operational handoff for future agents

## Key Design Decisions Already Made

### Why `jbofs` exists

The user explicitly preferred:

- explicit placement over transparent pooling
- independent per-disk filesystems over RAID / pooled CoW filesystems
- a logical namespace built from symlinks
- no FUSE layer in the steady-state access path

### Why not mergerfs as the primary model

We evaluated it seriously. `mergerfs` is a valid alternative and now has documented passthrough-I/O support, but the user judged the semantics too messy for the desired workflow. The repo docs now acknowledge mergerfs’ strengths and FUSE passthrough nuance in [docs/comparison.md](/home/fozga/r/art/nvme/docs/comparison.md).

### Why sync and prune are separate

- `jbofs-sync.sh` is additive only
- `jbofs-prune.sh` is destructive but only removes broken logical symlinks

This split is intentional to reduce accidental destructive repair actions.

### Why filesystem aliases exist

Stable IDs are the canonical mount roots, but `disk-N` aliases are much easier for humans to use when placing files. `scripts/setup/07_aliases.sh` builds `/srv/jbofs/aliased/disk-N` from the selected raw mounts.

### Recursive copy semantics

`jbofs-cp.sh` uses rsync-style source semantics:

- `srcdir/` copies contents
- `srcdir` copies the directory itself

Recursive copy requires exactly one grouping mode:

- `--round-robin`
- `--batch`

### `jbofs-rm.sh` semantics

- default is `--ensure-data --rm-both`
- can operate from logical or physical paths
- physical input accepts both raw roots and aliased roots
- removing by physical path removes all matching logical symlinks

## Known Edge Cases Already Solved

### `fstab` comment false positive in inventory classification

We hit a bug where installer comments like:

```text
# / was on /dev/nvme0n1p3 during installation
```

caused a data disk to be classified as `CAUTION`.

Fix:

- `scripts/setup/lib_inventory.py` now ignores comments and only matches active `fstab` entries

### Duplicate XFS labels in generated plan

Truncating similar Samsung serials produced label collisions in `mkfs.xfs -L ...`.

Fix:

- `scripts/setup/lib_plan.py` now derives a unique short label from the tail of the stable ID

### Fresh XFS mountpoints are root-owned

Verification write probes can fail with `EACCES` on new mounts until ownership is changed. This is expected, not a mount failure.

### `pytest` import-path issue

Plain `pytest` originally failed to import `scripts.setup`.

Fix:

- `tests/conftest.py` inserts the repo root into `sys.path`

### Tempdir cleanup in tests

Tests now use `TemporaryDirectory()` context managers so tempdirs are cleaned up automatically.

## Tests and Verification

Run everything from repo root:

```bash
pytest
```

Current expected status at the time of writing:

- full suite passes
- tests cover setup planning, helper semantics, README presence checks, and repo layout expectations

The main test files are:

- `tests/test_inventory_classification.py`
- `tests/test_plan_guardrails.py`
- `tests/test_jbofs_cp.py`
- `tests/test_jbofs_rm.py`
- `tests/test_jbofs_sync.py`
- `tests/test_jbofs_prune.py`
- `tests/test_readme_commands.py`
- `tests/test_repo_layout.py`

## Ubuntu Packages / Local Tooling

See [docs/developer-guide.md](/home/fozga/r/art/nvme/docs/developer-guide.md) for the canonical package list.

Important packages:

- `python3`
- `python3-pytest`
- `python3-yaml`
- `xfsprogs`
- `fio`
- `util-linux`
- `nvme-cli`

## Current Setup Flow

The expected operator flow is:

1. `scripts/setup/01_inventory.py`
2. edit `config/protected-devices.yaml`
3. edit `config/selected-devices.yaml`
4. `scripts/setup/02_plan.py`
5. review generated plan
6. `scripts/setup/03_apply.sh`
7. `scripts/setup/04_verify.py`
8. `scripts/setup/07_aliases.sh`

After that:

- user-facing file operations use the `jbofs-*` helper scripts
- benchmarking uses `05_fio_bench.sh` and `06_report.py`

## Operational Semantics of the Helper Scripts

### `jbofs-cp.sh`

- one file or recursive tree copy
- explicit disk or policy selection
- creates logical symlink entries
- does not silently choose recursive grouping; requires `--round-robin` xor `--batch`

### `jbofs-rm.sh`

- can remove logical link only, data only, or both
- recursive support exists
- this is a user-intent command, not just a stale-link cleanup tool

### `jbofs-sync.sh`

- discovers physical files and creates missing logical symlinks
- can scope by:
  - `--disk=N`
  - `--disk-path PATH`
  - `--logical-prefix RELPATH`
- skips conflicts rather than overwriting them

### `jbofs-prune.sh`

- removes broken logical symlinks only
- can scope by `--logical-prefix`
- never deletes physical data

## Naming / Layout Conventions

- setup/provisioning scripts live in `scripts/setup/`
- user-facing operational helpers live directly in `scripts/`
- docs are split by purpose; keep README thin
- comparison/rationale belongs in docs, not README

## If You Need to Extend the Repo

Prefer:

- adding a dedicated guide instead of bloating README
- adding tests first for new helper behavior
- keeping destructive and additive repair operations separate
- preserving the explicit physical vs logical model

Be careful about:

- silently changing helper defaults
- introducing pooled or automatic behavior without making it explicit in docs and flags
- reintroducing import-path assumptions that break plain `pytest`

## Good Next Candidates for Future Work

- richer conflict reporting in `jbofs-sync.sh`
- `jbofs-ls` or similar inspection helper if users need path introspection
- maybe a concise operator cheatsheet
- maybe broader comparison appendix for clustered/distributed filesystems if ever relevant
