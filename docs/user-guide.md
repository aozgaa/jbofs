# User Guide

This guide covers normal file operations after `jbofs` setup is complete.

Before using these commands, complete [Setup Guide](/home/fozga/r/art/nvme/docs/setup-guide.md).

## Namespace Model

- Real files live under `/srv/jbofs/raw/<stable-id>/...`
- Friendly physical aliases exist under `/srv/jbofs/aliased/disk-N`
- Logical symlinks live under `/srv/jbofs/logical/...`

In normal use:

- write explicitly to one disk through `jbofs cp`
- remove files with `jbofs rm`
- repair missing logical links with `jbofs sync`
- remove broken logical links with `jbofs prune`

## Copy Files Into jbofs

Copy one file to a specific disk:

```bash
jbofs cp --disk=disk-2 capture.pcap pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Choose a disk by policy:

```bash
jbofs cp --policy=most-free capture.pcap pcaps/symbol=ES/date=2026-03-11/file2.pcap
jbofs cp --policy=random capture.pcap pcaps/symbol=ES/date=2026-03-11/file3.pcap
```

Dry run:

```bash
jbofs cp --disk=disk-1 --dry-run capture.pcap pcaps/test/file1.pcap
```

Recursive copy:

```bash
jbofs cp -r --policy=most-free --batch ./captures pcaps/2026-03-12
jbofs cp -r --policy=random --round-robin ./captures/ pcaps/2026-03-12
```

Rsync-style source semantics apply:

- `srcdir/` copies contents
- `srcdir` copies the directory itself

## Remove Files

Remove both the logical symlink and the physical file:

```bash
jbofs rm /srv/jbofs/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Remove only the logical symlink:

```bash
jbofs rm --ensure-logical --rm-link /srv/jbofs/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Remove by physical path:

```bash
jbofs rm --ensure-physical --rm-both /srv/jbofs/aliased/disk-0/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Recursive remove:

```bash
jbofs rm -r --ensure-logical /srv/jbofs/logical/pcaps/2026-03-11
```

Dry-run first when in doubt.

## Sync Missing Logical Links

If you manually add files under `/srv/jbofs/raw/...`, rebuild missing logical symlinks with:

```bash
jbofs sync
```

Scope to one disk:

```bash
jbofs sync --disk=disk-1
```

Scope to one subtree:

```bash
jbofs sync --disk-path /srv/jbofs/aliased/disk-0/pcaps --logical-prefix pcaps/2026-03-12
```

Dry-run:

```bash
jbofs sync --dry-run
```

## Prune Broken Logical Links

If physical files were removed manually, prune stale logical symlinks with:

```bash
jbofs prune
```

Scope to one subtree:

```bash
jbofs prune --logical-prefix pcaps/2026-03-12
```

Dry-run:

```bash
jbofs prune --dry-run
```
