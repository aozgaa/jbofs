const std = @import("std");
const cfg = @import("../config.zig");
const pathing = @import("../pathing.zig");

pub const SyncResult = struct {
    created: usize = 0,
    unchanged: usize = 0,
    conflicts: usize = 0,
};

pub fn syncLogicalLinks(allocator: std.mem.Allocator, config: cfg.Config) !SyncResult {
    var result = SyncResult{};

    for (config.roots) |root| {
        var dir = try std.fs.openDirAbsolute(root.root_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            const physical_path = try std.fs.path.join(allocator, &.{ root.root_path, entry.path });
            defer allocator.free(physical_path);
            const logical_path = try std.fs.path.join(allocator, &.{ config.logical_root, entry.path });
            defer allocator.free(logical_path);

            if (!(try pathExists(logical_path))) {
                if (std.fs.path.dirname(logical_path)) |parent| try std.fs.cwd().makePath(parent);
                try std.fs.symLinkAbsolute(physical_path, logical_path, .{});
                result.created += 1;
                continue;
            }

            var buffer: [std.fs.max_path_bytes]u8 = undefined;
            const existing_target = std.fs.readLinkAbsolute(logical_path, &buffer) catch |err| switch (err) {
                error.NotLink => {
                    result.conflicts += 1;
                    continue;
                },
                else => return err,
            };

            if (std.mem.eql(u8, existing_target, physical_path)) {
                result.unchanged += 1;
            } else {
                result.conflicts += 1;
            }
        }
    }

    return result;
}

fn pathExists(path: []const u8) !bool {
    if (std.posix.access(path, std.posix.F_OK)) |_| return true else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.fs.readLinkAbsolute(path, &buffer) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.NotLink => return true,
        else => return true,
    };
    return true;
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

fn createPhysicalFile(physical_path: []const u8) !void {
    if (std.fs.path.dirname(physical_path)) |parent| try std.fs.cwd().makePath(parent);
    var file = try std.fs.createFileAbsolute(physical_path, .{});
    defer file.close();
    try file.writeAll("data");
}

test "sync creates missing logical symlinks" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "movie.mkv" });
    defer std.testing.allocator.free(physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "movie.mkv" });
    defer std.testing.allocator.free(logical);

    try createPhysicalFile(physical);
    const result = try syncLogicalLinks(std.testing.allocator, config);

    try std.testing.expectEqual(@as(usize, 1), result.created);
    try std.testing.expect(try pathExists(logical));
}

test "sync leaves correct links untouched" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "movie.mkv" });
    defer std.testing.allocator.free(physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "movie.mkv" });
    defer std.testing.allocator.free(logical);

    try createPhysicalFile(physical);
    if (std.fs.path.dirname(logical)) |parent| try std.fs.cwd().makePath(parent);
    try std.fs.symLinkAbsolute(physical, logical, .{});

    const result = try syncLogicalLinks(std.testing.allocator, config);
    try std.testing.expectEqual(@as(usize, 1), result.unchanged);
}

test "sync reports conflicts without overwriting" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "movie.mkv" });
    defer std.testing.allocator.free(physical);
    const other_physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[1].root_path, "media", "other.mkv" });
    defer std.testing.allocator.free(other_physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "movie.mkv" });
    defer std.testing.allocator.free(logical);

    try createPhysicalFile(physical);
    try createPhysicalFile(other_physical);
    if (std.fs.path.dirname(logical)) |parent| try std.fs.cwd().makePath(parent);
    try std.fs.symLinkAbsolute(other_physical, logical, .{});

    const result = try syncLogicalLinks(std.testing.allocator, config);
    try std.testing.expectEqual(@as(usize, 1), result.conflicts);

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const target = try std.fs.readLinkAbsolute(logical, &buffer);
    try std.testing.expectEqualStrings(other_physical, target);
}
