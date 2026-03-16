const std = @import("std");
const cfg = @import("../config.zig");
const pathing = @import("../pathing.zig");
const c = @cImport({
    @cInclude("sys/statvfs.h");
});

pub const CopyOptions = struct {
    disk: ?[]const u8 = null,
    policy: ?cfg.PlacementPolicy = null,
};

pub const FreeSpaceFn = *const fn ([]const u8) anyerror!u64;

pub fn copyManagedFile(
    allocator: std.mem.Allocator,
    config: cfg.Config,
    source_path: []const u8,
    logical_input: []const u8,
    options: CopyOptions,
) !cfg.Root {
    return copyManagedFileWithSelector(allocator, config, source_path, logical_input, options, defaultFreeSpace);
}

pub fn copyManagedFileWithSelector(
    allocator: std.mem.Allocator,
    config: cfg.Config,
    source_path: []const u8,
    logical_input: []const u8,
    options: CopyOptions,
    free_space_fn: FreeSpaceFn,
) !cfg.Root {
    const logical_relative = try pathing.normalizeLogicalPath(allocator, config.logical_root, logical_input);
    defer allocator.free(logical_relative);

    const selected_root = try selectRoot(config, options, free_space_fn);
    const physical_destination = try pathing.joinUnderRoot(allocator, selected_root.root_path, logical_relative);
    defer allocator.free(physical_destination);
    const logical_destination = try pathing.joinUnderRoot(allocator, config.logical_root, logical_relative);
    defer allocator.free(logical_destination);

    if (try pathExists(logical_destination)) return error.DestinationAlreadyExists;

    var source_file = try openFileForRead(source_path);
    defer source_file.close();

    const source_stat = try source_file.stat();
    if (source_stat.kind != .file and source_stat.kind != .named_pipe) {
        return error.InvalidSourceType;
    }

    if (std.fs.path.dirname(physical_destination)) |parent| try std.fs.cwd().makePath(parent);
    if (std.fs.path.dirname(logical_destination)) |parent| try std.fs.cwd().makePath(parent);

    var destination_file = openFileForCreate(physical_destination) catch |err| switch (err) {
        error.PathAlreadyExists => return error.DestinationAlreadyExists,
        else => return err,
    };
    defer destination_file.close();

    try copyFileContents(&source_file, &destination_file);

    std.fs.symLinkAbsolute(physical_destination, logical_destination, .{}) catch |err| {
        deleteFileIfPresent(physical_destination) catch {};
        return switch (err) {
            error.PathAlreadyExists => error.DestinationAlreadyExists,
            else => err,
        };
    };

    return selected_root;
}

fn selectRoot(config: cfg.Config, options: CopyOptions, free_space_fn: FreeSpaceFn) !cfg.Root {
    if (options.disk) |shortname| {
        return cfg.findRootByShortname(config, shortname) orelse error.UnknownRootName;
    }

    const policy = options.policy orelse config.placement.default_policy;
    switch (policy) {
        .first => return config.roots[0],
        .@"most-free" => {
            var best_root = config.roots[0];
            var best_space = try free_space_fn(best_root.root_path);
            for (config.roots[1..]) |root| {
                const candidate_space = try free_space_fn(root.root_path);
                if (candidate_space > best_space) {
                    best_space = candidate_space;
                    best_root = root;
                }
            }
            return best_root;
        },
    }
}

fn copyFileContents(source_file: *std.fs.File, destination_file: *std.fs.File) !void {
    var read_buffer: [8192]u8 = undefined;
    var write_buffer: [8192]u8 = undefined;
    var reader = source_file.reader(&read_buffer);
    var writer = destination_file.writer(&write_buffer);

    _ = try reader.interface.streamRemaining(&writer.interface);
    try writer.interface.flush();
}

fn openFileForRead(file_path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(file_path)) return std.fs.openFileAbsolute(file_path, .{});
    return std.fs.cwd().openFile(file_path, .{});
}

fn openFileForCreate(file_path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(file_path)) {
        return std.fs.createFileAbsolute(file_path, .{
            .exclusive = true,
            .truncate = false,
        });
    }

    return std.fs.cwd().createFile(file_path, .{
        .exclusive = true,
        .truncate = false,
    });
}

fn pathExists(file_path: []const u8) !bool {
    if (std.fs.path.isAbsolute(file_path)) {
        std.posix.access(file_path, std.posix.F_OK) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        if (std.posix.access(file_path, std.posix.F_OK)) |_| return true else |_| {}

        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        _ = std.fs.readLinkAbsolute(file_path, &buffer) catch |err| switch (err) {
            error.FileNotFound => return false,
            error.NotLink => return true,
            else => return true,
        };
        return true;
    }

    if (std.fs.cwd().access(file_path, .{})) |_| return true else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.fs.cwd().readLink(file_path, &buffer) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.NotLink => return true,
        else => return true,
    };
    return true;
}

fn deleteFileIfPresent(file_path: []const u8) !void {
    if (std.fs.path.isAbsolute(file_path)) {
        std.fs.deleteFileAbsolute(file_path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        return;
    }

    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}

fn defaultFreeSpace(path: []const u8) !u64 {
    var stat: c.struct_statvfs = undefined;
    const posix_path = try std.posix.toPosixPath(path);
    if (c.statvfs(&posix_path, &stat) != 0) return error.StatVfsFailed;

    const block_size: u64 = if (stat.f_frsize > 0)
        @intCast(stat.f_frsize)
    else
        @intCast(stat.f_bsize);
    return @as(u64, @intCast(stat.f_bavail)) * block_size;
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
    alias_a: []u8,
    alias_b: []u8,

    fn deinit(self: *OwnedConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.config.roots);
        allocator.free(self.logical_root);
        allocator.free(self.root_a);
        allocator.free(self.root_b);
        allocator.free(self.alias_a);
        allocator.free(self.alias_b);
    }
};

fn makeConfig(allocator: std.mem.Allocator, tmp_root: []const u8) !OwnedConfig {
    const logical_root = try std.fs.path.join(allocator, &.{ tmp_root, "logical" });
    const root_a = try std.fs.path.join(allocator, &.{ tmp_root, "root-a" });
    const root_b = try std.fs.path.join(allocator, &.{ tmp_root, "root-b" });
    const alias_a = try std.fs.path.join(allocator, &.{ tmp_root, "aliases", "disk-0" });
    const alias_b = try std.fs.path.join(allocator, &.{ tmp_root, "aliases", "disk-1" });
    const aliases_dir = try std.fs.path.join(allocator, &.{ tmp_root, "aliases" });
    defer allocator.free(aliases_dir);

    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_a);
    try std.fs.cwd().makePath(root_b);
    try std.fs.cwd().makePath(aliases_dir);

    const roots = try allocator.dupe(cfg.Root, &.{
        .{ .root_path = root_a, .alias = alias_a, .shortname = "disk-0" },
        .{ .root_path = root_b, .alias = alias_b, .shortname = "disk-1" },
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
        .root_b = root_b,
        .alias_a = alias_a,
        .alias_b = alias_b,
    };
}

fn fakeFreeSpace(path: []const u8) !u64 {
    if (std.mem.endsWith(u8, path, "root-a")) return 1;
    if (std.mem.endsWith(u8, path, "root-b")) return 5;
    return 0;
}

test "cp with explicit disk" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "source.txt" });
    defer std.testing.allocator.free(source_path);

    {
        var source = try std.fs.createFileAbsolute(source_path, .{});
        defer source.close();
        try source.writeAll("hello");
    }

    const selected = try copyManagedFile(std.testing.allocator, config, source_path, "media/file.txt", .{ .disk = "disk-1" });
    try std.testing.expectEqualStrings("disk-1", selected.shortname);

    const physical = try std.fs.path.join(std.testing.allocator, &.{ config.roots[1].root_path, "media", "file.txt" });
    defer std.testing.allocator.free(physical);
    const logical = try std.fs.path.join(std.testing.allocator, &.{ config.logical_root, "media", "file.txt" });
    defer std.testing.allocator.free(logical);

    try std.testing.expect(try pathExists(physical));
    try std.testing.expect(try pathExists(logical));
}

test "cp with first policy" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "source.txt" });
    defer std.testing.allocator.free(source_path);

    {
        var source = try std.fs.createFileAbsolute(source_path, .{});
        defer source.close();
        try source.writeAll("hello");
    }

    const selected = try copyManagedFile(std.testing.allocator, config, source_path, "media/first.txt", .{ .policy = .first });
    try std.testing.expectEqualStrings("disk-0", selected.shortname);
}

test "cp with most-free policy" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "source.txt" });
    defer std.testing.allocator.free(source_path);

    {
        var source = try std.fs.createFileAbsolute(source_path, .{});
        defer source.close();
        try source.writeAll("hello");
    }

    const selected = try copyManagedFileWithSelector(std.testing.allocator, config, source_path, "media/free.txt", .{ .policy = .@"most-free" }, fakeFreeSpace);
    try std.testing.expectEqualStrings("disk-1", selected.shortname);
}

test "cp rejects invalid logical path" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "source.txt" });
    defer std.testing.allocator.free(source_path);

    {
        var source = try std.fs.createFileAbsolute(source_path, .{});
        defer source.close();
        try source.writeAll("hello");
    }

    try std.testing.expectError(error.InvalidLogicalPath, copyManagedFile(std.testing.allocator, config, source_path, "../escape.txt", .{}));
}

test "cp rejects existing destination" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    var owned = try makeConfig(std.testing.allocator, tmp_root);
    defer owned.deinit(std.testing.allocator);
    const config = owned.config;
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "source.txt" });
    defer std.testing.allocator.free(source_path);

    {
        var source = try std.fs.createFileAbsolute(source_path, .{});
        defer source.close();
        try source.writeAll("hello");
    }

    _ = try copyManagedFile(std.testing.allocator, config, source_path, "media/file.txt", .{});
    try std.testing.expectError(error.DestinationAlreadyExists, copyManagedFile(std.testing.allocator, config, source_path, "media/file.txt", .{}));
}
