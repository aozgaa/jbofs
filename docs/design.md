# Design

`jbofs` is a "just bunch of file systems" workflow, not a new filesystem.
It manages a set of independent physical roots plus a separate logical tree of symlinks.

## Core Model

Each configured root has two identities:

- `root_path`: the real filesystem location where data is stored
- `shortname`: the CLI name used with `jbofs cp --disk`

The config also defines one `logical_root`, which contains symlinks to physical files.

Example:

```text
physical file: /srv/jbofs/raw/disk-a/media/movie.mkv
logical link:  /srv/jbofs/logical/media/movie.mkv
```

## Write Path

`jbofs cp`:

1. Normalizes the requested logical path relative to `logical_root`
2. Selects one configured root
3. Copies the source file into that root
4. Creates a symlink at `logical_root/<logical-path>` pointing at the physical file

Destination conflicts are rejected. `jbofs` does not overwrite an existing logical path.

## Placement Model

Placement is intentionally simple.

- `--disk <NAME>` writes to a specific configured root by shortname
- `--policy first` uses the first configured root
- `--policy most-free` chooses the root with the most available space
- if neither flag is provided, the config's `placement.default_policy` is used

There is no background rebalance, migration, or pooled allocator.

## Remove Model

`jbofs rm` operates on a logical path only.

- it resolves the path under `logical_root`
- it requires that the logical entry is a symlink
- it requires that the symlink target is inside one of the configured `root_path` values
- it deletes the physical file target if present
- it always deletes the logical symlink

If the physical file is already missing, removal still succeeds and reports that the data was already gone internally.

## Repair Model

Repair is split into two commands:

- `jbofs sync` scans every configured physical root and creates missing logical symlinks
- `jbofs prune` scans `logical_root` and removes broken symlinks

`jbofs sync` is additive. It does not overwrite conflicts. If a logical path already exists and points somewhere else, it is counted as a conflict and left unchanged.

`jbofs prune` is destructive only with respect to dead symlinks. It never deletes physical data.

## Path Semantics

Logical paths may be passed either as:

- a relative path such as `media/movie.mkv`
- an absolute path under `logical_root`

Logical paths must not contain empty components, `.` or `..`.

Physical roots must be absolute paths in the config.

The current commands consult `root_path` and `shortname`. `jbofs query root-for-shortname` is the lookup helper for mapping a configured shortname back to its physical root.

## Non-Goals

The current implementation does not provide:

- a pooled mount
- recursive copy or recursive remove
- dry-run support
- redundancy, checksums, snapshots, or self-healing

The design goal is a narrow, explicit storage-management tool with simple failure domains.

For concrete setup and usage examples, see [setup-guide.md](./setup-guide.md) and [user-guide.md](./user-guide.md).
