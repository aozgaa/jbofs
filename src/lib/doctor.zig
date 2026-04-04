const std = @import("std");
const builtin = @import("builtin");
const cfg = @import("../config.zig");

pub const Scope = enum {
    config,
    logical,
};

pub const Diagnostic = struct {
    code: []const u8,
    scope: Scope,
    path: []const u8,
    message: []const u8,
    owns_path: bool = false,

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        if (self.owns_path) allocator.free(self.path);
        allocator.free(self.message);
    }
};

pub const Report = struct {
    diagnostics: []Diagnostic,

    pub fn deinit(self: Report, allocator: std.mem.Allocator) void {
        for (self.diagnostics) |d| d.deinit(allocator);
        allocator.free(self.diagnostics);
    }
};

fn isValidShortname(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |c, i| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or
            (i > 0 and (c == '.' or c == '_' or c == '-'));
        if (!ok) return false;
    }
    return true;
}

/// Appends a diagnostic, taking ownership of `diag.message` and, when `owns_path`
/// is set, `diag.path`. On OOM, frees any owned allocations before propagating
/// the error.
fn appendDiagnostic(
    allocator: std.mem.Allocator,
    diagnostics: *std.ArrayList(Diagnostic),
    diag: Diagnostic,
) !void {
    diagnostics.append(allocator, diag) catch |err| {
        diag.deinit(allocator);
        return err;
    };
}

pub fn checkConfig(allocator: std.mem.Allocator, config: cfg.Config) !Report {
    var diagnostics = std.ArrayList(Diagnostic).empty;
    errdefer {
        for (diagnostics.items) |d| d.deinit(allocator);
        diagnostics.deinit(allocator);
    }

    for (config.roots) |root| {
        if (!isValidShortname(root.shortname)) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "invalid root shortname '{s}'; must match [A-Za-z0-9][A-Za-z0-9._-]*",
                .{root.shortname},
            );
            try appendDiagnostic(allocator, &diagnostics, .{
                .code = "C0001",
                .scope = .config,
                .path = root.root_path,
                .message = msg,
            });
        }
    }

    try appendPathDiagnostic(allocator, &diagnostics, config.logical_root);
    for (config.roots) |root| {
        try appendPathDiagnostic(allocator, &diagnostics, root.root_path);
    }

    // C0002 duplicate shortname check
    for (config.roots, 0..) |root_a, i| {
        for (config.roots[i + 1 ..]) |root_b| {
            if (std.mem.eql(u8, root_a.shortname, root_b.shortname)) {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "duplicate shortname; also used by root at {s}",
                    .{root_b.root_path},
                );
                try appendDiagnostic(allocator, &diagnostics, .{
                    .code = "C0002",
                    .scope = .config,
                    .path = root_a.root_path,
                    .message = msg,
                });
            }
        }
    }

    // Canonicalize all configured paths for overlap checks (C0004, C0005, C0006).
    // Canonical strings are intermediate data: owned locally, freed before return.
    const logical_canon: ?[]u8 = try appendCanonDiagnostic(allocator, &diagnostics, config.logical_root);
    defer if (logical_canon) |c| allocator.free(c);

    var root_canons = try allocator.alloc(?[]u8, config.roots.len);
    for (root_canons) |*slot| slot.* = null;
    defer {
        for (root_canons) |canon| if (canon) |c| allocator.free(c);
        allocator.free(root_canons);
    }
    for (config.roots, 0..) |root, i| {
        root_canons[i] = try appendCanonDiagnostic(allocator, &diagnostics, root.root_path);
    }

    // C0005 physical roots overlap check
    for (config.roots, 0..) |root_a, i| {
        const canon_a: []const u8 = root_canons[i] orelse config.roots[i].root_path;
        for (config.roots[i + 1 ..], i + 1..config.roots.len) |root_b, j| {
            const canon_b: []const u8 = root_canons[j] orelse config.roots[j].root_path;
            if (pathsOverlap(canon_a, canon_b)) {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "physical root overlaps with {s}",
                    .{root_b.root_path},
                );
                try appendDiagnostic(allocator, &diagnostics, .{
                    .code = "C0005",
                    .scope = .config,
                    .path = root_a.root_path,
                    .message = msg,
                });
            }
        }
    }

    // C0006 logical_root overlaps with physical root check
    const logical_canon_path: []const u8 = logical_canon orelse config.logical_root;
    for (config.roots, 0..) |root, i| {
        const canon_r: []const u8 = root_canons[i] orelse root.root_path;
        if (pathsOverlap(logical_canon_path, canon_r)) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "logical_root overlaps with physical root {s}",
                .{root.root_path},
            );
            try appendDiagnostic(allocator, &diagnostics, .{
                .code = "C0006",
                .scope = .config,
                .path = config.logical_root,
                .message = msg,
            });
        }
    }

    try appendLogicalEntryDiagnostics(allocator, &diagnostics, config);

    sortDiagnostics(diagnostics.items);
    return .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) };
}

pub fn run(allocator: std.mem.Allocator, config: cfg.Config) !void {
    var report = try checkConfig(allocator, config);
    defer report.deinit(allocator);

    if (report.diagnostics.len == 0) return;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.fs.File.stderr();
    var writer = stderr.writer(&stderr_buffer);
    try printReport(&writer.interface, report);
    try writer.interface.flush();
    return error.DoctorFoundIssues;
}

pub fn printReport(writer: *std.Io.Writer, report: Report) !void {
    for (report.diagnostics) |diagnostic| {
        try printDiagnostic(writer, diagnostic);
    }
}

fn appendPathDiagnostic(
    allocator: std.mem.Allocator,
    diagnostics: *std.ArrayList(Diagnostic),
    path: []const u8,
) !void {
    var dir = std.fs.openDirAbsolute(path, .{}) catch {
        const msg = try allocator.dupe(u8, "configured path is missing or unopenable");
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "C0003",
            .scope = .config,
            .path = path,
            .message = msg,
        });
        return;
    };
    defer dir.close();
}

fn appendCanonDiagnostic(
    allocator: std.mem.Allocator,
    diagnostics: *std.ArrayList(Diagnostic),
    path: []const u8,
) !?[]u8 {
    const canon = std.fs.realpathAlloc(allocator, path) catch {
        const msg = try std.fmt.allocPrint(
            allocator,
            "configured path cannot be canonicalized (realpath failed)",
            .{},
        );
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "C0004",
            .scope = .config,
            .path = path,
            .message = msg,
        });
        return null;
    };
    return canon;
}

fn appendLogicalEntryDiagnostics(
    allocator: std.mem.Allocator,
    diagnostics: *std.ArrayList(Diagnostic),
    config: cfg.Config,
) !void {
    const logical_root = config.logical_root;
    var dir = std.fs.openDirAbsolute(logical_root, .{ .iterate = true }) catch return;
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const logical_path = try std.fs.path.join(allocator, &.{ logical_root, entry.path });
        defer allocator.free(logical_path);

        switch (entry.kind) {
            .directory => {},
            .sym_link => {
                try checkLogicalSymlink(allocator, diagnostics, config, logical_path);
            },
            else => {
                const kind_name = @tagName(entry.kind);
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "unexpected logical entry kind '{s}'; expected directory or symlink",
                    .{kind_name},
                );
                try appendDiagnostic(allocator, diagnostics, .{
                    .code = "L0001",
                    .scope = .logical,
                    .path = try allocator.dupe(u8, logical_path),
                    .message = msg,
                    .owns_path = true,
                });
            },
        }
    }
}

fn checkLogicalSymlink(
    allocator: std.mem.Allocator,
    diagnostics: *std.ArrayList(Diagnostic),
    config: cfg.Config,
    logical_path: []const u8,
) !void {
    var target_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const target = try std.fs.readLinkAbsolute(logical_path, &target_buffer);

    if (!std.fs.path.isAbsolute(target)) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "logical symlink target is not absolute: {s}",
            .{target},
        );
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "L0002",
            .scope = .logical,
            .path = try allocator.dupe(u8, logical_path),
            .message = msg,
            .owns_path = true,
        });
    }

    const canonical_target = std.fs.realpathAlloc(allocator, target) catch |err| {
        if (err == error.FileNotFound) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "logical symlink target is missing: {s}; run `jbofs prune` to remove the dead symlink",
                .{target},
            );
            try appendDiagnostic(allocator, diagnostics, .{
                .code = "L0006",
                .scope = .logical,
                .path = try allocator.dupe(u8, logical_path),
                .message = msg,
                .owns_path = true,
            });
        }
        return;
    };
    defer allocator.free(canonical_target);

    if (!std.mem.eql(u8, target, canonical_target)) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "logical symlink target is not canonicalized: stored {s}, canonical {s}",
            .{ target, canonical_target },
        );
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "L0003",
            .scope = .logical,
            .path = try allocator.dupe(u8, logical_path),
            .message = msg,
            .owns_path = true,
        });
    }

    const canonical_logical_root = std.fs.realpathAlloc(allocator, config.logical_root) catch return;
    defer allocator.free(canonical_logical_root);

    if (pathStartsWith(canonical_target, canonical_logical_root)) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "logical symlink target resolves inside logical_root: {s}",
            .{canonical_target},
        );
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "L0004",
            .scope = .logical,
            .path = try allocator.dupe(u8, logical_path),
            .message = msg,
            .owns_path = true,
        });
    }

    var inside_any_root = false;
    for (config.roots) |root| {
        const canonical_root = std.fs.realpathAlloc(allocator, root.root_path) catch continue;
        defer allocator.free(canonical_root);

        if (pathStartsWith(canonical_target, canonical_root)) {
            inside_any_root = true;
            break;
        }
    }

    if (!inside_any_root) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "logical symlink target resolves outside configured physical roots: {s}",
            .{canonical_target},
        );
        try appendDiagnostic(allocator, diagnostics, .{
            .code = "L0005",
            .scope = .logical,
            .path = try allocator.dupe(u8, logical_path),
            .message = msg,
            .owns_path = true,
        });
    }
}

fn pathStartsWith(path: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    if (path.len == prefix.len) return true;
    return path[prefix.len] == '/';
}

fn pathsOverlap(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return true;
    if (pathStartsWith(a, b)) return true;
    if (pathStartsWith(b, a)) return true;
    return false;
}

fn printDiagnostic(writer: *std.Io.Writer, diagnostic: Diagnostic) !void {
    try writer.print("{s} [{s}] {s}: {s}\n", .{
        diagnostic.code,
        @tagName(diagnostic.scope),
        diagnostic.path,
        diagnostic.message,
    });
}

fn sortDiagnostics(diagnostics: []Diagnostic) void {
    var i: usize = 1;
    while (i < diagnostics.len) : (i += 1) {
        var j = i;
        while (j > 0 and diagnosticLess(diagnostics[j], diagnostics[j - 1])) : (j -= 1) {
            std.mem.swap(Diagnostic, &diagnostics[j], &diagnostics[j - 1]);
        }
    }
}

fn diagnosticLess(a: Diagnostic, b: Diagnostic) bool {
    switch (std.mem.order(u8, a.code, b.code)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.path, b.path)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.message, b.message)) {
        .lt => return true,
        .gt => return false,
        .eq => return @intFromEnum(a.scope) < @intFromEnum(b.scope),
    }
}

fn tmpDirPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir) ![]u8 {
    const relative = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(relative);
    return std.fs.cwd().realpathAlloc(allocator, relative);
}

const OwnedConfig = struct {
    config: cfg.Config,
    logical_root: []u8,
    root_a: []u8,
    root_b: []u8,

    fn deinit(self: *OwnedConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.config.roots);
        allocator.free(self.logical_root);
        allocator.free(self.root_a);
        allocator.free(self.root_b);
    }
};

fn makeConfig(allocator: std.mem.Allocator, tmp_root: []const u8) !OwnedConfig {
    const logical_root = try std.fs.path.join(allocator, &.{ tmp_root, "logical" });
    const root_a = try std.fs.path.join(allocator, &.{ tmp_root, "root-a" });
    const root_b = try std.fs.path.join(allocator, &.{ tmp_root, "root-b" });

    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_a);
    try std.fs.cwd().makePath(root_b);

    const roots = try allocator.dupe(cfg.Root, &.{
        .{ .root_path = root_a, .shortname = "disk-0" },
        .{ .root_path = root_b, .shortname = "disk-1" },
    });

    return .{
        .config = .{
            .version = 2,
            .logical_root = logical_root,
            .roots = roots,
            .placement = .{ .default_policy = .first },
        },
        .logical_root = logical_root,
        .root_a = root_a,
        .root_b = root_b,
    };
}

fn createFifo(path: []const u8) !void {
    const posix_path = try std.posix.toPosixPath(path);
    const fifo_mode: u32 = std.os.linux.S.IFIFO | 0o644;
    const mknod_ret = std.os.linux.mknod(&posix_path, fifo_mode, 0);
    try std.testing.expectEqual(@as(usize, 0), mknod_ret);
}

fn createUnixSocket(path: []const u8) !std.posix.socket_t {
    const sock = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.DGRAM, 0);
    errdefer std.posix.close(sock);

    var addr: std.posix.sockaddr.un = undefined;
    addr.family = std.posix.AF.UNIX;
    @memset(&addr.path, 0);
    if (path.len > addr.path.len) return error.NameTooLong;
    @memcpy(addr.path[0..path.len], path);
    try std.posix.bind(sock, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un));
    return sock;
}

fn countDiagnosticsWithCode(report: Report, code: []const u8) usize {
    var count: usize = 0;
    for (report.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, code)) count += 1;
    }
    return count;
}

test "pathStartsWith" {
    try std.testing.expect(pathStartsWith("", ""));
    try std.testing.expect(!pathStartsWith("", "/"));
    try std.testing.expect(pathStartsWith("/", ""));
    try std.testing.expect(pathStartsWith("/", "/"));

    try std.testing.expect(pathStartsWith("/srv/jbofs/logical", "/srv/jbofs/logical"));
    try std.testing.expect(pathStartsWith("/srv/jbofs/logical/media/movie.mkv", "/srv/jbofs/logical"));
    try std.testing.expect(!pathStartsWith("/srv/jbofs/logical2", "/srv/jbofs/logical"));
    try std.testing.expect(!pathStartsWith("/srv/jbofs/logical-sibling", "/srv/jbofs/logical"));
    try std.testing.expect(!pathStartsWith("/srv/jbofs", "/srv/jbofs/logical"));
    try std.testing.expect(!pathStartsWith("/srv/jbofs/logical", "/srv/jbofs/logical/media"));
}

test "doctor check emits no diagnostics for well formed logical mapping in subdir" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const physical_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.root_a, "media", "movie.mkv" },
    );
    defer std.testing.allocator.free(physical_path);
    if (std.fs.path.dirname(physical_path)) |parent| try std.fs.cwd().makePath(parent);
    var file = try std.fs.createFileAbsolute(physical_path, .{});
    defer file.close();
    try file.writeAll("data");

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "media", "movie.mkv" },
    );
    defer std.testing.allocator.free(logical_link);
    if (std.fs.path.dirname(logical_link)) |parent| try std.fs.cwd().makePath(parent);
    try std.fs.symLinkAbsolute(physical_path, logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), report.diagnostics.len);
}

test "doctor check reports L0003 for non-canonical logical symlink target" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const physical_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.root_a, "media", "movie.mkv" },
    );
    defer std.testing.allocator.free(physical_path);
    if (std.fs.path.dirname(physical_path)) |parent| try std.fs.cwd().makePath(parent);
    var file = try std.fs.createFileAbsolute(physical_path, .{});
    defer file.close();
    try file.writeAll("data");

    const non_canonical_target = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.root_a, "media", "..", "media", "movie.mkv" },
    );
    defer std.testing.allocator.free(non_canonical_target);

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "media", "movie.mkv" },
    );
    defer std.testing.allocator.free(logical_link);
    if (std.fs.path.dirname(logical_link)) |parent| try std.fs.cwd().makePath(parent);
    try std.fs.symLinkAbsolute(non_canonical_target, logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countDiagnosticsWithCode(report, "L0003"));
}

test "doctor check reports L0004 for logical symlink target inside logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const target_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "nested", "payload.txt" },
    );
    defer std.testing.allocator.free(target_path);
    if (std.fs.path.dirname(target_path)) |parent| try std.fs.cwd().makePath(parent);
    var file = try std.fs.createFileAbsolute(target_path, .{});
    defer file.close();
    try file.writeAll("payload");

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "loop-link" },
    );
    defer std.testing.allocator.free(logical_link);
    try std.fs.symLinkAbsolute(target_path, logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countDiagnosticsWithCode(report, "L0004"));
}

test "doctor check reports L0005 for logical symlink target outside configured roots" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const outside_target = try std.fs.path.join(
        std.testing.allocator,
        &.{ tmp_root, "outside", "payload.txt" },
    );
    defer std.testing.allocator.free(outside_target);
    if (std.fs.path.dirname(outside_target)) |parent| try std.fs.cwd().makePath(parent);
    var file = try std.fs.createFileAbsolute(outside_target, .{});
    defer file.close();
    try file.writeAll("payload");

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "outside-link" },
    );
    defer std.testing.allocator.free(logical_link);
    try std.fs.symLinkAbsolute(outside_target, logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countDiagnosticsWithCode(report, "L0005"));
}

test "doctor check reports L0006 for missing logical symlink target" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const missing_target = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.root_a, "missing", "payload.txt" },
    );
    defer std.testing.allocator.free(missing_target);

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "missing-link" },
    );
    defer std.testing.allocator.free(logical_link);
    try std.fs.symLinkAbsolute(missing_target, logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countDiagnosticsWithCode(report, "L0006"));

    const l0006 = for (report.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "L0006")) break d;
    } else unreachable;
    try std.testing.expect(std.mem.indexOf(u8, l0006.message, "jbofs prune") != null);
}

test "doctor check succeeds when config paths exist" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), report.diagnostics.len);
}

test "doctor run succeeds when config paths exist" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    try run(std.testing.allocator, owned.config);
}

test "doctor check reports C0003 for missing logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    try std.fs.deleteTreeAbsolute(owned.logical_root);

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    // A missing path triggers both C0003 (can't open) and C0004 (can't canonicalize).
    const found_c0003 = for (report.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "C0003")) break true;
    } else false;
    try std.testing.expect(found_c0003);
}

test "doctor check reports C0003 for missing physical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    try std.fs.deleteTreeAbsolute(owned.root_a);

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    // A missing path triggers both C0003 (can't open) and C0004 (can't canonicalize).
    const found_c0003 = for (report.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "C0003")) break true;
    } else false;
    try std.testing.expect(found_c0003);
}

test "doctor check reports C0001 for invalid shortname" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Patch one root to have an invalid shortname via a mutable copy.
    var patched_roots = [_]cfg.Root{
        .{ .root_path = owned.config.roots[0].root_path, .shortname = "" },
        owned.config.roots[1],
    };
    var patched_config = owned.config;
    patched_config.roots = &patched_roots;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("C0001", report.diagnostics[0].code);
}

test "doctor check reports C0001 for shortname starting with dot" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Patch one root to have an invalid shortname via a mutable copy.
    var patched_roots = [_]cfg.Root{
        .{ .root_path = owned.config.roots[0].root_path, .shortname = ".hidden" },
        owned.config.roots[1],
    };
    var patched_config = owned.config;
    patched_config.roots = &patched_roots;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("C0001", report.diagnostics[0].code);
}

test "doctor check reports C0004 for non-canonicalizable logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Point logical_root at a path that doesn't exist → realpath fails.
    const missing = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "no-such-dir" });
    defer std.testing.allocator.free(missing);

    // Patch logical root using mutable copy pattern.
    var patched_config = owned.config;
    patched_config.logical_root = missing;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    // Expect both C0003 (can't open) and C0004 (can't canonicalize).
    const codes: []const []const u8 = &.{ "C0003", "C0004" };
    for (codes) |code| {
        const found = for (report.diagnostics) |d| {
            if (std.mem.eql(u8, d.code, code)) break true;
        } else false;
        try std.testing.expect(found);
    }
}

test "doctor check reports C0005 when one physical root is inside another" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Make root_b a subdirectory of root_a.
    const nested = try std.fs.path.join(std.testing.allocator, &.{ owned.root_a, "sub" });
    defer std.testing.allocator.free(nested);
    try std.fs.cwd().makePath(nested);

    // Patch root_b to point to the nested path.
    var patched_roots = [_]cfg.Root{
        .{ .root_path = owned.root_a, .shortname = owned.config.roots[0].shortname },
        .{ .root_path = nested, .shortname = owned.config.roots[1].shortname },
    };
    var patched_config = owned.config;
    patched_config.roots = &patched_roots;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    const c0005_count = blk: {
        var n: usize = 0;
        for (report.diagnostics) |d| {
            if (std.mem.eql(u8, d.code, "C0005")) n += 1;
        }
        break :blk n;
    };
    try std.testing.expectEqual(@as(usize, 1), c0005_count);
}

test "doctor check reports C0002 for duplicate shortname" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Both roots now share the same shortname.
    // Note: cfg.Config.roots is []const Root so use mutable array copy pattern.
    var patched_roots = [_]cfg.Root{
        .{ .root_path = owned.root_a, .shortname = owned.config.roots[0].shortname },
        .{ .root_path = owned.root_b, .shortname = owned.config.roots[0].shortname },
    };
    var patched_config = owned.config;
    patched_config.roots = &patched_roots;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    const c0002_count = blk: {
        var n: usize = 0;
        for (report.diagnostics) |d| if (std.mem.eql(u8, d.code, "C0002")) {
            n += 1;
        };
        break :blk n;
    };
    try std.testing.expectEqual(@as(usize, 1), c0002_count);
}

test "doctor check reports C0006 when logical root is inside a physical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    // Move logical_root inside root_a.
    const nested_logical = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.root_a, "logical" },
    );
    defer std.testing.allocator.free(nested_logical);
    try std.fs.cwd().makePath(nested_logical);

    var patched_config = owned.config;
    patched_config.logical_root = nested_logical;

    const report = try checkConfig(std.testing.allocator, patched_config);
    defer report.deinit(std.testing.allocator);

    const c0006_count = blk: {
        var n: usize = 0;
        for (report.diagnostics) |d| {
            if (std.mem.eql(u8, d.code, "C0006")) n += 1;
        }
        break :blk n;
    };
    try std.testing.expectEqual(@as(usize, 1), c0006_count);
}

test "doctor check accepts directories and symlinks under logical root for L0001" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const child_dir = try std.fs.path.join(std.testing.allocator, &.{ owned.logical_root, "child-dir" });
    defer std.testing.allocator.free(child_dir);
    try std.fs.cwd().makePath(child_dir);

    const child_link = try std.fs.path.join(std.testing.allocator, &.{ owned.logical_root, "child-link" });
    defer std.testing.allocator.free(child_link);
    try std.fs.symLinkAbsolute("/definitely/missing-target", child_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), countDiagnosticsWithCode(report, "L0001"));
}

test "doctor check reports L0001 for regular file under logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const invalid_entry = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "loose-file.txt" },
    );
    defer std.testing.allocator.free(invalid_entry);

    var file = try std.fs.createFileAbsolute(invalid_entry, .{});
    defer file.close();
    try file.writeAll("bad");

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("L0001", report.diagnostics[0].code);
    try std.testing.expectEqualStrings(invalid_entry, report.diagnostics[0].path);
}

test "doctor check reports L0001 for fifo under logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const invalid_entry = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "named-pipe" },
    );
    defer std.testing.allocator.free(invalid_entry);

    try createFifo(invalid_entry);

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("L0001", report.diagnostics[0].code);
    try std.testing.expectEqualStrings(invalid_entry, report.diagnostics[0].path);
}

test "doctor check reports L0001 for unix socket under logical root" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const short_root = try std.fs.path.join(
        std.testing.allocator,
        &.{ "/tmp", "jbofs-doctor-sock-root" },
    );
    defer std.testing.allocator.free(short_root);
    std.fs.deleteFileAbsolute(short_root) catch {};
    try std.fs.symLinkAbsolute(owned.logical_root, short_root, .{});
    defer std.fs.deleteFileAbsolute(short_root) catch {};

    const short_socket_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ short_root, "s" },
    );
    defer std.testing.allocator.free(short_socket_path);

    const invalid_entry = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "s" },
    );
    defer std.testing.allocator.free(invalid_entry);

    const sock = try createUnixSocket(short_socket_path);
    defer std.posix.close(sock);

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("L0001", report.diagnostics[0].code);
    try std.testing.expectEqualStrings(invalid_entry, report.diagnostics[0].path);
}

test "doctor L0001 device-node coverage requires admin-controlled environment" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    // TODO: Add block-device and character-device L0001 coverage in a container,
    // user namespace, or other admin-controlled test environment that can create
    // device nodes without depending on the developer workstation state.
    return error.SkipZigTest;
}

test "doctor check reports L0002 for relative logical symlink target" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);

    const logical_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ owned.logical_root, "relative-link" },
    );
    defer std.testing.allocator.free(logical_link);
    try std.fs.cwd().symLink("relative/target.txt", logical_link, .{});

    const report = try checkConfig(std.testing.allocator, owned.config);
    defer report.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countDiagnosticsWithCode(report, "L0002"));
}
