# Getting Started

This guide is the shortest path from cloning the repo to a working `jbofs` setup.
It covers installing the CLI, creating an initial config, and preparing the required directories.

## 1. Install Zig and Build `jbofs`

This repository currently targets Zig `0.15.2`.

From the repo root, build the binary:

```bash
zig build
```

That produces `./zig-out/bin/jbofs`.

To run without installing it anywhere:

```bash
./zig-out/bin/jbofs --help
```

You can also run through Zig directly during development:

```bash
zig build run -- --help
```

To install `jbofs` into a user-local prefix:

```bash
zig build -p ~/.local
export PATH="${HOME}/.local/bin":"${PATH}" # should go in .bashrc
jbofs --help
```

## 2. Prepare Your Filesystem Layout

Before using `jbofs`, create or mount one or more physical roots and choose a logical root directory.

Example layout:

```text
/srv/jbofs/raw/disk-a
/srv/jbofs/raw/disk-b
/srv/jbofs/logical
```

`jbofs sync` and `jbofs cp` create intermediate subdirectories as needed, but the top-level physical and logical roots
should already exist and be writable by the user running the command.

Example:

```bash
sudo mkdir -p /srv/jbofs
sudo chown -R $(id -nu):$(id -nu) /srv/jbofs
mkdir -p /srv/jbofs/raw/disk-a /srv/jbofs/raw/disk-b /srv/jbofs/logical
```

## 3. Create the Config Interactively

Run:

```bash
zig build run -- init
```

The interactive prompts ask for:

- `logical dir`
- one or more physical roots
- each root’s shortname
- default placement policy

By default the config is written to `~/.config/jbofs/fs_config.json`. You can override that with either:

- `zig build run -- -c /path/to/fs_config.json init`
- `JBOFS_CONFIG_PATH=/path/to/fs_config.json zig build run -- init`

Use `-f` to overwrite an existing config:

```bash
zig build run -- init -f
```

## 4. Verify the Generated Config

The config schema and lookup precedence are documented in [setup-guide.md](./setup-guide.md).

Once the config exists, a useful sanity check is:

```bash
jbofs query root-for-shortname disk-0
```

That should print the configured physical `root_path` for the shortname you entered during setup.

## 5. Continue With Normal Usage

Next docs:

- [user-guide.md](./user-guide.md) for day-to-day commands
- [setup-guide.md](./setup-guide.md) for config locations, schema, and validation details
- [design.md](./design.md) for semantics and limitations
- [roadmap.md](./roadmap.md) for planned follow-up work
