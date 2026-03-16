# JBOFS Specification

## Goal

`jbofs` should return to a very small core:

1. Persist a mapping from logical namespace to a set of backing filesystems.
2. Copy file data into one selected backing filesystem.
3. Maintain logical symlinks that point at the real file locations.
4. Provide a small set of repair and cleanup commands.

This document is a cleanroom-oriented proposal for that smaller system. It also records where the Zig port drifted away from the core semantics present around commit `8ab6b28a96b206a`.

## What Changed Since `8ab6b28a96b206a`

### Summary

The original repository already had two layers:

- the core four verbs: `cp`, `rm`, `sync`, `prune`
- a larger setup/inventory/provisioning workflow for preparing disks

The Zig port preserved most of the complexity of the shell scripts, added a new CLI parser dependency, and surfaced some setup semantics directly in the compiled CLI. That moved the project away from "just bunch of file systems" and toward a larger storage-management tool.

### Concrete semantic drift

1. The compiled CLI now advertises a `setup` command tree.
   - In [src/main.zig](/home/fozga/r/art/jbofs/src/main.zig), top-level help includes `setup`.
   - This is outside the four core verbs and makes the product feel larger than it needs to be.

2. Runtime configuration is still environment-driven and implicit.
   - [src/core/env.zig](/home/fozga/r/art/jbofs/src/core/env.zig) reads `RAW_ROOT`, `ALIASED_ROOT`, and `LOGICAL_ROOT`.
   - This keeps behavior scattered across shell state instead of one persistent config file.

3. `cp` still carries recursive/group-placement behavior.
   - [src/cli/cp.zig](/home/fozga/r/art/jbofs/src/cli/cp.zig) includes `--recursive`, `--round-robin`, `--batch`, `--disk`, `--policy`, `--force`, and `--dry-run`.
   - For the simplified model, recursive copy is unnecessary and placement should be easy to reason about.

4. `rm` still supports multiple path-interpretation and deletion modes.
   - [src/cli/rm.zig](/home/fozga/r/art/jbofs/src/cli/rm.zig) includes `--ensure-logical`, `--ensure-physical`, `--ensure-data`, `--rm-link`, `--rm-data`, `--rm-both`, and `--recursive`.
   - This broadens `rm` from "remove one logical file and its data" into a more general garbage-collection tool.

5. `sync` still exposes scan-source complexity.
   - [src/cli/sync.zig](/home/fozga/r/art/jbofs/src/cli/sync.zig) includes `--disk`, `--disk-path`, and `--logical-prefix`.
   - The disk-path/stable-root logic is implementation-heavy for a command whose core job is just "recreate logical symlinks for data already on disk".

6. `prune` is already close to the desired shape, but still inherits optional subtree filtering.
   - [src/cli/prune.zig](/home/fozga/r/art/jbofs/src/cli/prune.zig) includes `--logical-prefix`.
   - That is acceptable if kept as a narrow convenience, but not necessary for the minimal version.

7. The repository still carries substantial setup machinery and tests for it.
   - `scripts/setup/*`
   - [tests/test_plan_guardrails.py](/home/fozga/r/art/jbofs/tests/test_plan_guardrails.py)
   - [tests/test_inventory_classification.py](/home/fozga/r/art/jbofs/tests/test_inventory_classification.py)
   - These are valid tools in some environments, but they are orthogonal to the core `jbofs` data model.

8. The port duplicated legacy semantics rather than using the rewrite as a simplification point.
   - `clap` parsing, mode flags, and root-detection logic make the implementation longer without materially improving the core idea.

### Recommended direction

Keep the old setup scripts outside the core specification. They may remain in the repository as separate operator utilities, but they should not define the core `jbofs` contract and should not shape the main CLI.

The core CLI should be:

- `jbofs init`
- `jbofs cp`
- `jbofs rm`
- `jbofs prune`
- `jbofs sync`

Nothing else is required by the base product.

## Data Model

### Concepts

- `physical filesystem`: one mounted backing filesystem
- `physical file`: the real bytes stored on one backing filesystem
- `logical path`: the user-facing path under a logical root
- `logical symlink`: a symlink under the logical root pointing at the physical file

### Invariants

1. Every managed logical file is represented by exactly one symlink under the logical root.
2. Every managed symlink points at exactly one physical file under one configured filesystem root.
3. `cp` creates a physical file first, then creates the logical symlink.
4. `rm` removes both the symlink and the physical file for one logical path.
5. `prune` removes logical symlinks whose targets no longer exist.
6. `sync` recreates missing logical symlinks for physical files already present on configured filesystems.

### Non-goals

- No recursive `cp`
- No directory trees as first-class managed objects
- No setup/provisioning/inventory workflow in the core CLI
- No hidden metadata database
- No special alias-management command in the core CLI
- No requirement to manage files that were not laid out according to the configured roots

## Configuration

### Recommendation

Use a single JSON file by default:

- (if env var defined) `$JBOFS_CONFIG_PATH`
- (if env var defined) `$XDG_CONFIG_HOME/jbofs/fs_config.json`
- (fallback) `$HOME/.config/jbofs/fs_config.json`

Allow override with:

- `jbofs --config /path/to/fs_config.json ...`

JSON is easy to parse in Zig, explicit, and avoids ambient shell state.

### Proposed schema

```json
{
  "version": 1,
  "logical_root": "/srv/jbofs/logical",
  "filesystems": [
    {
      "root": "/srv/jbofs/raw/nvme-S5P2NG0R607870N",
      "alias": "/srv/jbofs/aliases/disk-0",
      "shortname": "disk-0"
    },
    {
      "root": "/srv/jbofs/raw/nvme-S5P2NG0R608243B",
      "alias": "/srv/jbofs/aliases/disk-1",
      "shortname": "disk-1"
    }
  ],
  "placement": {
    "default_policy": "most-free"
  }
}
```

### Schema rules

1. `version` is required and currently must equal `1`.
2. `logical_root` is required and absolute.
3. `filesystems` is required and non-empty.
4. Each filesystem entry has:
   - `name`: stable CLI name such as `disk-0`
   - `root`: absolute path to the mounted filesystem root
5. Filesystem names must be unique.
6. Filesystem roots must be unique.
7. `placement.default_policy` is optional; default is `most-free`.

### Why not `.env`

A `.env` file is workable but weaker:

- no natural structure for multiple filesystem entries
- easier to drift into partially defined state
- harder to validate cleanly

If an env-compatible format is still desired, it should be generated from the JSON file, not be the source of truth.

## Path Mapping

For a logical relative path `photos/2024/img001.jpg`:

- logical symlink path:
  - `<logical_root>/photos/2024/img001.jpg`
- physical file path on `disk-1`:
  - `<filesystems["disk-1"].root>/photos/2024/img001.jpg`

This simple "same relative path under both roots" mapping should be the only mapping rule in the cleanroom implementation.

No additional metadata is required if this invariant holds.

## CLI Surface

## Global form

```text
jbofs [--config PATH] <subcommand> [args...]
```

`--config` is global and optional for every command.

## `jbofs init`

### Purpose

Create a new config file with a minimal valid schema.

### Form

```text
jbofs init [--config PATH] [--force]
```

### Behavior

2. If the target config  exists and `--force` is not given, fail.
3. If it exists and `--force` is given, continue.
4. Parent directories for the config file should be created as needed.
5. ask the user interactively how they want jbofs setup:
  1. logical dir (default /srv/jbofs/logical)
  2. fs alias dir (default /srv/jbofs/aliases)
  3. add a filesystem? while true (at least once, else print error and retry):
    1. ask for mount point
    2. ask for alias (default /src/jbofs/aliases/disk-<N>)
    3. ask for shortname (default disk-<N>)
  4. ask for placement policy (`most-free|random`) (default `most-free`)
6. serialize completed config to disk. (this step alone should be unit testable)

### Initial contents

The inital file should be well-formed, something like

```json
{
  "version": 1,
  "logical_root": "/srv/jbofs/logical",
  "filesystems": [
   { "root": "...", "alias": "...", "shortname": "..." }
  ],
  "placement": {
    "default_policy": "most-free"
  }
}
```



## `jbofs cp`

### Purpose

Copy one regular file into one selected filesystem and create its logical symlink.

### Form

```text
jbofs cp [--disk SHORTNAME | --policy POLICY] SOURCE LOGICAL_PATH
```

### Supported options

- `--disk SHORTNAME` (optional)
  - choose an explicit filesystem by configured `shortname`
- `--policy POLICY` (optional, default value based on config)
  - choose a filesystem by policy
  - initially support:
    - `most-free`
    - `first`

### Deliberate simplifications

1. `SOURCE` must be one regular file.
2. No recursive copy.
3. No `--round-robin`.
4. No `--batch`.
5. No `--dry-run` in the minimal implementation.
6. No `--force` in the minimal implementation.

If later needed, `--force` can be reintroduced, but it should not shape the first clean rewrite.
Instead, cp should overwrite contents by default.

### Arguments

- `SOURCE`
  - path to an existing regular file
- `LOGICAL_PATH`
  - logical path, relative to `logical_root`
  - must not be absolute
  - must not contain `..` path traversal

### Behavior

1. Load config.
2. Validate `SOURCE` is filetype we can "read()" from (eg; regular file, pipefd)
3. Resolve the target filesystem.
4. Compute:
   - physical destination: `<filesystem.root>/<LOGICAL_PATH>`
   - logical destination: `<logical_root>/<LOGICAL_PATH>`
5. Refuse to proceed if either destination already exists.
6. Create parent directories as needed.
7. Copy bytes from `SOURCE` to the physical destination until EOF.
8. Create a symlink at the logical destination pointing to the physical destination.
9. Exit success only if both the file and symlink exist.

### Selection policy

- `first`
  - choose the first filesystem entry in config order
- `most-free`
  - stat each filesystem root and choose the one with the most available space

If neither `--disk` nor `--policy` is provided, use `placement.default_policy` from config.

## `jbofs rm`

### Purpose

Remove one managed file by logical path.

### Form

```text
jbofs rm [LOGICAL_PATH]
```

### Deliberate simplifications

1. Only accepts a logical path.
2. No recursive mode.
3. No `--ensure-*` flags.
4. No `--rm-link`, `--rm-data`, or other partial-delete modes.

### Arguments

- `LOGICAL_PATH`
  - relative to `logical_root`
  - may also be accepted as an absolute path under `logical_root`, but relative is preferred

### Behavior

(if require/expectations fail, log error and exit without modification).

1. Normalize `LOGICAL_PATH` to a path under `logical_root`.
2. Require that the resolved logical path is a symlink.
3. Read the symlink target.
4. Require that the symlink target is under one of the configured filesystem roots.
5. Delete the physical file.
6. Delete the logical symlink.
7. Succeed if both are gone.

### Missing-target behavior

If the symlink exists but its physical target is already missing:

1. Remove the symlink.
2. Return success with a note that the data was already absent.

This keeps `rm` practical in partially damaged states.

## `jbofs prune`

### Purpose

Remove dead symlinks under the logical root.

### Form

```text
jbofs prune
```

### Arguments

None.

### Minimal behavior

1. Walk the logical root recursively.
2. For each symlink:
   - if the target exists, leave it alone
   - if the target does not exist, remove the symlink
3. Print or count what was pruned.

### Deliberate Simplifications

`--prefix RELPATH` may be added later, but it is not part of the minimal core contract.

## `jbofs sync`

### Purpose

Recreate missing logical symlinks for physical files already present on configured filesystems.

### Form

```text
jbofs sync
```

### Arguments

None.

### Behavior

1. For each configured filesystem root:
   - walk regular files recursively
2. Derive the relative path from that filesystem root.
3. Compute the expected logical symlink path as:
   - `<logical_root>/<relative_path>`
4. If the logical path is absent:
   - create parent directories
   - create the symlink
5. If the logical path already exists and points to the same physical file:
   - do nothing
6. If the logical path exists but points elsewhere or is a non-symlink:
   - report conflict
   - leave it unchanged

### Deliberate simplifications

1. No `--physical--prefix` or `--logical-prefix` options. Complicated and likely unnecessary. eg:
```
- `PHYSICAL_PREFIX`
  - optional path to some physical subtree such as `/srv/jbofs/disk-1/photos/2024`
  - if omitted, scan all configured filesystems
```
1. No `--disk-path`.
2. No stable-root mapping logic.
3. No dependency on alias directories.
4. Configured filesystem roots are the only scan roots.

## Operator Examples

These examples should appear in user-facing docs because `jbofs` is intentionally close to shell tools.

### Equivalent manual copy

If config maps `disk-0` to `/srv/jbofs/raw/disk-a` and `logical_root` to `/srv/jbofs/logical`, then:

```bash
mkdir -p /srv/jbofs/raw/disk-a/media
cp /tmp/movie.mkv /srv/jbofs/raw/disk-a/media/movie.mkv
mkdir -p /srv/jbofs/logical/media
ln -s /srv/jbofs/raw/disk-a/media/movie.mkv /srv/jbofs/logical/media/movie.mkv
```

That is semantically what `jbofs cp --disk disk-0 /tmp/movie.mkv media/movie.mkv` should do.

### Manual removal

```bash
rm -f /srv/jbofs/logical/media/movie.mkv
rm -f /srv/jbofs/raw/disk-a/media/movie.mkv
```

That is semantically what `jbofs rm media/movie.mkv` should do.

### Manual prune

```bash
find /srv/jbofs/logical -type l ! -exec test -e {} \\; -print -delete
```

That is semantically what `jbofs prune` should do.

### Manual sync

```bash
find /srv/jbofs/raw/disk-a -type f
```

For each file found, recreate the symlink under the logical root using the same relative path.

## Cleanroom Implementation Notes

## Suggested module split

- `src/config.zig`
  - parse and validate `fs_config.json`
- `src/pathing.zig`
  - path normalization
  - relative path validation
  - root-membership checks
- `src/commands/init.zig`
- `src/commands/cp.zig`
- `src/commands/rm.zig`
- `src/commands/prune.zig`
- `src/commands/sync.zig`
- `src/lib/cp.zig`
- `src/lib/rm.zig`
- `src/lib/prune.zig`
- `src/lib/sync.zig`
- `src/main.zig`

## Important validation rules

1. treat paths are ordinary linux commands do (ie: accept realtive paths or aboslute paths).
2. Canonicalize paths to find roots/prefix/suffixes.
3. Reject symlink targets outside configured filesystem roots.
4. Only manage regular files and symlinks.

## Error model

Each command should fail with a short, precise error message and a non-zero exit code when:

- config is missing or invalid
- no filesystems are configured
- selected filesystem name is unknown
- policy selection cannot choose a filesystem
- source path is missing or not a regular file
- logical path is invalid
- destination already exists
- existing logical entry conflicts with expected symlink

## Testing Scope For The Rewrite

The minimal test suite should cover:

1. config parsing and validation
2. `init` create and force-overwrite behavior
3. `cp` with explicit disk
4. `cp` with policy-based selection
5. `cp` rejection of invalid logical paths
6. `rm` of a healthy managed file
7. `rm` when the symlink target is already missing
8. `prune` removing dead symlinks only
9. `sync` creating missing links
10. `sync` leaving correct links untouched
11. `sync` reporting conflicts without overwriting

The setup/inventory tests should not define success for the core rewrite.

## Migration Guidance

1. Keep old setup scripts as separate utilities if still useful operationally.
2. Remove `setup` from the compiled `jbofs` CLI.
3. Replace environment-root loading with config-file loading.
4. Rewrite the four verbs against the simple config-backed path mapping.
5. Add `init` as the only setup-like core command.

## Final Recommendation

The clean rewrite should optimize for obviousness:

- one config file
- one logical root
- a list of filesystem roots
- one relative-path mapping rule
- four maintenance verbs plus `init`

Anything beyond that should be justified as a separate layer, not folded into the base `jbofs` contract.
