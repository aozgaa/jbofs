# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
zig build               # build the binary to zig-out/bin/jbofs
zig build test          # run all tests
zig build run -- --help # run the CLI
zig build run -- cp --help
```

The project targets Zig `0.15.2` and links libc (required for `getline(3)` in `init` and `statvfs(3)` in `cp`).

## Pre-commit Hooks

Commits run `zig fmt`, `zig build`, `zig build test`, and `flowmark --auto` (markdown formatter at 120-char width).
Fix formatting issues before committing.

## Architecture

`jbofs` is a “just a bunch of filesystems” CLI. It manages physical files across multiple independent filesystem roots
and exposes a separate logical namespace of symlinks.

### Core Model

- **Physical roots**: directories like `/srv/jbofs/raw/disk-a`, each with a configured `shortname` (e.g. `disk-0`)
- **Logical root**: a separate directory (e.g. `/srv/jbofs/logical`) containing only symlinks that point into physical
  roots
- Config is JSON (`version: 2`) loaded from `$JBOFS_CONFIG_PATH`, `$XDG_CONFIG_HOME/jbofs/fs_config.json`, or
  `~/.config/jbofs/fs_config.json`

### Source Layout

| Path | Responsibility |
| --- | --- |
| `src/main.zig` | Entrypoint: parses CLI, dispatches to commands |
| `src/cli.zig` | CLI parsing (`zig-clap`), help text, `Action` union |
| `src/config.zig` | Config schema, JSON parsing/validation/stringify, path resolution |
| `src/pathing.zig` | Logical-path normalization, root containment checks |
| `src/commands/*.zig` | Thin wrappers: load config, call lib, print output |
| `src/lib/*.zig` | Operational logic and tests (temp-dir based) |

### Command Flow Pattern

Every command follows the same pattern:
1. `src/commands/<cmd>.zig` defines `Args`, calls `config.loadConfigFile`, then delegates to `src/lib/<cmd>.zig`
2. `src/lib/<cmd>.zig` contains the actual logic and holds the unit tests

### Key Semantics

- `cp`: copies a file into a chosen root, creates a logical symlink.
  Rejects conflicts. Supports `--disk <shortname>` or `--policy first|most-free`.
- `rm`: operates on logical paths only; validates symlink points into a configured root before deleting physical file
  and symlink.
- `sync`: additive—walks all physical roots, creates missing symlinks, skips conflicts.
- `prune`: walks `logical_root`, removes symlinks with missing targets (never deletes physical data).
- Logical paths may be relative (`media/file.txt`) or absolute under `logical_root`; normalized before use.

### Testing

Tests live in the library files (`src/lib/`) and use temporary directories.
When changing CLI semantics, update `src/cli.zig`, `src/commands/`, `src/lib/`, and `docs/`.

## Worktrees

Create worktrees under `~/.config/superpowers/worktrees/jbofs/`.
