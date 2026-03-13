# Benchmarking

This guide covers fio benchmarking and reporting for `jbofs`.

Before benchmarking, complete [Setup Guide](/home/fozga/r/art/nvme/docs/setup-guide.md). For normal file operations after setup, see [User Guide](/home/fozga/r/art/nvme/docs/user-guide.md).

## Run fio in Dry-Run Mode First

```bash
bash scripts/setup/05_fio_bench.sh --mount-root /data/nvme --dry-run
```

This prints the fio commands without executing them.

## Run Benchmarks

Run the default profile set:

```bash
bash scripts/setup/05_fio_bench.sh --mount-root /data/nvme --profiles seq_write,seq_read,mixed_iter --runtime 60 --apply
```

Run in parallel across all mounts:

```bash
bash scripts/setup/05_fio_bench.sh --mount-root /data/nvme --profiles seq_write,seq_read,mixed_iter --runtime 60 --parallel --apply
```

Outputs are written under:

```text
artifacts/fio/<timestamp>/
```

## Build a Consolidated Report

```bash
python3 scripts/setup/06_report.py --inventory artifacts/inventory.json --verify artifacts/verify.json --output artifacts/report.md
sed -n '1,200p' artifacts/report.md
```

## Suggested Workflow

1. Complete setup and verify mounts.
2. Run `fio` in dry-run mode.
3. Run the benchmark set you care about.
4. Build the consolidated report.

## Notes

- Benchmarks should be run only after the intended mount layout is stable.
- `fio` can generate substantial write load; do not run it on disks with data you care about unless that is intentional.
