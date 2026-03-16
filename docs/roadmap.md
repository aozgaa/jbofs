# Roadmap

This document tracks likely follow-up work for `jbofs`. These are ideas and open tasks, not guarantees.

## Configuration and UX

- [ ] `init` creates all required directories, including the logical root, with a clear privilege model
- [ ] add query helpers for config lookups such as shortname-to-root mapping
- [ ] remove on-filesystem aliases if better lookup helpers make them unnecessary

## Copy Semantics

- [ ] define careful behavior when `jbofs cp` is given a source that is already managed by `jbofs`
- [ ] define careful behavior for multiple logical symlinks pointing at one physical file
- [ ] add recursive `cp`

## Test Coverage

- [ ] expand `cp` testing for more source file kinds in a controlled environment
- [ ] test block devices
- [ ] test character devices
- [ ] test sockets
- [ ] test symlink sources and decide whether to follow them
- [ ] test directories
- [x] test regular files
- [ ] test FIFOs

## Future Evaluation

- [ ] add benchmarking comparisons once the command surface is more stable
