# jbofs

`jbofs` is a "just bunch of file systems" layout for storing files explicitly on multiple independent roots (~= filesystems) while presenting a separate logical namespace of symlinks.

At a glance:

- physical files live under user-initialized roots.
- friendly aliases exist under `/srv/jbofs/aliased/disk-N`
- logical symlinks live under `/srv/jbofs/logical/...`

The command surface is:

- `jbofs cp`
- `jbofs rm`
- `jbofs sync`
- `jbofs prune`

Read next:

- [docs/design.md](./docs/design.md)
- [docs/comparison.md](./docs/comparison.md)
- [docs/setup-guide.md](./docs/setup-guide.md)
- [docs/user-guide.md](./docs/user-guide.md)
- [docs/benchmarking.md](./docs/benchmarking.md)
- [docs/developer-guide.md](./docs/developer-guide.md)
- [docs/agent-handoff.md](./docs/agent-handoff.md)
