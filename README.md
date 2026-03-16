# jbofs

`jbofs` is a small CLI for managing files across multiple independent filesystem roots while exposing a separate logical namespace of symlinks.

At a glance:

- physical files live under configured roots such as `/srv/jbofs/raw/disk-a`
- optional aliases such as `/srv/jbofs/aliases/disk-0` point at those roots
- logical symlinks live under a separate tree such as `/srv/jbofs/logical`
- writes are explicit: `jbofs` copies data to one root, then creates one logical symlink

Current commands:

- `jbofs init`
- `jbofs cp`
- `jbofs rm`
- `jbofs sync`
- `jbofs prune`

`jbofs` is configured with a JSON file. By default it is loaded from:

- `$JBOFS_CONFIG_PATH`, if set
- `$XDG_CONFIG_HOME/jbofs/fs_config.json`, if set
- `~/.config/jbofs/fs_config.json` otherwise

Read next:

- [docs/design.md](./docs/design.md)
- [docs/setup-guide.md](./docs/setup-guide.md)
- [docs/user-guide.md](./docs/user-guide.md)
- [docs/comparison.md](./docs/comparison.md)
- [docs/developer-guide.md](./docs/developer-guide.md)
- [docs/roadmap.md](./docs/roadmap.md)
