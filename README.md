# jbofs

Safety-first scripts to inventory NVMe devices, generate an explicit setup plan, and operate `jbofs`, a "just bunch of file systems" layout for sequential pcap-oriented workloads.

## Safety model

- Default behavior is non-destructive.
- `scripts/setup/03_apply.sh` refuses to execute without `--apply --confirm <token>`.
- Devices are controlled by two explicit lists:
  - `config/selected-devices.yaml`
  - `config/protected-devices.yaml`
- Only devices classified `SAFE_CANDIDATE` and explicitly selected are eligible.

## Directory layout

- Mount root: `/data/nvme/<stable-id>`
- Friendly aliases: `/data/nvme/0`, `/data/nvme/1`, `/data/nvme/2`, `/data/nvme/3`
- Symlink namespace on the root filesystem: `/data/logical`

Create the alias paths and the `/data/logical` namespace after the NVMe mounts are in place:

```bash
bash scripts/setup/07_aliases.sh
```

This script is required before using `--disk=N` with helper scripts. It creates:

- `/data/nvme/0..3` as symlinks to the stable NVMe mountpoints
- `/data/logical` on the root filesystem (`/dev/nvme4n1p3`)

`/data/logical` is intended to hold symlinks, not the actual large data files.

## Helper scripts

### `scripts/setup/07_aliases.sh`

Creates the numeric aliases under `/data/nvme` and ensures `/data/logical` exists.

Environment:

- `NVME_ROOT` default: `/data/nvme`
- `LOGICAL_ROOT` default: `/data/logical`
- `SELECTED_CONFIG` default: `config/selected-devices.yaml`

Typical usage:

```bash
bash scripts/setup/07_aliases.sh
ls -l /data/nvme
ls -ld /data/logical
```

### `scripts/jbofs-cp.sh`

Copies a file onto one selected NVMe backing path and creates a symlink into the logical namespace.

Usage:

```bash
bash scripts/jbofs-cp.sh (--disk=N | --policy=random|most-free) [-r|--recursive] [--round-robin|--batch] [-f|--force] [--dry-run] SRC LOGICAL_DEST
```

Rules:

- Exactly one of `--disk=N` or `--policy=random|most-free` is required.
- `LOGICAL_DEST` is relative to `/data/logical`.
- The top-level category is part of `LOGICAL_DEST`, for example `pcaps/...`, `logs/...`, or `captures/...`.
- `--disk=N` requires that `/data/nvme/N` already exists, usually from `scripts/setup/07_aliases.sh`.
- Recursive mode requires exactly one of `--round-robin` or `--batch`.
- `--round-robin` assigns files one by one across numeric NVMe aliases.
- `--batch` assigns the whole recursive copy to one selected disk.
- `srcdir/ means copy the contents`; `srcdir` means copy the directory itself.

Environment:

- `NVME_ROOT` default: `/data/nvme`
- `LOGICAL_ROOT` default: `/data/logical`

To force data to a specific disk, place the real file under one of the alias mountpoints:

```bash
mkdir -p /data/nvme/0/pcaps/symbol=ES/date=2026-03-11
cp capture.pcap /data/nvme/0/pcaps/symbol=ES/date=2026-03-11/file1.pcap
ln -s /data/nvme/0/pcaps/symbol=ES/date=2026-03-11/file1.pcap /data/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Or use the helper script, which copies to the chosen disk and creates the `/data/logical` symlink for you:

```bash
bash scripts/jbofs-cp.sh --disk=2 capture.pcap pcaps/symbol=ES/date=2026-03-11/file1.pcap
bash scripts/jbofs-cp.sh --policy=most-free capture.pcap pcaps/symbol=ES/date=2026-03-11/file2.pcap
bash scripts/jbofs-cp.sh --policy=random capture.pcap pcaps/symbol=ES/date=2026-03-11/file3.pcap
```

Dry-run example:

```bash
bash scripts/jbofs-cp.sh --disk=1 --dry-run capture.pcap pcaps/test/file1.pcap
```

Recursive examples:

```bash
bash scripts/jbofs-cp.sh -r --policy=most-free --batch ./captures pcaps/2026-03-12
bash scripts/jbofs-cp.sh -r --policy=random --round-robin ./captures/ pcaps/2026-03-12
```

If you want a shell function in `~/.bash_aliases`, use:

```bash
jbofs-cp() {
  /home/fozga/r/art/nvme/scripts/jbofs-cp.sh "$@"
}
```

### `scripts/jbofs-rm.sh`

Removes a logical symlink, the backing physical file, or both.

Usage:

```bash
bash scripts/jbofs-rm.sh [-r|--recursive] [--ensure-logical|--ensure-physical|--ensure-data] [--rm-link|--rm-data|--rm-both] [--dry-run] PATH
```

Defaults:

- `--ensure-data`
- `--rm-both`

Rules:

- Ensure flags are mutually exclusive.
- Remove flags are mutually exclusive.
- The input path must be under `/data`.
- `--ensure-logical` restricts the input to `/data/logical/...`.
- `--ensure-physical` restricts the input to `/data/nvme/...`, including both stable mount paths and numeric aliases.
- When removing by physical path, all matching logical symlinks under `/data/logical` are removed.
- `-r` recurses through logical or physical directories and applies the selected remove mode to every matching file.

Examples:

```bash
bash scripts/jbofs-rm.sh --dry-run /data/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
bash scripts/jbofs-rm.sh --ensure-logical --rm-link /data/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
bash scripts/jbofs-rm.sh --ensure-physical --rm-both /data/nvme/0/pcaps/symbol=ES/date=2026-03-11/file1.pcap
bash scripts/jbofs-rm.sh -r --ensure-logical /data/logical/pcaps/2026-03-11
```

### `scripts/jbofs-sync.sh`

Adds missing logical symlinks for files that already exist on jbofs disks. This command is additive only; stale symlink removal will live in a separate prune command.

Usage:

```bash
bash scripts/jbofs-sync.sh [--disk=N | --disk-path PATH] [--logical-prefix RELPATH] [--dry-run]
```

Rules:

- With no scope flags, sync scans all stable physical mount roots under `/data/nvme`.
- `--disk=N` syncs only one numeric alias such as `/data/nvme/1`.
- `--disk-path PATH` syncs only one physical subtree, which may be given through a numeric alias or a stable mount path.
- `--logical-prefix RELPATH` filters synced files by logical relative path such as `pcaps/2026-03-12`.
- Existing correct symlinks are left untouched.
- Conflicting logical paths are reported and skipped.

Examples:

```bash
bash scripts/jbofs-sync.sh
bash scripts/jbofs-sync.sh --disk=1
bash scripts/jbofs-sync.sh --disk-path /data/nvme/0/pcaps --logical-prefix pcaps/2026-03-12
bash scripts/jbofs-sync.sh --dry-run
```

### `scripts/jbofs-prune.sh`

Removes broken logical symlinks under `/data/logical`. This is the destructive counterpart to additive `jbofs-sync`; it does not delete physical files.

Usage:

```bash
bash scripts/jbofs-prune.sh [--logical-prefix RELPATH] [--dry-run]
```

Rules:

- Prune only examines symlinks under `/data/logical`.
- Valid symlinks are left untouched.
- Regular files are ignored.
- `--logical-prefix RELPATH` scopes pruning to one logical subtree.

Examples:

```bash
bash scripts/jbofs-prune.sh
bash scripts/jbofs-prune.sh --logical-prefix pcaps/2026-03-12
bash scripts/jbofs-prune.sh --dry-run
```

## End-to-end workflow

1. Inventory hardware and current mounts.

```bash
python3 scripts/setup/01_inventory.py --output-dir artifacts
```

2. Review `artifacts/inventory.md`, then set explicit selections/protections:

```yaml
# config/selected-devices.yaml
selected_devices:
  - nvme-EXAMPLE_SERIAL_A
  - nvme-EXAMPLE_SERIAL_B
```

```yaml
# config/protected-devices.yaml
protected_devices:
  - nvme-ROOT_DISK_SERIAL
```

3. Generate a guarded setup plan (still not applied):

```bash
python3 scripts/setup/02_plan.py \
  --inventory artifacts/inventory.json \
  --selected config/selected-devices.yaml \
  --protected config/protected-devices.yaml \
  --output-dir artifacts
```

4. Review `artifacts/setup-plan.md` and `artifacts/setup-plan.sh` manually.

5. Apply only when ready, with explicit confirmation token printed by step 3:

```bash
bash scripts/setup/03_apply.sh --plan artifacts/setup-plan.sh --apply --confirm <token>
```

6. Verify mounts and optionally test write access:

```bash
python3 scripts/setup/04_verify.py --mount-root /data/nvme --probe-write --output-dir artifacts
```

7. Run fio benchmarks (dry-run first, then apply):

```bash
bash scripts/setup/05_fio_bench.sh --mount-root /data/nvme --dry-run
bash scripts/setup/05_fio_bench.sh --mount-root /data/nvme --profiles seq_write,seq_read,mixed_iter --runtime 60 --apply
```

8. Build a consolidated report:

```bash
python3 scripts/setup/06_report.py --inventory artifacts/inventory.json --verify artifacts/verify.json --output artifacts/report.md
```

## Artifacts

- Inventory: `artifacts/inventory.json`, `artifacts/inventory.md`
- Plan: `artifacts/setup-plan.sh`, `artifacts/setup-plan.md`
- Apply logs: `artifacts/logs/apply-<timestamp>.log`
- Verify: `artifacts/verify.json`, `artifacts/verify.md`
- fio: `artifacts/fio/<timestamp>/*.json`
- Consolidated report: `artifacts/report.md`

## Notes

- This toolkit intentionally avoids pooling/RAID and uses one XFS filesystem per disk.
- For SSD trim, prefer periodic trim (`fstrim.timer`) rather than mount option `discard` for better steady-state performance in many environments.
