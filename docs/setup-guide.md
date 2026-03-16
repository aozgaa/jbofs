# Setup Guide

This guide covers the one-time storage bring-up flow for `jbofs`.

After setup is complete, proceed to:

- [User Guide](/home/fozga/r/art/nvme/docs/user-guide.md) for day-to-day file operations
- [Benchmarking](/home/fozga/r/art/nvme/docs/benchmarking.md) for fio runs and performance reports

## Prerequisites

- The target storage devices are physically visible to Linux.
- The system/root disk is known and will be protected.
- Required packages are installed.

See [Developer Guide](/home/fozga/r/art/nvme/docs/developer-guide.md) for Ubuntu package installation.

## 1. Inventory Disks

Generate the current inventory:

```bash
python3 scripts/setup/01_inventory.py --output-dir artifacts
sed -n '1,200p' artifacts/inventory.md
```

Review:

- which disk is the OS/root disk
- which disks are blank target devices
- whether any disk is unexpectedly classified as `CAUTION` or `BLOCKED`

## 2. Protect the Wrong Disks and Select the Right Ones

Edit:

- `config/protected-devices.yaml`
- `config/selected-devices.yaml`

Example:

```yaml
# config/protected-devices.yaml
protected_devices:
  - nvme-ROOT_DISK_SERIAL
```

```yaml
# config/selected-devices.yaml
selected_devices:
  - nvme-DATA_DISK_A
  - nvme-DATA_DISK_B
  - nvme-DATA_DISK_C
  - nvme-DATA_DISK_D
```

## 3. Generate the Guarded Setup Plan

```bash
python3 scripts/setup/02_plan.py \
  --inventory artifacts/inventory.json \
  --selected config/selected-devices.yaml \
  --protected config/protected-devices.yaml \
  --output-dir artifacts
sed -n '1,200p' artifacts/setup-plan.md
```

Review the plan carefully before applying it.

## 4. Apply the Filesystem Setup

Use the confirmation token emitted by the plan step:

```bash
bash scripts/setup/03_apply.sh --plan artifacts/setup-plan.sh --apply --confirm <token>
```

This formats the selected disks with XFS, mounts them, and appends `fstab` entries.

## 5. Verify Mounts

```bash
python3 scripts/setup/04_verify.py --mount-root /srv/jbofs/raw --probe-write --output-dir artifacts
sed -n '1,200p' artifacts/verify.md
```

Fresh mountpoints may be owned by `root:root`. If the write probe fails with `EACCES`, fix ownership first.

## 6. Create Alias Namespace and Logical Filesystem

```bash
bash scripts/setup/07_aliases.sh
ls -l /srv/jbofs/raw
ls -l /srv/jbofs/aliased
ls -ld /srv/jbofs/logical
```

This creates:

- `/srv/jbofs/raw/<stable-id>` as the canonical filesystem mount roots
- `/srv/jbofs/aliased/disk-N` as convenience symlinks to the raw roots
- `/srv/jbofs/logical` as the singular logical symlink filesystem

At this point setup is complete.

## Next Steps

- Use [User Guide](/home/fozga/r/art/nvme/docs/user-guide.md) for `jbofs cp`, `jbofs rm`, `jbofs sync`, and `jbofs prune`
- Use [Benchmarking](/home/fozga/r/art/nvme/docs/benchmarking.md) for fio and reports
