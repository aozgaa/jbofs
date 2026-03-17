# User Guide

This guide covers the current `jbofs` command set.

## Command Summary

```text
jbofs init
jbofs cp [-d <NAME>] [-p <POL>] <SOURCE> <LOGICAL_PATH>
jbofs rm <LOGICAL_PATH>
jbofs sync
jbofs prune
jbofs query root-for-shortname <SHORTNAME>
```

Global options:

- `-c, --config <PATH>`: choose a config file
- `-h, --help`: show help

Before using these commands, complete [setup-guide.md](/home/fozga/r/art/jbofs2/docs/setup-guide.md).

## How Paths Work

`LOGICAL_PATH` may be either:

- a relative path like `media/movie.mkv`
- an absolute path under the configured logical root

Both forms refer to the same managed logical entry.

Example config:

- logical root: `/srv/jbofs/logical`

Then these are equivalent:

```bash
jbofs rm media/movie.mkv
jbofs rm /srv/jbofs/logical/media/movie.mkv
```

## `jbofs cp`

Copy a source file into one managed physical root and create the logical symlink.

Examples:

```bash
jbofs cp --disk disk-1 ./movie.mkv media/movie.mkv
jbofs cp --policy first ./movie.mkv media/movie.mkv
jbofs cp --policy most-free ./movie.mkv media/movie.mkv
```

Notes:

- `--disk` and `--policy` are mutually exclusive
- if neither is provided, the config's default placement policy is used
- the source must be a regular file or named pipe
- the destination logical path must not already exist
- parent directories under the selected physical root and logical root are created automatically

The command does not support recursive copies in the current implementation.

## `jbofs rm`

Remove a managed logical entry and its physical target.

Examples:

```bash
jbofs rm media/movie.mkv
jbofs rm /srv/jbofs/logical/media/movie.mkv
```

Behavior:

- the input must resolve to a symlink inside the configured logical root
- the symlink target must be inside one of the configured physical roots
- if the target file already disappeared, `jbofs rm` still removes the logical symlink

The command does not accept physical paths and does not perform recursive deletes in the current implementation.

## `jbofs sync`

Scan all configured physical roots and create any missing logical symlinks.

Example:

```bash
jbofs sync
```

Typical use:

1. A file is created manually under a physical root.
2. `jbofs sync` discovers it.
3. A symlink is created under `logical_root` using the same relative path.

Conflict handling:

- if the logical path does not exist, the symlink is created
- if the logical path already points to the same physical file, it is counted as unchanged
- if the logical path exists but points elsewhere, or is not a symlink, it is counted as a conflict and left untouched

## `jbofs prune`

Remove broken symlinks from the logical tree.

Example:

```bash
jbofs prune
```

Typical use:

1. A physical file is removed manually.
2. Its logical symlink becomes broken.
3. `jbofs prune` deletes the dead symlink.

The command does not delete physical files.

## `jbofs query root-for-shortname`

Look up the configured `root_path` for a physical root shortname.

Example:

```bash
jbofs query root-for-shortname disk-1
```

Behavior:

- prints the configured `root_path` followed by a newline
- returns an error if the shortname is not configured
- does not canonicalize the configured path before printing it

## Config Selection

Config lookup precedence is:

1. `-c /path/to/fs_config.json`
2. `JBOFS_CONFIG_PATH`
3. `$XDG_CONFIG_HOME/jbofs/fs_config.json`
4. `~/.config/jbofs/fs_config.json`

Example:

```bash
jbofs -c ./fs_config.json sync
```

## Current Limitations

The current CLI does not support:

- recursive copy
- recursive remove
- dry-run mode
- scoping `sync` or `prune` to one subtree
- automatic alias management

For planned follow-up work, see [roadmap.md](/home/fozga/r/art/jbofs2/docs/roadmap.md).
