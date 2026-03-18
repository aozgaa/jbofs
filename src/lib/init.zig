const std = @import("std");
const cfg = @import("../config.zig");

pub const InitRootInput = cfg.Root;

pub const InitConfigInput = struct {
    logical_root: []const u8,
    roots: []const InitRootInput,
    default_policy: cfg.PlacementPolicy = .@"most-free",
};

pub fn buildConfig(input: InitConfigInput) !cfg.Config {
    if (input.roots.len == 0) return error.NoRootsConfigured;

    return .{
        .version = 2,
        .logical_root = input.logical_root,
        .roots = @ptrCast(input.roots),
        .placement = .{ .default_policy = input.default_policy },
    };
}

pub fn writeConfigFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    config: cfg.Config,
    force: bool,
) !void {
    const payload = try cfg.stringifyConfig(allocator, config);
    defer allocator.free(payload);

    if (std.fs.path.dirname(file_path)) |parent| {
        try std.fs.cwd().makePath(parent);
    }

    var file = openConfigFile(file_path, force) catch |err| switch (err) {
        error.PathAlreadyExists => return error.ConfigAlreadyExists,
        else => return err,
    };
    defer file.close();

    try file.writeAll(payload);
}

pub const DirStatus = union(enum) {
    ok,
    failed: anyerror,
};

pub const CreateDirsResult = struct {
    logical_root: DirStatus,
    roots: []DirStatus, // one per configured root, caller must free

    pub fn deinit(self: CreateDirsResult, allocator: std.mem.Allocator) void {
        allocator.free(self.roots);
    }
};

pub fn createRequiredDirectories(
    allocator: std.mem.Allocator,
    config: cfg.Config,
) !CreateDirsResult {
    const logical_root_status: DirStatus = if (std.fs.cwd().makePath(config.logical_root)) |_|
        .ok
    else |err|
        .{ .failed = err };

    const roots_statuses = try allocator.alloc(DirStatus, config.roots.len);
    for (config.roots, 0..) |root, i| {
        roots_statuses[i] = if (std.fs.cwd().makePath(root.root_path)) |_|
            .ok
        else |err|
            .{ .failed = err };
    }

    return .{
        .logical_root = logical_root_status,
        .roots = roots_statuses,
    };
}

fn openConfigFile(file_path: []const u8, force: bool) !std.fs.File {
    if (std.fs.path.isAbsolute(file_path)) {
        return std.fs.createFileAbsolute(file_path, .{
            .truncate = true,
            .exclusive = !force,
        });
    }

    return std.fs.cwd().createFile(file_path, .{
        .truncate = true,
        .exclusive = !force,
    });
}

fn tmpDirPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir) ![]u8 {
    const relative = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(relative);
    return std.fs.cwd().realpathAlloc(allocator, relative);
}

test "build config creates valid root_path schema" {
    const config = try buildConfig(.{
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .shortname = "disk-0",
            },
        },
    });

    const payload = try cfg.stringifyConfig(std.testing.allocator, config);
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"root_path\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"disk-0\"") != null);
}

test "write config to new path" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const config_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "nested", "fs_config.json" });
    defer std.testing.allocator.free(config_path);

    const config = try buildConfig(.{
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .shortname = "disk-0",
            },
        },
    });

    try writeConfigFile(std.testing.allocator, config_path, config, false);

    const file_data = try std.fs.cwd().readFileAlloc(std.testing.allocator, config_path, 1024 * 1024);
    defer std.testing.allocator.free(file_data);

    try std.testing.expect(std.mem.indexOf(u8, file_data, "\"logical_root\"") != null);
}

test "refuse overwrite without force" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const config_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "fs_config.json" });
    defer std.testing.allocator.free(config_path);

    const config = try buildConfig(.{
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .shortname = "disk-0",
            },
        },
    });

    try writeConfigFile(std.testing.allocator, config_path, config, false);
    try std.testing.expectError(error.ConfigAlreadyExists, writeConfigFile(std.testing.allocator, config_path, config, false));
}

test "createRequiredDirectories succeeds for fresh tmp directories" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
    try std.testing.expectEqual(@as(usize, 1), result.roots.len);
    try std.testing.expectEqual(DirStatus.ok, result.roots[0]);
}

test "createRequiredDirectories ok when directories already exist" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);

    // Create the directories first so they already exist
    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
    try std.testing.expectEqual(DirStatus.ok, result.roots[0]);
}

test "createRequiredDirectories returns failed when path is a file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw-disk" });
    defer std.testing.allocator.free(root_path);

    // Place a file at root_path so makePath fails (file where a dir is expected)
    const file = try std.fs.createFileAbsolute(root_path, .{});
    file.close();

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config);
    defer result.deinit(std.testing.allocator);

    // logical_root should succeed
    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
    // root_path should fail because a file exists there
    try std.testing.expect(result.roots[0] == .failed);
}

test "allow overwrite with force" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const config_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "fs_config.json" });
    defer std.testing.allocator.free(config_path);

    const first_config = try buildConfig(.{
        .logical_root = "/srv/jbofs/logical-a",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .shortname = "disk-0",
            },
        },
    });

    const second_config = try buildConfig(.{
        .logical_root = "/srv/jbofs/logical-b",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-b",
                .shortname = "disk-1",
            },
        },
    });

    try writeConfigFile(std.testing.allocator, config_path, first_config, false);
    try writeConfigFile(std.testing.allocator, config_path, second_config, true);

    const file_data = try std.fs.cwd().readFileAlloc(std.testing.allocator, config_path, 1024 * 1024);
    defer std.testing.allocator.free(file_data);

    try std.testing.expect(std.mem.indexOf(u8, file_data, "/srv/jbofs/logical-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, file_data, "/srv/jbofs/raw/disk-b") != null);
}
