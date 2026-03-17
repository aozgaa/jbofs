const std = @import("std");

pub const PlacementPolicy = enum {
    first,
    @"most-free",
};

pub const Placement = struct {
    default_policy: PlacementPolicy = .@"most-free",
};

pub const Root = struct {
    root_path: []const u8,
    alias: []const u8,
    shortname: []const u8,
};

pub const Config = struct {
    version: u32,
    logical_root: []const u8,
    roots: []const Root,
    placement: Placement = .{},
};

pub const ParsedConfig = std.json.Parsed(Config);

pub fn parseConfig(allocator: std.mem.Allocator, source: []const u8) !ParsedConfig {
    var parsed = try std.json.parseFromSlice(Config, allocator, source, .{
        .allocate = .alloc_always,
    });
    errdefer parsed.deinit();

    try validateConfig(parsed.value);
    return parsed;
}

pub fn validateConfig(config: Config) !void {
    if (config.version != 1) {
        return error.InvalidVersion;
    }

    if (!std.fs.path.isAbsolute(config.logical_root)) {
        return error.LogicalRootMustBeAbsolute;
    }

    if (config.roots.len == 0) {
        return error.NoRootsConfigured;
    }

    for (config.roots, 0..) |root, i| {
        if (!std.fs.path.isAbsolute(root.root_path)) {
            return error.RootPathMustBeAbsolute;
        }

        if (!std.fs.path.isAbsolute(root.alias)) {
            return error.AliasPathMustBeAbsolute;
        }

        if (root.shortname.len == 0) {
            return error.EmptyRootShortname;
        }

        var j: usize = i + 1;
        while (j < config.roots.len) : (j += 1) {
            const other = config.roots[j];
            if (std.mem.eql(u8, root.shortname, other.shortname)) {
                return error.DuplicateRootShortname;
            }
            if (std.mem.eql(u8, root.root_path, other.root_path)) {
                return error.DuplicateRootPath;
            }
        }
    }
}

pub fn resolveConfigPath(
    allocator: std.mem.Allocator,
    override_path: ?[]const u8,
    env_map: *const std.process.EnvMap,
) ![]u8 {
    if (override_path) |path| {
        return allocator.dupe(u8, path);
    }

    if (env_map.get("JBOFS_CONFIG_PATH")) |path| {
        return allocator.dupe(u8, path);
    }

    if (env_map.get("XDG_CONFIG_HOME")) |path| {
        return std.fs.path.join(allocator, &.{ path, "jbofs", "fs_config.json" });
    }

    const home = env_map.get("HOME") orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".config", "jbofs", "fs_config.json" });
}

pub fn loadConfigFile(allocator: std.mem.Allocator, file_path: []const u8) !ParsedConfig {
    const file_data = if (std.fs.path.isAbsolute(file_path)) blk: {
        var file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
    } else try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);
    defer allocator.free(file_data);

    return parseConfig(allocator, file_data);
}

pub fn findRootByShortname(config: Config, shortname: []const u8) ?Root {
    for (config.roots) |root| {
        if (std.mem.eql(u8, root.shortname, shortname)) return root;
    }
    return null;
}

pub fn stringifyConfig(allocator: std.mem.Allocator, config: Config) ![]u8 {
    try validateConfig(config);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try std.json.Stringify.value(config, .{ .whitespace = .indent_2 }, &out.writer);
    return allocator.dupe(u8, out.written());
}

test "parse valid config with roots" {
    const source =
        \\{
        \\  "version": 1,
        \\  "logical_root": "/srv/jbofs/logical",
        \\  "roots": [
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "alias": "/srv/jbofs/aliases/disk-0",
        \\      "shortname": "disk-0"
        \\    }
        \\  ],
        \\  "placement": {
        \\    "default_policy": "most-free"
        \\  }
        \\}
    ;

    const parsed = try parseConfig(std.testing.allocator, source);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expectEqualStrings("/srv/jbofs/raw/disk-a", parsed.value.roots[0].root_path);
    try std.testing.expectEqual(.@"most-free", parsed.value.placement.default_policy);
}

test "reject duplicate shortname" {
    const source =
        \\{
        \\  "version": 1,
        \\  "logical_root": "/srv/jbofs/logical",
        \\  "roots": [
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "alias": "/srv/jbofs/aliases/disk-0",
        \\      "shortname": "disk-0"
        \\    },
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-b",
        \\      "alias": "/srv/jbofs/aliases/disk-1",
        \\      "shortname": "disk-0"
        \\    }
        \\  ]
        \\}
    ;

    try std.testing.expectError(error.DuplicateRootShortname, parseConfig(std.testing.allocator, source));
}

test "reject duplicate root_path" {
    const source =
        \\{
        \\  "version": 1,
        \\  "logical_root": "/srv/jbofs/logical",
        \\  "roots": [
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "alias": "/srv/jbofs/aliases/disk-0",
        \\      "shortname": "disk-0"
        \\    },
        \\    {
        \\      "root_path": "/srv/jbofs/raw/disk-a",
        \\      "alias": "/srv/jbofs/aliases/disk-1",
        \\      "shortname": "disk-1"
        \\    }
        \\  ]
        \\}
    ;

    try std.testing.expectError(error.DuplicateRootPath, parseConfig(std.testing.allocator, source));
}

test "resolve config path precedence" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("HOME", "/home/tester");
    try env_map.put("XDG_CONFIG_HOME", "/tmp/xdg");
    try env_map.put("JBOFS_CONFIG_PATH", "/tmp/jbofs.json");

    const explicit = try resolveConfigPath(std.testing.allocator, "/tmp/override.json", &env_map);
    defer std.testing.allocator.free(explicit);
    try std.testing.expectEqualStrings("/tmp/override.json", explicit);

    const from_env = try resolveConfigPath(std.testing.allocator, null, &env_map);
    defer std.testing.allocator.free(from_env);
    try std.testing.expectEqualStrings("/tmp/jbofs.json", from_env);

    _ = env_map.remove("JBOFS_CONFIG_PATH");
    const from_xdg = try resolveConfigPath(std.testing.allocator, null, &env_map);
    defer std.testing.allocator.free(from_xdg);
    try std.testing.expectEqualStrings("/tmp/xdg/jbofs/fs_config.json", from_xdg);

    _ = env_map.remove("XDG_CONFIG_HOME");
    const from_home = try resolveConfigPath(std.testing.allocator, null, &env_map);
    defer std.testing.allocator.free(from_home);
    try std.testing.expectEqualStrings("/home/tester/.config/jbofs/fs_config.json", from_home);
}

test "stringify config produces root_path schema" {
    const config = Config{
        .version = 1,
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .alias = "/srv/jbofs/aliases/disk-0",
                .shortname = "disk-0",
            },
        },
        .placement = .{ .default_policy = .first },
    };

    const output = try stringifyConfig(std.testing.allocator, config);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"roots\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"root_path\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"first\"") != null);
}

test "find root by shortname returns configured root" {
    const config = Config{
        .version = 1,
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .alias = "/srv/jbofs/aliases/disk-0",
                .shortname = "disk-0",
            },
            .{
                .root_path = "/srv/jbofs/raw/disk-b",
                .alias = "/srv/jbofs/aliases/disk-1",
                .shortname = "disk-1",
            },
        },
    };

    const root = findRootByShortname(config, "disk-1") orelse return error.ExpectedRoot;
    try std.testing.expectEqualStrings("/srv/jbofs/raw/disk-b", root.root_path);
}

test "find root by shortname returns null when missing" {
    const config = Config{
        .version = 1,
        .logical_root = "/srv/jbofs/logical",
        .roots = &.{
            .{
                .root_path = "/srv/jbofs/raw/disk-a",
                .alias = "/srv/jbofs/aliases/disk-0",
                .shortname = "disk-0",
            },
        },
    };

    try std.testing.expect(findRootByShortname(config, "disk-9") == null);
}
