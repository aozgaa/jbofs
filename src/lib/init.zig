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
