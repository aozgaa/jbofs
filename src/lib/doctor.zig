const std = @import("std");
const cfg = @import("../config.zig");

pub const Scope = enum { config };

pub const Diagnostic = struct {
    code: []const u8,
    scope: Scope,
    path: []const u8,
    message: []const u8,
};

pub const Report = struct {
    diagnostics: []Diagnostic,

    pub fn deinit(self: Report, allocator: std.mem.Allocator) void {
        allocator.free(self.diagnostics);
    }
};

pub fn checkConfig(allocator: std.mem.Allocator, config: cfg.Config) !Report {
    var diagnostics = std.ArrayList(Diagnostic).empty;
    errdefer diagnostics.deinit(allocator);

    try appendPathDiagnostic(allocator, &diagnostics, config.logical_root);
    for (config.roots) |root| {
        try appendPathDiagnostic(allocator, &diagnostics, root.root_path);
    }

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
        try diagnostics.append(allocator, .{
            .code = "C0003",
            .scope = .config,
            .path = path,
            .message = "configured path is missing or unopenable",
        });
        return;
    };
    defer dir.close();
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

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("C0003", report.diagnostics[0].code);
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

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("C0003", report.diagnostics[0].code);
}
