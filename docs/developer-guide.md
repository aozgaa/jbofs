# Developer Guide

This guide covers local development for the current Zig implementation.

## Toolchain

The repository currently targets:

- Zig `0.15.2`
- `zig-clap` `0.11.0`
- libc, because `src/commands/init.zig` uses `getline(3)` and `src/lib/cp.zig` uses `statvfs(3)`

## Build and Test

Build:

```bash
zig build
```

Run tests:

```bash
zig build test
```

Run the CLI:

```bash
zig build run -- --help
zig build run -- cp --help
```

## Repository Layout

- [src/main.zig](../src/main.zig): entrypoint and command dispatch
- [src/cli.zig](../src/cli.zig): CLI parsing and help text
- [src/config.zig](../src/config.zig): config schema, validation, loading, path resolution
- [src/pathing.zig](../src/pathing.zig): logical-path normalization and root checks
- [src/commands/](../src/commands): command entrypoints
- [src/lib/](../src/lib): operational logic and tests

## Command Responsibilities

`init`

- prompts for config values
- builds a validated in-memory config
- writes JSON to the resolved config path

`cp`

- resolves the logical destination path
- selects a root by explicit shortname or placement policy
- copies file contents
- creates the logical symlink

`rm`

- only accepts logical paths
- resolves and validates the symlink target
- removes the physical file if present
- removes the logical symlink

`sync`

- walks every configured `root_path`
- recreates missing logical symlinks
- reports created, unchanged, and conflicting entries

`prune`

- walks `logical_root`
- removes symlinks whose targets no longer exist

## Important Current Semantics

- `jbofs query root-for-shortname` resolves configured shortnames to physical `root_path` values
- `sync` and `prune` have no subtree filtering
- `rm` is logical-path only
- `cp` supports regular files and named pipes, not directories
- logical paths are normalized and must stay under `logical_root`

## Testing Style

Most behavior is tested at the library layer with temporary directories.
The tests exercise:

- config validation and config-path precedence
- path normalization and root containment
- explicit-root and policy-based placement
- sync conflict behavior
- prune dead-link behavior
- remove semantics when data is already missing

When changing CLI semantics, update:

- command parsing in [src/cli.zig](../src/cli.zig)
- command wrappers in [src/commands/](../src/commands)
- corresponding library behavior and tests in [src/lib/](../src/lib)
- user-facing docs in [docs/](./)

Open future work is tracked in [roadmap.md](./roadmap.md).
