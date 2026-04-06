# jbofs

`jbofs` is a small CLI for managing files across multiple independent filesystem roots while exposing a separate logical
namespace of symlinks.
`jbofs` is *not* a pooled filesystem; it is an explicit storage workflow built around a symlink farm with independent
roots.

At a glance:

- physical files live under configured roots such as `/srv/jbofs/raw/disk-a`
- each root has a configured shortname such as `disk-0` for `jbofs cp --disk`
- logical symlinks live under a separate tree such as `/srv/jbofs/logical`
- writes are explicit: `jbofs` copies data to one root, then creates one logical symlink
- `jbofs query root-for-shortname <SHORTNAME>` resolves a configured shortname back to its physical root

Current commands:

- `jbofs init`
- `jbofs cp`
- `jbofs rm`
- `jbofs sync`
- `jbofs prune`
- `jbofs doctor`
- `jbofs query root-for-shortname`

For example:
```
$ jbofs init                                                                  # configure roots and logical view, interactively
$ jbofs cp --disk disk-01 movie.mov /srv/jbofs/logical/movies/movie.mov       # explicit placement
$ jbofs cp --policy most-free movie2.mov /srv/jbofs/logical/movies/movie2.mov # policy-driven placement
$ vlc /srv/jbofs/logical/movies/movie.mov                                     # ... use data for something ...
$ jbofs rm /srv/jbofs/logical/movies/movie.mov                                # cleanup symlink and data
```
Due to its simplicity ("just a bunch of filesystems and symlinks"), `jbofs` can also be used with regular binutils:
```
$ rm /srv/jbofs/logical/movies/movie2.mov                                     # orphan data
$ jbofs doctor                                                                # diagnose issues, eg: P0003 -- missing symlink
$ jbofs sync                                                                  # create symlinks to unorphan data
$ rm /mnt/nvme-S5P2NG0R608249J/CLAUDE.md                                      # orphan symlink
$ jbofs doctor                                                                # diagnose again, eg: L0006 -- missing target
$ jbofs prune                                                                 # rm orphaned symlink
```

Read next:

- [docs/comparison.md](./docs/comparison.md) -- start here if you are comparing to `mergerfs`, ZFS/Btrfs, RAID/LVM,
  Stow, ...
- [docs/getting-started.md](./docs/getting-started.md) -- installation and first-run setup
- [docs/design.md](./docs/design.md) -- philosophy, design goals, “architecture”
- [docs/setup-guide.md](./docs/setup-guide.md) -- config location, overrides, examples
- [docs/user-guide.md](./docs/user-guide.md)
- [docs/developer-guide.md](./docs/developer-guide.md)
- [docs/roadmap.md](./docs/roadmap.md)
