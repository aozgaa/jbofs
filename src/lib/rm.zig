const std = @import("std");
const cfg = @import("../config.zig");
const pathing = @import("../pathing.zig");

pub const RemoveResult = struct {
    data_missing: bool,
};

pub fn removeManagedFile(
    allocator: std.mem.Allocator,
    config: cfg.Config,
    logical_input: []const u8,
) !RemoveResult {
    const logical_relative = try pathing.normalizeLogicalPath(allocator, config.logical_root, logical_input);
    defer allocator.free(logical_relative);

    const logical_path = try pathing.joinUnderRoot(allocator, config.logical_root, logical_relative);
    defer allocator.free(logical_path);

    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const target = if (std.fs.path.isAbsolute(logical_path))
        std.fs.readLinkAbsolute(logical_path, &link_buffer) catch |err| switch (err) {
            error.FileNotFound => return error.LogicalPathNotFound,
            error.NotLink => return error.LogicalPathNotSymlink,
            else => return err,
        }
    else
        std.fs.cwd().readLink(logical_path, &link_buffer) catch |err| switch (err) {
            error.FileNotFound => return error.LogicalPathNotFound,
            error.NotLink => return error.LogicalPathNotSymlink,
            else => return err,
        };

    var managed = false;
    for (config.roots) |root| {
        if (try pathing.isPathWithinRoot(allocator, target, root.root_path)) {
            managed = true;
            break;
        }
    }
    if (!managed) return error.TargetOutsideManagedRoots;

    var data_missing = false;
    deleteAbsoluteFile(target) catch |err| switch (err) {
        error.FileNotFound => data_missing = true,
        else => return err,
    };
    try deleteAbsoluteFile(logical_path);

    return .{ .data_missing = data_missing };
}

fn deleteAbsoluteFile(file_path: []const u8) !void {
    if (std.fs.path.isAbsolute(file_path)) return std.fs.deleteFileAbsolute(file_path);
    return std.fs.cwd().deleteFile(file_path);
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
    alias_a: []u8,

    fn deinit(self: *OwnedConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.config.roots);
        allocator.free(self.logical_root);
        allocator.free(self.root_a);
        allocator.free(self.alias_a);
    }
};

fn makeConfig(allocator: std.mem.Allocator, tmp_root: []const u8) !OwnedConfig {
    const logical_root = try std.fs.path.join(allocator, &.{ tmp_root, "logical" });
    const root_a = try std.fs.path.join(allocator, &.{ tmp_root, "root-a" });
    const alias_a = try std.fs.path.join(allocator, &.{ tmp_root, "aliases", "disk-0" });
    const aliases_dir = try std.fs.path.join(allocator, &.{ tmp_root, "aliases" });
    defer allocator.free(aliases_dir);

    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_a);
    try std.fs.cwd().makePath(aliases_dir);

    const roots = try allocator.dupe(cfg.Root, &.{
        .{ .root_path = root_a, .alias = alias_a, .shortname = "disk-0" },
    });

    return .{
        .config = .{
            .version = 1,
            .logical_root = logical_root,
            .roots = roots,
            .placement = .{ .default_policy = .first },
        },
        .logical_root = logical_root,
        .root_a = root_a,
        .alias_a = alias_a,
    };
}

test "rm removes healthy managed file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "file.txt" });
    defer std.testing.allocator.free(physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "file.txt" });
    defer std.testing.allocator.free(logical);

    const physical_dir = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media" });
    defer std.testing.allocator.free(physical_dir);
    const logical_dir = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media" });
    defer std.testing.allocator.free(logical_dir);
    try std.fs.cwd().makePath(physical_dir);
    try std.fs.cwd().makePath(logical_dir);

    {
        var file = try std.fs.createFileAbsolute(physical, .{});
        defer file.close();
        try file.writeAll("hello");
    }
    try std.fs.symLinkAbsolute(physical, logical, .{});

    const result = try removeManagedFile(std.testing.allocator, config, "media/file.txt");
    try std.testing.expect(!result.data_missing);
    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(physical, .{}));
    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(logical, .{}));
}

test "rm removes symlink when target already missing" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[0].root_path, "media", "file.txt" });
    defer std.testing.allocator.free(physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "file.txt" });
    defer std.testing.allocator.free(logical);

    const logical_dir = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media" });
    defer std.testing.allocator.free(logical_dir);
    try std.fs.cwd().makePath(logical_dir);
    try std.fs.symLinkAbsolute(physical, logical, .{});

    const result = try removeManagedFile(std.testing.allocator, config, "media/file.txt");
    try std.testing.expect(result.data_missing);
    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(logical, .{}));
}

test "rm rejects symlink target outside configured physical roots" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);
    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;

    const outside = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "outside.txt" });
    defer std.testing.allocator.free(outside);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "file.txt" });
    defer std.testing.allocator.free(logical);

    const logical_dir = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media" });
    defer std.testing.allocator.free(logical_dir);
    try std.fs.cwd().makePath(logical_dir);

    {
        var file = try std.fs.createFileAbsolute(outside, .{});
        defer file.close();
        try file.writeAll("hello");
    }
    try std.fs.symLinkAbsolute(outside, logical, .{});

    try std.testing.expectError(error.TargetOutsideManagedRoots, removeManagedFile(std.testing.allocator, config, "media/file.txt"));
}
