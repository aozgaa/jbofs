# `jbofs doctor`

Add a new `jbofs doctor` subcommand.

The command takes no additional arguments and checks the integrity invariants followed by `jbofs`. Some of these
invariants are stricter than what current commands fully enforce today; that is intentional.
`doctor` is the executable definition of the expected on-disk semantics.

## Checker Architecture

The implementation should use three checking passes with a shared diagnostic collector:

1. config pass
2. logical-tree pass
3. physical-root pass

The config pass validates configured values, attempts canonicalization, and checks configured-path relationships.
The logical-tree pass walks `logical_root`, validates logical entries, and builds the logical-to-physical mapping view.
The physical-root pass walks each configured root, validates physical entries, and cross-checks them against the logical
mapping view.

The checker should collect all diagnostics across passes, sort them deterministically before printing, and exit based on
whether any problems were found.

## Exit Status

- Exit `0` if no problems are found.
- Exit `1` if any invariant violation is found.

## Reporting

`doctor` should print one diagnostic per problem it finds.

Problems include both:

- invariant violations
- I/O / traversal errors encountered while checking the filesystem

Each diagnostic must include a stable error code.
Code format:

- `CNNNN` for config/layout problems
- `LNNNN` for logical-tree problems
- `PNNNN` for physical-root problems

The numeric portion must be zero-padded to 4 digits.

The output should be human-readable and make it clear what failed and where.
Diagnostics should include the relevant concrete values, such as:

- the offending logical path
- the offending physical path
- the stored symlink target
- the configured roots involved in a layout violation

Do not emit codes alone; each line should pair the code with a readable explanation.
An I/O error should be logged and should count as a problem in the final result.

Where useful, diagnostics should include the likely remediation command or note.
In particular:

- for a dead logical symlink target, mention that `jbofs prune` can remove the dead symlink
- for a physical file with no logical symlink, mention running `jbofs sync`
- for duplicate logical mappings to one physical file, mention that shared ownership management is not yet implemented

Examples of I/O / traversal failures that should be reported include:

- a configured root does not exist
- `logical_root` does not exist
- a configured path cannot be opened
- reading a symlink target fails
- statting or traversing an entry fails

The intent is that `doctor` remains useful as a diagnostic tool even when the filesystem is already damaged or partially
missing.

Suggested code assignment model:

- assign one code per distinct invariant or traversal failure class
- keep codes stable once introduced
- include the code in tests so regressions in classification are visible

If one entry independently violates multiple invariants, `doctor` should emit multiple diagnostics rather than stopping
at the first one.

## Initial Diagnostic Codes

The initial implementation should use these codes:

### Config

- `C0001` invalid root shortname
- `C0002` duplicate root shortname
- `C0003` configured path missing or unopenable
- `C0004` configured path canonicalization failed
- `C0005` configured physical roots overlap / contain each other / are equal
- `C0006` `logical_root` overlaps / contains / is contained by a configured physical root

### Logical

- `L0001` non-directory, non-symlink entry under `logical_root`
- `L0002` logical symlink has a symlink ancestor
- `L0003` logical symlink target is not absolute
- `L0004` logical symlink target string is not canonicalized
- `L0005` logical symlink target is missing
- `L0006` logical symlink target resolves outside configured physical roots
- `L0007` logical symlink target does not resolve to a regular file
- `L0008` logical relative path and physical relative path differ
- `L0009` multiple logical symlinks map to one physical file

### Physical

- `P0001` non-directory, non-regular entry under a physical root
- `P0002` physical file has no corresponding logical symlink
- `P0003` configured physical root missing or unopenable during physical scan
- `P0004` physical traversal / stat / read failure

## Invariants

### Configured path layout

All configured root paths and `logical_root` are interpreted by their canonicalized paths.
Comparisons for overlap / containment are done on canonicalized paths, not raw path strings.
If canonicalization of a configured path fails, that failure is itself a problem, but `doctor` should still attempt
subsequent checks using the raw configured path where practical so diagnostics are not unnecessarily suppressed.

1. configured physical roots must not overlap
2. no configured physical root may be equal to, contain, or be contained by another configured physical root
3. `logical_root` must not be equal to, contain, or be contained by any configured physical root
4. configured root shortnames must be valid and unique
5. shortname validation problems are reported as config diagnostics even though they are not on-disk invariants, because
   they affect the integrity of the configured namespace

Shortnames must match the portable pattern:

`[A-Za-z0-9][A-Za-z0-9._-]*`

These should be reported as `C` codes.

### Logical tree

For every subpath under `logical_root`:

1. it must be either a directory or a symlink
2. if it is a symlink, its target path must be absolute
3. every ancestor of a logical symlink must be a real directory, not a symlink
4. if it is a symlink, its target path string must already be canonicalized
5. if it is a symlink, it must point at an existing inode
6. if it is a symlink, it must resolve to a path inside a configured physical root
7. if it is a symlink, it must resolve to a regular file
8. each logical symlink must map to exactly one physical file, and no two logical symlinks may map to the same physical
   file
9. if multiple logical symlinks map to one physical file, that is an invariant violation and the diagnostic should note
   that shared ownership management is not yet implemented
10. the logical relative path (to logical root) and the target physical relative path (to physical root) must be
    identical.

When multiple logical symlinks map to the same physical file, report that as one grouped diagnostic for the shared
physical file and include all logical paths involved.

This means the logical tree must contain only directories and symlinks.
Regular files, sockets, FIFOs, device nodes, and any other entry kinds under `logical_root` are violations.

These should be reported as `L` codes.

### Physical roots

For every subpath under every configured physical root:

1. it must be either a directory or a regular file
2. every regular file must have exactly one corresponding logical symlink at the identical relative path under
   `logical_root`

This means physical roots must contain only directories and regular files.
Symlinks, sockets, FIFOs, device nodes, and any other entry kinds under a physical root are violations.
If a physical file has no logical symlink, the diagnostic should mention running `jbofs sync`.

These should be reported as `P` codes.

## Notes

- Missing configured paths are reported as problems by `doctor`; they are not special-cased as a separate success mode.
- The checker should continue gathering diagnostics where practical instead of stopping at the first problem.
- Canonicalization requirements are intentional: configured roots and logical symlink targets should already be stored
  in canonical form rather than relying on runtime normalization.
