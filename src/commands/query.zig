const std = @import("std");
const cfg = @import("../config.zig");

pub const RootForShortnameArgs = struct {
    shortname: []u8,

    pub fn deinit(self: RootForShortnameArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.shortname);
    }
};

pub fn runRootForShortname(allocator: std.mem.Allocator, args: RootForShortnameArgs, config_override: ?[]const u8) !void {
    const stdout = std.fs.File.stdout();
    var buffer: [1024]u8 = undefined;
    var stdout_writer = stdout.writer(&buffer);
    try runRootForShortnameWithWriter(allocator, &stdout_writer.interface, args, config_override);
    try stdout_writer.interface.flush();
}

pub fn runRootForShortnameWithWriter(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    args: RootForShortnameArgs,
    config_override: ?[]const u8,
) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const config_path = try cfg.resolveConfigPath(allocator, config_override, &env_map);
    defer allocator.free(config_path);

    var parsed = try cfg.loadConfigFile(allocator, config_path);
    defer parsed.deinit();

    const root = cfg.findRootByShortname(parsed.value, args.shortname) orelse return error.UnknownRootName;
    try writer.writeAll(root.root_path);
    try writer.writeAll("\n");
}

fn tmpDirPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir) ![]u8 {
    const relative = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(relative);
    return std.fs.cwd().realpathAlloc(allocator, relative);
}

test "query root-for-shortname prints configured root path" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const config_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "fs_config.json" });
    defer std.testing.allocator.free(config_path);

    const config_source =
        \\{
        \\  "version": 2,
        \\  "logical_root": "/srv/jbofs/logical",
        \\  "roots": [
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "shortname": "disk-0"
        \\    },
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-b",
        \\      "shortname": "disk-1"
        \\    }
        \\  ]
        \\}
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = config_path, .data = config_source });

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    const args = RootForShortnameArgs{ .shortname = try std.testing.allocator.dupe(u8, "disk-1") };
    defer args.deinit(std.testing.allocator);

    try runRootForShortnameWithWriter(std.testing.allocator, &output.writer, args, config_path);
    try std.testing.expectEqualStrings("/srv/jbofs/raw/disk-b\n", output.written());
}

test "query root-for-shortname returns unknown root name for missing shortname" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const config_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "fs_config.json" });
    defer std.testing.allocator.free(config_path);

    const config_source =
        \\{
        \\  "version": 2,
        \\  "logical_root": "/srv/jbofs/logical",
        \\  "roots": [
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "shortname": "disk-0"
        \\    }
        \\  ]
        \\}
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = config_path, .data = config_source });

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    const args = RootForShortnameArgs{ .shortname = try std.testing.allocator.dupe(u8, "disk-9") };
    defer args.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnknownRootName,
        runRootForShortnameWithWriter(std.testing.allocator, &output.writer, args, config_path),
    );
}
