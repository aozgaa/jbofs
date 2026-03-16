# Design

`jbofs` is a "just bunch of file systems" layout for storing files explicitly on multiple independent XFS-backed filesystems while presenting a separate logical namespace of symlinks.

## Core Model

- Raw filesystems live under `/srv/jbofs/raw/<stable-id>/...`
- Aliased filesystems live under `/srv/jbofs/aliased/disk-N/...`
- Logical symlinks live under `/srv/jbofs/logical/...`

This means physical placement is explicit, while user-facing paths can stay stable and category-oriented.

## Why This Design

`jbofs` deliberately avoids:

- RAID/LVM striping
- pooled/FUSE filesystems such as mergerfs
- automatic balancing or data migration

Reasons:

- each disk stays independently mountable and recoverable
- physical placement is predictable
- failure domains stay simple
- there is no hidden allocation policy to debug later

## Physical vs Logical Paths

Physical path:

```text
/srv/jbofs/aliased/disk-0/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

Logical path:

```text
/srv/jbofs/logical/pcaps/symbol=ES/date=2026-03-11/file1.pcap
```

The logical path is a symlink pointing at the physical file.

## Raw and Aliased Filesystems

Raw mount roots under `/srv/jbofs/raw/<stable-id>` are the canonical identity for each filesystem. Aliased roots under `/srv/jbofs/aliased/disk-N` are convenience symlinks created after setup.

This split exists because:

- stable IDs survive device enumeration changes better than transient block-device names
- `disk-N` aliases are much easier to type during day-to-day use

## Explicit Placement

`jbofs cp` requires either:

- `--disk=disk-N`
- or a placement policy such as `--policy=most-free` or `--policy=random`

This keeps disk choice explicit at the command boundary. The system does not silently rebalance or choose hidden placement rules.

## Sync and Prune Separation

Repair operations are split on purpose:

- `jbofs sync` is additive only and creates missing logical symlinks
- `jbofs prune` removes broken logical symlinks only

This avoids a single “fix everything” command that can both create and delete state.

## Remove Semantics

`jbofs rm` can operate from either side:

- logical path input
- physical path input

When removing from a physical path, all matching logical symlinks are removed. This avoids ambiguous partial cleanup when multiple logical entries point to one physical file.

## Recursive Copy Semantics

Recursive `jbofs cp` follows rsync-style source semantics:

- `srcdir/` copies contents
- `srcdir` copies the directory itself

Recursive copy also requires exactly one grouping mode:

- `--round-robin`
- `--batch`

This makes recursive placement predictable instead of implicit.

## Non-Goals

- no transparent pooled mount like `/srv/jbofs/data`
- no automatic rebalance
- no data redundancy
- no background healing

`jbofs` is intentionally simple: explicit physical writes, explicit logical namespace, explicit repair commands.
