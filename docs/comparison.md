# Comparison

This document compares `jbofs` with adjacent storage and namespace approaches.
The goal is not to argue that `jbofs` is universally better; it is to make the semantics and tradeoffs explicit so you
can choose the right tool for the job.

## Executive Summary

If your priority is:

- explicit file placement on independent filesystems: `jbofs`
- one pooled mount with policy-driven placement: `mergerfs`
- integrated checksums, snapshots, replication, and pooled storage: `ZFS` or `Btrfs`
- classic block-level redundancy/performance: Linux RAID (`md`) or device-mapper RAID/LVM RAID
- package-like symlink farm management: GNU Stow
- parity over otherwise independent disks, usually for mostly-static media: SnapRAID

## Evaluation Dimensions

The main semantic questions are:

1. What is being aggregated?
   A path namespace, a filesystem, or a block device.
2. Where does a file physically live?
   On one real filesystem, striped across multiple devices, or behind a copy-on-write pool.
3. Is placement explicit or policy-driven?
4. Is there integrated redundancy?
5. Is there integrated integrity checking / self-healing?
6. What happens when one disk fails?
7. Can you access the underlying disks directly without the aggregation layer?
8. Are repair actions additive, destructive, or both?

## `jbofs`

### What it is

`jbofs` is a small operational model rather than a new filesystem:

- one filesystem per disk
- direct physical storage under `/srv/jbofs/raw/<stable-id>` or `/srv/jbofs/aliased/disk-N`
- logical symlink namespace under `/srv/jbofs/logical`
- explicit write, remove, sync, and prune commands

### What it does well

- Explicit physical placement
- Very simple failure domains
- Easy direct access to the underlying disk contents
- No FUSE layer
- No hidden balancing or migration
- Easy to reason about for large immutable or append-mostly files

### What it does poorly

- No pooled mount
- No automatic redundancy
- No integrated checksums or self-healing
- No snapshots or replication
- More operational discipline required than a single logical filesystem

### Best fit

- Large file collections where physical placement matters
- Low-magic operational environments
- Cases where you want namespace indirection but not pooled IO semantics

## `mergerfs`

Official docs describe `mergerfs` as a union filesystem that logically combines multiple filesystem paths into a single
mount point, with configurable file creation placement and direct access to underlying filesystems still available.
It explicitly lists file IO passthrough for near-native performance where supported, and also lists non-features such as
RAID-like redundancy, active rebalancing, and splitting files across branches.
Source: <https://trapexit.github.io/mergerfs/latest/>

### Semantic model

- Aggregates paths, not block devices
- Presents one logical mount over multiple underlying filesystems
- New-file placement is policy-driven
- Existing files still physically live on one underlying branch

### Important semantics differences vs `jbofs`

- `mergerfs` gives you a pooled namespace as the primary interface; `jbofs` gives you explicit physical paths plus a separate symlink namespace.
- `mergerfs` must make policy choices at create/rename/link time; `jbofs` makes you choose placement explicitly or via a helper policy at command invocation.
- `mergerfs` can return `EXDEV` for rename/link operations under path-preserving policies when the target path does not exist on the required branch. Source: <https://trapexit.github.io/mergerfs/latest/faq/why_isnt_it_working/>
- `jbofs` has no union-filesystem rename semantics because it is not a union mount.

### FUSE passthrough I/O note

`mergerfs` itself documents file I/O passthrough for near-native performance where supported, so it is fair to say that
`mergerfs` can have a passthrough-I/O mode in practice.
Source: <https://trapexit.github.io/mergerfs/latest/>

At the kernel level, FUSE passthrough allows certain operations to bypass the userspace daemon and execute directly
against a registered backing file.  The kernel docs say passthrough currently covers operations such as `read(2)`,
`write(2)`, `splice(2)`, and `mmap(2)`.
Source: <https://docs.kernel.org/6.17/filesystems/fuse-passthrough.html>

That matters because the usual shorthand “FUSE is always slow because every I/O goes through userspace” is not
universally true anymore, and `mergerfs` is one of the relevant examples.

However, the kernel docs also call out important caveats:

- passthrough setup currently requires `CAP_SYS_ADMIN`
- resource-accounting and visibility are tricky because the kernel can retain backing-file references even after the
  daemon closes its own file descriptor
- this can make open files less visible to normal inspection tools and can bypass ordinary per-process file-descriptor
  accounting
- filesystem stacking/shutdown loops are an explicit concern, and stack-depth limits are part of the design

So even where a FUSE filesystem can take advantage of passthrough I/O, that does not erase the higher-level semantic
differences versus `jbofs`:

- it is still a union/FUSE mount with policy-driven namespace behavior
- rename/create/link semantics are still those of the union layer
- deployment and security constraints may be materially different from a
  plain-filesystem-plus-symlink model

### Where `mergerfs` is better

- You truly want one mountpoint
- Users/applications should not care which disk a file lands on
- You want policy-driven placement with direct underlying-disk escape hatches

### Where `jbofs` is better

- You do not want FUSE/union semantics in the main IO path
- You want explicit placement and explicit repair operations
- You want to avoid policy surprises around rename/link/create behavior
- Even if `mergerfs` passthrough narrows the raw-I/O gap, `jbofs` still has the
  simpler semantic model because there is no union layer in the steady-state
  access path at all

### Best fit

- Home-lab/media/library pools
- “One big tree” UX with otherwise independent filesystems
- Often paired with SnapRAID for parity, because `mergerfs` explicitly does not
  provide RAID-like redundancy

## GNU Stow and Symlink Farms

GNU Stow describes itself as a symlink farm manager that makes distinct sets of software or data appear to be installed
in a single tree.
It is very explicit that it manages symlinks in a target tree and has ownership/conflict semantics around those
symlinks.
Source: <https://www.gnu.org/software/stow/manual/>

### Semantic model

- Namespace-only tool
- No data placement logic
- No filesystem pooling
- No block/device aggregation
- No integrity or redundancy

### Important semantics differences vs `jbofs`

- Stow is optimized for package-tree installation and removal, not per-file runtime placement.
- Stow can fold and unfold directory trees to minimize symlink count; `jbofs` intentionally keeps the logical namespace
  as direct file symlinks created from actual physical content.
- `jbofs-sync`/`jbofs-prune` are file-storage repair tools; Stow is package-tree management.

### Where GNU Stow is better

- Managing install trees, dotfiles, or package-like directory sets
- Ownership and unstow/restow semantics for package deployment

### Where `jbofs` is better

- Ongoing data placement across multiple disks
- Explicit mapping between physical storage and logical access paths
- Repairing logical links after manual storage operations

### Bottom line

`jbofs` is closer to “a purpose-built symlink-based storage workflow.”
Stow is a generic symlink farm manager and a useful conceptual ancestor, but not a replacement.

## Linux RAID (`md`) and dm-raid / LVM RAID

The Linux kernel `md` documentation describes RAID arrays and levels such as `raid0`, `raid1`, `raid5`, and `linear`.
Device-mapper RAID similarly provides RAID targets at the block layer.
Sources:

- <https://www.kernel.org/doc/html/latest/admin-guide/md.html>
- <https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-raid.html>

### Semantic model

- Aggregates block devices
- Filesystem sits on top of the virtual block device
- Files are not “on a disk” in the human sense; the filesystem sees one logical device
- Redundancy/performance depend on RAID level

### Important semantics differences vs `jbofs`

- `md`/dm-raid operate below the filesystem. `jbofs` operates above independent filesystems.
- In RAID0/striped modes, a file’s blocks may live across many disks.
- In mirrored/parity modes, recovery and integrity are tied to the RAID layer, not to explicit per-file placement.
- A single logical mount is natural with RAID; `jbofs` intentionally does not do block aggregation.

### Where RAID is better

- You want one filesystem with block-level redundancy or striping
- You want the system to manage distribution below the filesystem
- You want standard POSIX semantics without union/symlink indirection

### Where `jbofs` is better

- You want independent per-disk filesystems and direct per-disk recovery
- You do not want to stripe blocks across devices
- You want certain classes of operational simplicity over integrated redundancy

### Special note on `linear`

`md`/device-mapper linear concatenation can make multiple devices look like one
longer block device, but this is still block-device aggregation, not explicit
per-file placement.
It gives a bigger volume, not the semantics of “this file is on disk 2.”

## LVM Linear / Striped / Thin / Snapshot

The LVM manual and thin-provisioning docs describe linear, striped, thin, and
snapshot logical volumes built on device mapper.
Sources:

- <https://man7.org/linux/man-pages/man8/lvm.8.html>
- <https://man7.org/linux/man-pages/man7/lvmthin.7.html>
- <https://docs.kernel.org/admin-guide/device-mapper/thin-provisioning.html>

### Semantic model

- Block-device abstraction and management layer
- One or more filesystems typically sit on logical volumes
- Can do linear concatenation, striping, snapshots, and thin provisioning

### Important semantics differences vs `jbofs`

- LVM solves capacity management and snapshot/thin-provisioning problems, not logical path presentation.
- LVM snapshots and thin pools are fundamentally block-layer features.
- `jbofs` gives namespace indirection; LVM gives block-level indirection.

### Where LVM is better

- Flexible block provisioning
- Snapshotting at LV level
- Pooling capacity into logical volumes

### Where `jbofs` is better

- Human-visible explicit file placement
- Direct per-disk namespace reasoning
- Minimal moving parts for “independent disks + logical symlink tree”

## ZFS

OpenZFS documents storage pools (`zpool`), virtual devices (vdevs), end-to-end checksums, scrubs, RAID-Z, snapshots, send/receive, and many advanced features. Sources:

- `zpool` / storage pools: <https://openzfs.github.io/openzfs-docs/man/master/8/zpool.8.html>
- vdev model: <https://openzfs.github.io/openzfs-docs/Basic%20Concepts/VDEVs.html>
- checksums: <https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Checksums.html>
- scrubs: <https://openzfs.github.io/openzfs-docs/man/master/8/zpool-scrub.8.html>
- RAID-Z: <https://openzfs.github.io/openzfs-docs/Basic%20Concepts/RAIDZ.html>

### Semantic model

- Integrated volume manager + filesystem
- Pool space shared across datasets
- Copy-on-write
- Checksummed data and metadata
- Scrubs and automatic repair when redundancy exists
- Snapshots, clones, send/receive replication

### Important semantics differences vs `jbofs`

- ZFS is a complete storage stack, not just a namespace/placement model.
- ZFS dynamically stripes across top-level vdevs.
- Redundancy and integrity are native concerns in ZFS.
- The pool is the primary object; in `jbofs`, independent filesystems are primary.
- ZFS datasets share pool space instead of being isolated by disk unless deliberately designed that way.

### Where ZFS is better

- You want integrated checksums, scrubs, and self-healing
- You want snapshots and replication
- You want pooled storage with strong administration primitives
- You want RAID-Z / mirrors managed within the same system

### Where `jbofs` is better

- You do not want a pooled copy-on-write storage stack
- You want files to remain plainly visible on independent native filesystems
- You want minimal abstraction and explicit placement over advanced storage features

### Important caveat

ZFS can do far more than `jbofs`, but you pay for that with more storage
semantics, more policy surface, and less “this file is obviously on this single
independent disk” transparency.

## Btrfs

Btrfs documentation describes a copy-on-write filesystem with built-in volume
management, checksums, subvolumes, snapshots, send/receive, and RAID profiles.
Sources:

- introduction / feature overview: <https://btrfs.readthedocs.io/en/latest/Introduction.html>
- scrub and repair behavior: <https://btrfs.readthedocs.io/en/latest/Scrub.html>
- send/receive: <https://btrfs.readthedocs.io/en/stable/Send-receive.html>

### Semantic model

- Integrated filesystem + multi-device volume management
- Copy-on-write
- Checksums for data and metadata
- Subvolumes and snapshots
- RAID profiles at filesystem level

### Important semantics differences vs `jbofs`

- Like ZFS, Btrfs is an integrated storage stack rather than an explicit
  multi-filesystem namespace scheme.
- Btrfs scrub can automatically repair when replicated profiles exist.
- Btrfs has subtleties around `NOCOW` / `NODATASUM`: the docs note that `NOCOW`
  implies `NODATASUM`, which weakens checksum-based protection for those files.
  Source: <https://btrfs.readthedocs.io/en/latest/Scrub.html>

### Where Btrfs is better

- Snapshots and subvolumes
- Integrated checksums
- Send/receive replication
- Multi-device operation within one filesystem

### Where `jbofs` is better

- Simpler operational model
- Clear independent-disk boundaries
- Easier direct access to per-disk contents without interpreting subvolume/RAID
  semantics

## SnapRAID

SnapRAID is a parity-and-scrub system designed around content and parity files
rather than a pooled filesystem.
The manual describes parity files, content files, `sync`, `scrub`, and repair
workflows.
Source: <https://www.snapraid.it/manual.html>

### Semantic model

- Independent data disks remain ordinary filesystems
- Separate parity files protect data after `sync`
- Integrity is checked with `scrub`
- Usually paired with a pooling layer for “one mount” UX, but the parity system
  itself is separate

### Important semantics differences vs `jbofs`

- SnapRAID is about parity/integrity over existing files, not namespace management by itself.
- SnapRAID protection is not continuously updated like a copy-on-write filesystem; it depends on explicit `sync` runs.
- `jbofs` currently has no parity or data-integrity layer.

### Where SnapRAID is better

- Mostly-static collections where parity-on-independent-filesystems is attractive
- Cases where you want recovery benefits without adopting ZFS/Btrfs

### Where `jbofs` is better

- Explicit namespace/placement workflow
- Day-to-day logical-path repair via `sync`/`prune`

### Most natural combination

If you wanted parity while preserving independent disks, the closest adjacent architecture would be:

- `jbofs`-like or `mergerfs`-like namespace model
- plus SnapRAID for parity and scrubbing

That is a different operational tradeoff from ZFS/Btrfs because parity is not inline with every write.

## OverlayFS

OverlayFS is a union-like overlay filesystem, but its kernel docs make clear
that it is designed around upper/lower layering and hybrid object identity, not
around pooled storage across data disks.
Source: <https://docs.kernel.org/filesystems/overlayfs.html>

### Why it is usually not the right comparison target

- It is optimized for overlay semantics, especially writable upper over lower layers
- It has whiteouts, copy-up behavior, and hybrid inode/device semantics
- It is not a storage pooling tool in the same sense as mergerfs

### Where it is better

- Container/image layering
- Writable overlays over read-only trees

### Where `jbofs` is better

- Multi-disk explicit file placement
- Stable physical-to-logical file mapping for data storage workflows

## Plain Symlinks, Bind Mounts, and Hand-Rolled Trees

You can build ad hoc symlink or bind-mount trees without `jbofs`.

### What `jbofs` adds beyond “just use symlinks”

- explicit helper commands for copy/remove/repair
- consistent logical vs physical path model
- additive sync and destructive prune split
- tests and docs around edge cases

### Bottom line

If you already want a symlink-based model, `jbofs` is mostly about reducing the
manual footguns of rolling your own.

## Comparison Matrix

| Approach | Aggregates | One mount by default | Redundancy | Checksums / self-heal | Explicit per-file placement | Underlying disks directly readable | Snapshots / replication |
|---|---|---:|---|---|---:|---:|---|
| `jbofs` | Namespace over independent filesystems | No | No | No | Yes | Yes | No |
| `mergerfs` | Paths | Yes | No | No | Policy-driven, not explicit by default | Yes | No |
| GNU Stow | Symlink target tree | Not really a storage pool | No | No | Not a storage placement tool | Yes | No |
| Linux RAID / dm-raid | Block devices | Yes | RAID-level dependent | RAID-level dependent, but not FS-integrated end-to-end checksums | No | Not in a simple per-file sense | No |
| LVM linear / striped / thin | Block devices | Yes | Depends on LV type | No integrated FS-level checksums | No | Not in a simple per-file sense | Snapshots at LV level |
| ZFS | Pool + filesystem | Yes | Yes | Yes | No | Not as plain independent filesystems | Yes |
| Btrfs | Filesystem + volume management | Yes | Yes, profile-dependent | Yes | No | Not as plain independent filesystems | Yes |
| SnapRAID | Parity over independent filesystems | No | Yes, after sync | Yes via scrub/fix workflow, but not inline CoW semantics | N/A | Yes | No |
| OverlayFS | Layered filesystem view | Yes | No | No | No | Not the point | No |

## Which Solution Is "Better"?

The answer depends on which semantics you are optimizing for.

### If you want a single transparent mount

- `mergerfs`, ZFS, Btrfs, RAID/LVM all fit better than `jbofs`

### If you want independent-disk transparency and explicit placement

- `jbofs` is better than pooled/union/block-layer solutions

### If you want integrated integrity, snapshots, and replication

- ZFS or Btrfs are better than `jbofs`

### If you want parity over otherwise ordinary disks

- SnapRAID is better than plain `jbofs`

### If you only want a symlink farm

- GNU Stow or even plain symlinks may be enough, but they do not give you the operational storage workflow that `jbofs` provides

## Practical Recommendation

For this repo’s goals, the decision to use `jbofs` instead of a pooled or CoW filesystem is strongest when all of the following are true:

- you care where files physically land
- you want direct per-disk access with no union layer in the main IO path
- you prefer explicit operational commands over automatic balancing or inline redundancy
- you are willing to trade away pooled-mount convenience and advanced filesystem features

If those stop being true, the first alternative to revisit is usually `mergerfs` for namespace convenience, or ZFS/Btrfs
if integrity, snapshots, and pooled semantics become more important than explicit per-file placement.

## References

- OpenZFS documentation: <https://openzfs.github.io/openzfs-docs/>
- mergerfs docs: <https://trapexit.github.io/mergerfs/latest/>
- GNU Stow manual: <https://www.gnu.org/software/stow/manual/>
- Linux md RAID docs: <https://www.kernel.org/doc/html/latest/admin-guide/md.html>
- Linux dm-raid docs: <https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-raid.html>
- LVM man pages: <https://man7.org/linux/man-pages/man8/lvm.8.html>
- thin provisioning docs: <https://docs.kernel.org/admin-guide/device-mapper/thin-provisioning.html>
- Btrfs docs: <https://btrfs.readthedocs.io/>
- OverlayFS kernel docs: <https://docs.kernel.org/filesystems/overlayfs.html>
- SnapRAID manual: <https://www.snapraid.it/manual.html>
