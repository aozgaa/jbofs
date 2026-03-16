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
    try writer.interface.flush();
}

fn promptForConfig(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !config.Config {
    const logical_root = try promptWithDefault(allocator, writer, "logical dir", "/srv/jbofs/logical");
    errdefer allocator.free(logical_root);

    const alias_dir = try promptWithDefault(allocator, writer, "root alias dir", "/srv/jbofs/aliases");
    defer allocator.free(alias_dir);

    var roots = std.ArrayList(init_lib.InitRootInput).empty;
    errdefer {
        for (roots.items) |root| {
            allocator.free(root.root_path);
            allocator.free(root.alias);
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
        const default_shortname = try std.fmt.allocPrint(allocator, "disk-{d}", .{index});
        defer allocator.free(default_shortname);
        const default_alias = try std.fs.path.join(allocator, &.{ alias_dir, default_shortname });
        defer allocator.free(default_alias);

        const root_path = try promptRequired(allocator, writer, "root path");
        const alias = try promptWithDefault(allocator, writer, "alias", default_alias);
        const shortname = try promptWithDefault(allocator, writer, "shortname", default_shortname);

        try roots.append(allocator, .{
            .root_path = root_path,
            .alias = alias,
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
            allocator.free(root.alias);
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
        allocator.free(root.alias);
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
