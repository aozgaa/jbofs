# jbofs

`jbofs` is a "just bunch of file systems" layout for storing files explicitly on multiple independent XFS-backed filesystems while presenting a separate logical namespace of symlinks.

At a glance:

- physical files live under `/srv/jbofs/raw/<stable-id>/...`
- friendly aliases exist under `/srv/jbofs/aliased/disk-N`
- logical symlinks live under `/srv/jbofs/logical/...`

The command surface is:

- `scripts/jbofs-cp.sh`
- `scripts/jbofs-rm.sh`
- `scripts/jbofs-sync.sh`
- `scripts/jbofs-prune.sh`

Read next:

- [docs/design.md](/home/fozga/r/art/nvme/docs/design.md)
- [docs/comparison.md](/home/fozga/r/art/nvme/docs/comparison.md)
- [docs/setup-guide.md](/home/fozga/r/art/nvme/docs/setup-guide.md)
- [docs/user-guide.md](/home/fozga/r/art/nvme/docs/user-guide.md)
- [docs/benchmarking.md](/home/fozga/r/art/nvme/docs/benchmarking.md)
- [docs/developer-guide.md](/home/fozga/r/art/nvme/docs/developer-guide.md)
- [docs/agent-handoff.md](/home/fozga/r/art/nvme/docs/agent-handoff.md)
