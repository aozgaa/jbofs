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
    created_with_sudo,
    failed: anyerror,
};

pub const CreateDirsResult = struct {
    logical_root: DirStatus,

    pub fn deinit(self: CreateDirsResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Function type for the sudo-escalation retry.  Injected so tests can
/// replace the real implementation without actually spawning sudo.
pub const SudoFn = *const fn (
    allocator: std.mem.Allocator,
    path: []const u8,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
) anyerror!void;

/// Default implementation: spawns `sudo install -d -o <uid> -g <gid> -m 755 <path>`.
pub fn defaultSudoInstall(
    allocator: std.mem.Allocator,
    path: []const u8,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
) !void {
    const uid_str = try std.fmt.allocPrint(allocator, "{d}", .{uid});
    defer allocator.free(uid_str);
    const gid_str = try std.fmt.allocPrint(allocator, "{d}", .{gid});
    defer allocator.free(gid_str);

    var child = std.process.Child.init(
        &.{ "sudo", "install", "-d", "-o", uid_str, "-g", gid_str, "-m", "755", path },
        allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.SudoInstallFailed,
        else => return error.SudoInstallFailed,
    }
}

pub fn createRequiredDirectories(
    allocator: std.mem.Allocator,
    config: cfg.Config,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
) !CreateDirsResult {
    return createRequiredDirectoriesWithSudo(allocator, config, uid, gid, defaultSudoInstall);
}

pub fn createRequiredDirectoriesWithSudo(
    allocator: std.mem.Allocator,
    config: cfg.Config,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
    sudo_fn: SudoFn,
) !CreateDirsResult {
    // Physical roots are pre-existing mounted drives; never create them.
    // Verify each one is present and is a directory.
    for (config.roots) |root| {
        var dir = std.fs.openDirAbsolute(root.root_path, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return error.RootPathDoesNotExist,
            else => return err,
        };
        dir.close();
    }

    const logical_root_status = makeDirWithFallback(allocator, config.logical_root, uid, gid, sudo_fn);

    return .{
        .logical_root = logical_root_status,
    };
}

fn makeDirWithFallback(
    allocator: std.mem.Allocator,
    path: []const u8,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
    sudo_fn: SudoFn,
) DirStatus {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.AccessDenied => {
            sudo_fn(allocator, path, uid, gid) catch {
                return .{ .failed = err };
            };
            return .created_with_sudo;
        },
        else => return .{ .failed = err },
    };
    return .ok;
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

test "createRequiredDirectories creates logical root and accepts existing physical roots" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    // Physical root must already exist (pre-existing mounted drive).
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config, std.posix.getuid(), std.os.linux.getgid());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
}

test "createRequiredDirectories logical_root ok when it already exists" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);

    // Both exist beforehand.
    try std.fs.cwd().makePath(logical_root);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config, std.posix.getuid(), std.os.linux.getgid());
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
}

test "createRequiredDirectories returns error when a root_path is missing" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    // root_path intentionally NOT created.
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    try std.testing.expectError(
        error.RootPathDoesNotExist,
        createRequiredDirectories(std.testing.allocator, config, std.posix.getuid(), std.os.linux.getgid()),
    );
}

test "createRequiredDirectories returns failed when logical_root path is a file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    // Place a file where logical_root should be so makePath fails.
    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical-file" });
    defer std.testing.allocator.free(logical_root);
    const blocker = try std.fs.createFileAbsolute(logical_root, .{});
    blocker.close();

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{
            .{ .root_path = root_path, .shortname = "disk-0" },
        },
    });

    const result = try createRequiredDirectories(std.testing.allocator, config, std.posix.getuid(), std.os.linux.getgid());
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.logical_root == .failed);
}

test "createRequiredDirectoriesWithSudo does not call sudo_fn when makePath succeeds" {
    // Verify that the sudo_fn is not invoked when makePath succeeds normally.
    const neverCalledSudo = struct {
        fn call(
            alloc: std.mem.Allocator,
            path: []const u8,
            uid: std.posix.uid_t,
            gid: std.posix.gid_t,
        ) anyerror!void {
            _ = alloc;
            _ = path;
            _ = uid;
            _ = gid;
            return error.SudoShouldNotHaveBeenCalled;
        }
    }.call;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "logical" });
    defer std.testing.allocator.free(logical_root);

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{.{ .root_path = root_path, .shortname = "disk-0" }},
    });

    const result = try createRequiredDirectoriesWithSudo(
        std.testing.allocator,
        config,
        std.posix.getuid(),
        std.os.linux.getgid(),
        neverCalledSudo,
    );
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(DirStatus.ok, result.logical_root);
}

test "createRequiredDirectoriesWithSudo returns failed for non-AccessDenied logical_root error" {
    // Verify: non-AccessDenied error on logical_root -> .failed; sudo not invoked.
    const neverCalledSudo = struct {
        fn call(
            alloc: std.mem.Allocator,
            path: []const u8,
            uid: std.posix.uid_t,
            gid: std.posix.gid_t,
        ) anyerror!void {
            _ = alloc;
            _ = path;
            _ = uid;
            _ = gid;
            return error.SudoShouldNotHaveBeenCalled;
        }
    }.call;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    // Place a file where logical_root should be so makePath returns NotDir, not AccessDenied.
    const logical_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "blocker" });
    defer std.testing.allocator.free(logical_root);
    const f = try std.fs.createFileAbsolute(logical_root, .{});
    f.close();

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "raw", "disk-a" });
    defer std.testing.allocator.free(root_path);
    try std.fs.cwd().makePath(root_path);

    const config = try buildConfig(.{
        .logical_root = logical_root,
        .roots = &.{.{ .root_path = root_path, .shortname = "disk-0" }},
    });

    const result = try createRequiredDirectoriesWithSudo(
        std.testing.allocator,
        config,
        std.posix.getuid(),
        std.os.linux.getgid(),
        neverCalledSudo,
    );
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.logical_root == .failed);
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
