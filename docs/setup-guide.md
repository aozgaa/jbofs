# Setup Guide

This guide covers setting up the current `jbofs` CLI. In this repository, setup means creating directories and writing a valid config file. Disk provisioning, formatting, and mounting are outside the scope of the tool.

## Prerequisites

Before using `jbofs`, prepare the filesystem layout yourself:

- create or mount one or more physical roots
- choose a logical root directory

Example layout:

```text
/srv/jbofs/raw/disk-a
/srv/jbofs/raw/disk-b
/srv/jbofs/logical
```

## 1. Install Zig and Build `jbofs`

From the repo root:

```bash
zig build
```

To run without installing:

```bash
zig build run -- --help
```

## 2. Create the Config Interactively

Run:

```bash
zig build run -- init
```

The interactive prompts ask for:

- `logical dir`
- one or more physical roots
- each root's shortname
- default placement policy

By default the config is written to `~/.config/jbofs/fs_config.json`. You can override that with either:

- `zig build run -- -c /path/to/fs_config.json init`
- `JBOFS_CONFIG_PATH=/path/to/fs_config.json zig build run -- init`

Use `-f` to overwrite an existing config:

```bash
zig build run -- init -f
```

## 3. Verify the Generated Config

The config schema is:

```json
{
  "version": 2,
  "logical_root": "/srv/jbofs/logical",
  "roots": [
    {
      "root_path": "/srv/jbofs/raw/disk-a",
      "shortname": "disk-0"
    },
    {
      "root_path": "/srv/jbofs/raw/disk-b",
      "shortname": "disk-1"
    }
  ],
  "placement": {
    "default_policy": "most-free"
  }
}
```

Current validation rules:

- `version` must be `2`
- `logical_root` must be absolute
- every `root_path` must be absolute
- at least one root is required
- `shortname` values must be non-empty and unique
- `root_path` values must be unique

If you have an older config that still contains `alias` fields, regenerate it or edit those fields out before using this version.

`jbofs query root-for-shortname <SHORTNAME>` resolves a configured shortname to the matching `root_path` when you need the physical location for a disk.

## 4. Create the Logical Root if Needed

`jbofs sync` and `jbofs cp` create intermediate subdirectories as needed, but the top-level physical and logical roots should already exist and be writable by the user running the command.

Example:

```bash
sudo mkdir -p /srv/jbofs
sudo chown -R $(id -nu):$(id -nu) /srv/jbofs
mkdir -p /srv/jbofs/raw/disk-a /srv/jbofs/raw/disk-b /srv/jbofs/logical
```

## 5. Continue With Normal Usage

Once the config exists, use:

- [user-guide.md](./user-guide.md) for day-to-day commands
- [design.md](./design.md) for semantics and limitations
- [roadmap.md](./roadmap.md) for planned follow-up work
