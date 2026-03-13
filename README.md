# jbofs

`jbofs` is a "just bunch of file systems" layout for storing files explicitly on multiple independent XFS-backed NVMe disks while presenting a separate logical namespace of symlinks.

At a glance:

- physical files live under `/data/nvme/<stable-id>/...`
- friendly aliases exist under `/data/nvme/0..N`
- logical symlinks live under `/data/logical/...`

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
