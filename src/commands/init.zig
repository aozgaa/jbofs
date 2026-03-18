const std = @import("std");
const config = @import("../config.zig");
const init_lib = @import("../lib/init.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

pub const Args = struct {
    force: bool,
};

pub const RootPromptFields = struct {
    root_path_label: []const u8 = "root path",
    shortname_label: []const u8 = "shortname",
};

pub fn run(allocator: std.mem.Allocator, args: Args, config_override: ?[]const u8) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const config_path = try config.resolveConfigPath(allocator, config_override, &env_map);
    defer allocator.free(config_path);

    const stdout = std.fs.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&stdout_buffer);

    const built = try promptForConfig(allocator, &writer.interface);
    defer freeOwnedConfig(allocator, built);

    try init_lib.writeConfigFile(allocator, config_path, built, args.force);
    try writer.interface.print("wrote config to {s}\n", .{config_path});

    const dirs_result = try init_lib.createRequiredDirectories(allocator, built);
    defer dirs_result.deinit(allocator);

    switch (dirs_result.logical_root) {
        .ok => try writer.interface.print("created {s}\n", .{built.logical_root}),
        .failed => |err| try writer.interface.print(
            "warning: could not create {s}: {s} (create it manually)\n",
            .{ built.logical_root, @errorName(err) },
        ),
    }

    for (built.roots, dirs_result.roots) |root, status| {
        switch (status) {
            .ok => try writer.interface.print("created {s}\n", .{root.root_path}),
            .failed => |err| try writer.interface.print(
                "warning: could not create {s}: {s} (create it manually)\n",
                .{ root.root_path, @errorName(err) },
            ),
        }
    }

    try writer.interface.flush();
}

pub fn defaultShortnameForIndex(allocator: std.mem.Allocator, index: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "disk-{d}", .{index});
}

pub fn rootPromptFields() RootPromptFields {
    return .{};
}

pub fn validateRootPath(path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) return error.RootPathMustBeAbsolute;
    var dir = std.fs.openDirAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.RootPathDoesNotExist,
        else => return err,
    };
    dir.close();
}

fn promptForConfig(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !config.Config {
    const logical_root = try promptWithDefault(allocator, writer, "logical dir", "/srv/jbofs/logical");
    errdefer allocator.free(logical_root);

    var roots = std.ArrayList(init_lib.InitRootInput).empty;
    errdefer {
        for (roots.items) |root| {
            allocator.free(root.root_path);
            allocator.free(root.shortname);
        }
        roots.deinit(allocator);
    }

    while (true) {
        const add_more = try promptWithDefault(allocator, writer, "add a physical root? [Y/n]", "y");
        defer allocator.free(add_more);

        if (std.ascii.eqlIgnoreCase(add_more, "n") or std.ascii.eqlIgnoreCase(add_more, "no")) {
            if (roots.items.len == 0) {
                try writer.print("at least one physical root is required\n", .{});
                try writer.flush();
                continue;
            }
            break;
        }

        const index = roots.items.len;
        const default_shortname = try defaultShortnameForIndex(allocator, index);
        defer allocator.free(default_shortname);

        const prompt_fields = rootPromptFields();
        const root_path = blk: while (true) {
            const candidate = try promptRequired(allocator, writer, prompt_fields.root_path_label);
            if (validateRootPath(candidate)) |_| {
                break :blk candidate;
            } else |_| {
                try writer.print("{s}: directory does not exist\n", .{candidate});
                try writer.flush();
                allocator.free(candidate);
            }
        };

        const shortname = try promptWithDefault(allocator, writer, prompt_fields.shortname_label, default_shortname);

        try roots.append(allocator, .{
            .root_path = root_path,
            .shortname = shortname,
        });
    }

    const placement = try promptWithDefault(allocator, writer, "placement policy (most-free|first)", "most-free");
    defer allocator.free(placement);

    const policy = if (std.mem.eql(u8, placement, "first"))
        config.PlacementPolicy.first
    else if (std.mem.eql(u8, placement, "most-free"))
        config.PlacementPolicy.@"most-free"
    else
        return error.UnknownPolicy;

    const owned_roots = try roots.toOwnedSlice(allocator);
    errdefer {
        for (owned_roots) |root| {
            allocator.free(root.root_path);
            allocator.free(root.shortname);
        }
        allocator.free(owned_roots);
    }

    const built = try init_lib.buildConfig(.{
        .logical_root = logical_root,
        .roots = owned_roots,
        .default_policy = policy,
    });
    try config.validateConfig(built);
    return built;
}

fn promptRequired(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    label: []const u8,
) ![]u8 {
    while (true) {
        const value = try promptWithDefault(allocator, writer, label, "");
        if (value.len > 0) return value;
        allocator.free(value);
        try writer.print("{s} is required\n", .{label});
        try writer.flush();
    }
}

fn promptWithDefault(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    label: []const u8,
    default_value: []const u8,
) ![]u8 {
    if (default_value.len > 0) {
        try writer.print("{s} [{s}]: ", .{ label, default_value });
    } else {
        try writer.print("{s}: ", .{label});
    }
    try writer.flush();

    const line = try readLineAlloc(allocator);
    defer allocator.free(line);

    return normalizePromptValue(allocator, line, default_value);
}

fn readLineAlloc(allocator: std.mem.Allocator) ![]u8 {
    var line_ptr: [*c]u8 = null;
    defer if (line_ptr != null) c.free(line_ptr);

    var capacity: usize = 0;
    const line_len = c.getline(&line_ptr, &capacity, c.stdin);
    if (line_len < 0) return error.EndOfStream;

    return allocator.dupe(u8, line_ptr[0..@intCast(line_len)]);
}

fn normalizePromptValue(
    allocator: std.mem.Allocator,
    line: []const u8,
    default_value: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, line, " \r\t\n");
    if (trimmed.len == 0) return allocator.dupe(u8, default_value);
    return allocator.dupe(u8, trimmed);
}

fn freeOwnedConfig(allocator: std.mem.Allocator, built: config.Config) void {
    allocator.free(built.logical_root);
    for (built.roots) |root| {
        allocator.free(root.root_path);
        allocator.free(root.shortname);
    }
    allocator.free(built.roots);
}

test "normalize prompt value uses default for blank line" {
    const value = try normalizePromptValue(std.testing.allocator, "\n", "default");
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("default", value);
}

test "normalize prompt value strips newline from explicit input" {
    const value = try normalizePromptValue(std.testing.allocator, "n\n", "");
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("n", value);
}

test "normalize prompt value strips surrounding spaces" {
    const value = try normalizePromptValue(std.testing.allocator, "  no \n", "");
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("no", value);
}

test "default shortname for index uses disk prefix" {
    const zero = try defaultShortnameForIndex(std.testing.allocator, 0);
    defer std.testing.allocator.free(zero);
    try std.testing.expectEqualStrings("disk-0", zero);

    const three = try defaultShortnameForIndex(std.testing.allocator, 3);
    defer std.testing.allocator.free(three);
    try std.testing.expectEqualStrings("disk-3", three);
}

test "root prompt fields omit alias" {
    const fields = rootPromptFields();
    try std.testing.expectEqualStrings("root path", fields.root_path_label);
    try std.testing.expectEqualStrings("shortname", fields.shortname_label);
}

fn tmpDirPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir) ![]u8 {
    const relative = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(relative);
    return std.fs.cwd().realpathAlloc(allocator, relative);
}

test "validateRootPath accepts existing directory" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    try validateRootPath(tmp_root);
}

test "validateRootPath rejects non-existent path" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try tmpDirPath(std.testing.allocator, &tmp_dir);
    defer std.testing.allocator.free(tmp_root);

    const missing = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "does-not-exist" });
    defer std.testing.allocator.free(missing);

    try std.testing.expectError(error.RootPathDoesNotExist, validateRootPath(missing));
}

test "validateRootPath rejects relative path" {
    try std.testing.expectError(error.RootPathMustBeAbsolute, validateRootPath("relative/path"));
}
