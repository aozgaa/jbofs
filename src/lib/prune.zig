const std = @import("std");
const cfg = @import("../config.zig");

pub fn pruneDeadLinks(allocator: std.mem.Allocator, config: cfg.Config) !usize {
    var dir = try std.fs.openDirAbsolute(config.logical_root, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var pruned: usize = 0;
    while (try walker.next()) |entry| {
        if (entry.kind != .sym_link) continue;

        const logical_path = try std.fs.path.join(allocator, &.{ config.logical_root, entry.path });
        defer allocator.free(logical_path);

        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const target = try std.fs.readLinkAbsolute(logical_path, &buffer);

        if (!(try targetExists(target))) {
            try std.fs.deleteFileAbsolute(logical_path);
            pruned += 1;
        }
    }

    return pruned;
}

fn targetExists(path: []const u8) !bool {
    if (std.posix.access(path, std.posix.F_OK)) |_| return true else |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
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

    fn deinit(self: *OwnedConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.config.roots);
        allocator.free(self.logical_root);
        allocator.free(self.root_a);
    }
};

fn makeConfig(allocator: std.mem.Allocator, tmp_root: []const u8) !OwnedConfig {
    const logical_root = try std.fs.path.join(allocator, &.{ tmp_root, "logical" });
    const root_a = try std.fs.path.join(allocator, &.{ tmp_root, "root-a" });

    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_a);

    const roots = try allocator.dupe(cfg.Root, &.{
        .{ .root_path = root_a, .shortname = "disk-0" },
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
    };
}

test "prune removes dead symlinks only" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical_live = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "live.txt" });
    defer std.testing.allocator.free(physical_live);
    const physical_dead = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "dead.txt" });
    defer std.testing.allocator.free(physical_dead);
    const logical_dir = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media" });
    defer std.testing.allocator.free(logical_dir);
    const root_dir = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media" });
    defer std.testing.allocator.free(root_dir);

    try std.fs.cwd().makePath(logical_dir);
    try std.fs.cwd().makePath(root_dir);

    {
        var file = try std.fs.createFileAbsolute(physical_live, .{});
        defer file.close();
        try file.writeAll("live");
    }

    const logical_live = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "live.txt" });
    defer std.testing.allocator.free(logical_live);
    const logical_dead = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "dead.txt" });
    defer std.testing.allocator.free(logical_dead);

    try std.fs.symLinkAbsolute(physical_live, logical_live, .{});
    try std.fs.symLinkAbsolute(physical_dead, logical_dead, .{});

    const pruned = try pruneDeadLinks(std.testing.allocator, config);
    try std.testing.expectEqual(@as(usize, 1), pruned);
    try std.testing.expect(try targetExists(physical_live));
    try std.testing.expect(try targetExists(logical_live));
    try std.testing.expect(!(try targetExists(logical_dead)));
}
