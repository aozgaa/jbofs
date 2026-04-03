# Roadmap

This document tracks likely follow-up work for `jbofs`. These are ideas and open tasks, not guarantees.

## Configuration and UX

- [x] add query helpers for config lookups such as shortname-to-root mapping
- [x] remove on-filesystem aliases if better lookup helpers make them unnecessary
- [x] `init` loop for roots: physical root paths should be checked for existence and the “creation” should fail/re-ask
  to create another entry if they don’t exist
- [x] `init` creates all required directories, including the logical root, with a clear privilege model: `init` runs as
  the invoking user (so config is written to the correct user path); directories that fail with `PermissionDenied`
  should be retried via `sudo install -d -o <user> -g <group> -m 755 <path>` so the directory is created and immediately
  owned by the invoking user, not root; uid/gid obtained via syscalls; a setuid helper binary was considered and
  rejected (requires elevated installation, non-trivial attack surface, overkill for a single mkdir+chown)
- [ ] `init` should support path completions/tabbing
- [ ] there should be some kind of programmtic driven init instead of interactive (eg: cli options) maybe the config
  format is simple enough this isn’t necessary?

## Copy Semantics

- [ ] define expected invariants and add a checker for them -- see docs/specs/doctor.md.
- [ ] jbofs cp rejects files already managed by jbofs (real file or after symlink resolution)
- [ ] add recursive `cp`

## Test Coverage

- [x] expand `cp` testing for more source file kinds in a controlled environment
- [ ] test block devices (skipped: requires root or loop device setup -- emulate with cgroups/container?)
- [x] test character devices
- [x] test sockets
- [x] test symlink sources and decide whether to follow them
- [x] test directories
- [x] test regular files
- [x] test FIFOs
- [ ] add privileged `doctor` inode-kind coverage for block/character devices in an admin-controlled container, jail,
  cgroup, or equivalent environment

## Future Evaluation

- [ ] add benchmarking comparisons once the command surface is more stable
