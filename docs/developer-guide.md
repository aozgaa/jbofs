# Developer Guide

This guide captures the operational assumptions, edge cases, and local development workflow for `jbofs`.

## Ubuntu Packages

On Ubuntu 24.04, install the tools used by the setup scripts and tests:

```bash
sudo apt update
sudo apt install -y python3 python3-pytest python3-yaml xfsprogs fio util-linux nvme-cli
```

Notes:

- `python3-yaml` is required by `scripts/setup/lib_plan.py`.
- `xfsprogs` provides `mkfs.xfs`.
- `fio` is only needed for benchmark runs, not for normal tests.
- `util-linux` provides `lsblk`, `findmnt`, `blkid`, and `wipefs`.
- `nvme-cli` is useful for hardware bring-up and validation.

## Running Tests

Run the full suite from the repo root:

```bash
pytest
```

Run one file:

```bash
pytest tests/test_jbofs_sync.py -q
```

Test collection depends on [tests/conftest.py](/home/fozga/r/art/nvme/tests/conftest.py), which inserts the repo root into `sys.path` so imports from `scripts.setup` work under plain `pytest`.

## Script Layout

Setup/provisioning scripts live under `scripts/setup/`:

- inventory, planning, apply, verify, fio, report, aliases
- setup-only libraries in `scripts/setup/lib_inventory.py` and `scripts/setup/lib_plan.py`

Operational `jbofs` helpers stay at `scripts/`:

- `jbofs cp`
- `jbofs rm`
- `jbofs sync`
- `jbofs prune`

## Namespace Model

- Physical data lives on XFS filesystems mounted under `/srv/jbofs/raw/<stable-id>`.
- Friendly aliases `/srv/jbofs/aliased/disk-N` are created by `scripts/setup/07_aliases.sh`.
- Logical symlinks live under `/srv/jbofs/logical`.

The alias script must run before helpers that rely on numeric disk aliases.

## Helper Responsibilities

`jbofs cp`

- Copies files into physical storage and creates logical symlinks.
- Recursive mode uses rsync-style semantics:
  - `srcdir/` copies contents
  - `srcdir` copies the directory itself
- Recursive copy requires exactly one of `--round-robin` or `--batch`.

`jbofs rm`

- Removes logical symlinks, physical data, or both.
- Accepts logical paths, stable physical paths, and numeric alias paths.
- Recursive remove traverses directories under either logical or physical roots.

`jbofs sync`

- Additive only.
- Creates missing logical symlinks for physical files that already exist.
- Can scan all stable roots, one numeric disk, or one physical subtree.
- Conflicting logical paths are reported and skipped.

`jbofs prune`

- Removes broken logical symlinks only.
- Never deletes physical data.
- Intended as the destructive counterpart to additive `jbofs sync`.

## Edge Cases Already Handled

### Stale `/etc/fstab` comments can misclassify disks

The inventory classifier originally treated installer comments like:

```text
# / was on /dev/nvme0n1p3 during installation
```

as active `fstab` references. The parser now ignores comments and only matches active entries.

### XFS labels must be unique

Truncating similar Samsung serial numbers produced duplicate labels in generated `mkfs.xfs` commands. Setup plan generation now derives unique labels from the tail of the stable device ID.

### Fresh XFS mountpoints are root-owned

After formatting and mounting, write probes can fail with `EACCES` for non-root users. This is expected until ownership or permissions are adjusted, for example with `chown`.

### `pytest` and direct Python execution behave differently

Direct `python3` execution from the repo root could import `scripts.setup`, but plain `pytest` collection initially could not. `tests/conftest.py` normalizes import behavior.

### Recursive copy semantics are subtle

Recursive `jbofs cp` intentionally follows rsync-style source semantics because they are less surprising than ad hoc rules:

- trailing slash means copy contents
- no trailing slash means copy the directory itself

### Physical paths may have multiple logical symlinks

`jbofs rm` removes all matching logical symlinks when invoked from a physical file path. This avoids ambiguous partial cleanup.

### Sync and prune are intentionally separate

- `jbofs sync` never deletes
- `jbofs prune` only removes broken logical symlinks

This separation reduces the chance of accidental destructive repair actions.

## Typical Developer Workflow

1. Update or add tests.
2. Run `pytest`.
3. Update docs if CLI/help text changed.
4. Re-run `pytest`.

For storage bring-up changes, also validate generated artifacts manually:

```bash
python3 scripts/setup/01_inventory.py --output-dir artifacts
python3 scripts/setup/02_plan.py --inventory artifacts/inventory.json --selected config/selected-devices.yaml --protected config/protected-devices.yaml --output-dir artifacts
sed -n '1,200p' artifacts/setup-plan.md
```
