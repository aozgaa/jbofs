# Setup Guide

This guide is the reference for `jbofs` configuration details.
If you want the shortest path to a working install, start with [getting-started.md](./getting-started.md).

## Config Lookup

When loading the config, `jbofs` checks these locations in order:

- `$JBOFS_CONFIG_PATH`, if set
- `$XDG_CONFIG_HOME/jbofs/fs_config.json`, if set
- `~/.config/jbofs/fs_config.json` otherwise

You can also select a config explicitly with:

```bash
jbofs -c /path/to/fs_config.json sync
```

## Config Schema

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

If you have an older config that still contains `alias` fields, regenerate it or edit those fields out before using this
version.

`jbofs query root-for-shortname <SHORTNAME>` resolves a configured shortname to the matching `root_path` when you need
the physical location for a disk.

## Filesystem Layout Notes

`jbofs sync` and `jbofs cp` create intermediate subdirectories as needed, but the top-level physical and logical roots
should already exist and be writable by the user running the command.

Example:

```bash
sudo mkdir -p /srv/jbofs
sudo chown -R $(id -nu):$(id -nu) /srv/jbofs
mkdir -p /srv/jbofs/raw/disk-a /srv/jbofs/raw/disk-b /srv/jbofs/logical
```

## Related Docs

- [getting-started.md](./getting-started.md) for installation and first-run setup
- [user-guide.md](./user-guide.md) for day-to-day commands
- [design.md](./design.md) for semantics and limitations
- [roadmap.md](./roadmap.md) for planned follow-up work
