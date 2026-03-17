const std = @import("std");
const clap = @import("clap");
const cp_cmd = @import("commands/cp.zig");
const init_cmd = @import("commands/init.zig");
const prune_cmd = @import("commands/prune.zig");
const query_cmd = @import("commands/query.zig");
const rm_cmd = @import("commands/rm.zig");
const sync_cmd = @import("commands/sync.zig");

pub const Subcommand = enum { init, cp, rm, prune, sync, query };
pub const QuerySubcommand = enum { @"root-for-shortname" };

pub const Action = union(enum) {
    help_top,
    help_init,
    help_cp,
    help_rm,
    help_prune,
    help_sync,
    help_query,
    help_query_root_for_shortname,
    init: init_cmd.Args,
    cp: cp_cmd.Args,
    rm: rm_cmd.Args,
    prune: prune_cmd.Args,
    sync: sync_cmd.Args,
    query_root_for_shortname: query_cmd.RootForShortnameArgs,
};

pub const Parsed = struct {
    config_override: ?[]u8,
    action: Action,

    pub fn deinit(self: Parsed, allocator: std.mem.Allocator) void {
        if (self.config_override) |path| allocator.free(path);
        switch (self.action) {
            .cp => |args| args.deinit(allocator),
            .rm => |args| args.deinit(allocator),
            .query_root_for_shortname => |args| args.deinit(allocator),
            else => {},
        }
    }
};

const top_params = clap.parseParamsComptime(
    \\-h, --help           Display this help and exit.
    \\-c, --config <PATH>  Config file path.
    \\<COMMAND>
    \\
);

const top_parsers = .{
    .PATH = clap.parsers.string,
    .COMMAND = clap.parsers.enumeration(Subcommand),
};

const init_params = clap.parseParamsComptime(
    \\-h, --help   Display this help and exit.
    \\-f, --force  Overwrite an existing config file.
    \\
);

const cp_params = clap.parseParamsComptime(
    \\-h, --help          Display this help and exit.
    \\-d, --disk <NAME>   Explicit physical root shortname.
    \\-p, --policy <POL>  Placement policy.
    \\<SOURCE>
    \\<LOGICAL_PATH>
    \\
);

const cp_parsers = .{
    .NAME = clap.parsers.string,
    .POL = clap.parsers.enumeration(cp_cmd.PolicyName),
    .SOURCE = clap.parsers.string,
    .LOGICAL_PATH = clap.parsers.string,
};

const rm_params = clap.parseParamsComptime(
    \\-h, --help      Display this help and exit.
    \\<LOGICAL_PATH>
    \\
);

const rm_parsers = .{
    .LOGICAL_PATH = clap.parsers.string,
};

const prune_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\
);

const sync_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\
);

const query_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<QUERY>
    \\
);

const query_parsers = .{
    .QUERY = clap.parsers.enumeration(QuerySubcommand),
};

const query_root_for_shortname_params = clap.parseParamsComptime(
    \\-h, --help   Display this help and exit.
    \\<SHORTNAME>
    \\
);

const query_root_for_shortname_parsers = .{
    .SHORTNAME = clap.parsers.string,
};

pub fn parseProcess(allocator: std.mem.Allocator) !Parsed {
    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();
    _ = iter.next();
    return parseIter(allocator, &iter);
}

fn parseIter(allocator: std.mem.Allocator, iter: anytype) !Parsed {
    var diag = clap.Diagnostic{};
    var top = clap.parseEx(clap.Help, &top_params, top_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        try reportCommandParseFailure("jbofs ", clap.Help, &top_params, err, diag);
        return error.InvalidCli;
    };
    defer top.deinit();

    const config_override = if (top.args.config) |path| try allocator.dupe(u8, path) else null;
    errdefer if (config_override) |path| allocator.free(path);

    if (top.args.help != 0 and top.positionals[0] == null) {
        return .{ .config_override = config_override, .action = .help_top };
    }

    const command = top.positionals[0] orelse {
        try printUsageError("missing subcommand", "jbofs ", clap.Help, &top_params);
        return error.MissingSubcommand;
    };

    return switch (command) {
        .init => try parseInit(allocator, iter, config_override),
        .cp => try parseCp(allocator, iter, config_override),
        .rm => try parseRm(allocator, iter, config_override),
        .prune => try parsePrune(allocator, iter, config_override),
        .sync => try parseSync(allocator, iter, config_override),
        .query => try parseQuery(allocator, iter, config_override),
    };
}

fn parseInit(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &init_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs init ", clap.Help, &init_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_init };
    return .{ .config_override = config_override, .action = .{ .init = .{ .force = res.args.force != 0 } } };
}

fn parseCp(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &cp_params, cp_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs cp ", clap.Help, &cp_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_cp };

    const source = res.positionals[0] orelse {
        try printUsageError("missing positional arguments", "jbofs cp ", clap.Help, &cp_params);
        return error.MissingPositionalArguments;
    };
    const logical_path = res.positionals[1] orelse {
        try printUsageError("missing positional arguments", "jbofs cp ", clap.Help, &cp_params);
        return error.MissingPositionalArguments;
    };
    if (res.args.disk != null and res.args.policy != null) {
        try printUsageError("--disk and --policy cannot be used together", "jbofs cp ", clap.Help, &cp_params);
        return error.MutuallyExclusiveOptions;
    }

    return .{
        .config_override = config_override,
        .action = .{
            .cp = .{
                .disk = if (res.args.disk) |disk| try allocator.dupe(u8, disk) else null,
                .policy = if (res.args.policy) |policy| policy.toPlacementPolicy() else null,
                .source = try allocator.dupe(u8, source),
                .logical_path = try allocator.dupe(u8, logical_path),
            },
        },
    };
}

fn parseRm(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &rm_params, rm_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs rm ", clap.Help, &rm_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_rm };

    const logical_path = res.positionals[0] orelse {
        try printUsageError("missing positional arguments", "jbofs rm ", clap.Help, &rm_params);
        return error.MissingPositionalArguments;
    };

    return .{
        .config_override = config_override,
        .action = .{ .rm = .{ .logical_path = try allocator.dupe(u8, logical_path) } },
    };
}

fn parsePrune(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &prune_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs prune ", clap.Help, &prune_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_prune };
    return .{ .config_override = config_override, .action = .{ .prune = .{} } };
}

fn parseSync(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &sync_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs sync ", clap.Help, &sync_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_sync };
    return .{ .config_override = config_override, .action = .{ .sync = .{} } };
}

fn parseQuery(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &query_params, query_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        try reportCommandParseFailure("jbofs query ", clap.Help, &query_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0 and res.positionals[0] == null) {
        return .{ .config_override = config_override, .action = .help_query };
    }

    const command = res.positionals[0] orelse {
        try printUsageError("missing query subcommand", "jbofs query ", clap.Help, &query_params);
        return error.MissingSubcommand;
    };

    return switch (command) {
        .@"root-for-shortname" => try parseQueryRootForShortname(allocator, iter, config_override),
    };
}

fn parseQueryRootForShortname(allocator: std.mem.Allocator, iter: anytype, config_override: ?[]u8) !Parsed {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &query_root_for_shortname_params, query_root_for_shortname_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try reportCommandParseFailure("jbofs query root-for-shortname ", clap.Help, &query_root_for_shortname_params, err, diag);
        return error.InvalidCli;
    };
    defer res.deinit();

    if (res.args.help != 0) return .{ .config_override = config_override, .action = .help_query_root_for_shortname };

    const shortname = res.positionals[0] orelse {
        try printUsageError("missing positional arguments", "jbofs query root-for-shortname ", clap.Help, &query_root_for_shortname_params);
        return error.MissingPositionalArguments;
    };

    return .{
        .config_override = config_override,
        .action = .{
            .query_root_for_shortname = .{
                .shortname = try allocator.dupe(u8, shortname),
            },
        },
    };
}

pub fn printHelp(action: Action) !void {
    const stdout = std.fs.File.stdout();
    var buffer: [2048]u8 = undefined;
    var stdout_writer = stdout.writer(&buffer);

    switch (action) {
        .help_top => {
            try stdout_writer.interface.print("usage: jbofs ", .{});
            try clap.usage(&stdout_writer.interface, clap.Help, &top_params);
            try stdout_writer.interface.writeAll("\n\nsubcommands:\n  init\n  cp\n  rm\n  prune\n  sync\n  query\n");
        },
        .help_init => try printCommandHelp(&stdout_writer.interface, "jbofs init ", &init_params),
        .help_cp => try printCommandHelp(&stdout_writer.interface, "jbofs cp ", &cp_params),
        .help_rm => try printCommandHelp(&stdout_writer.interface, "jbofs rm ", &rm_params),
        .help_prune => try printCommandHelp(&stdout_writer.interface, "jbofs prune ", &prune_params),
        .help_sync => try printCommandHelp(&stdout_writer.interface, "jbofs sync ", &sync_params),
        .help_query => try printRecCommandHelp(&stdout_writer.interface, "jbofs query ", &query_params, "  root-for-shortname\n"),
        .help_query_root_for_shortname => try printCommandHelp(&stdout_writer.interface, "jbofs query root-for-shortname ", &query_root_for_shortname_params),
        else => {},
    }
    try stdout_writer.interface.flush();
}

fn printRecCommandHelp(writer: *std.Io.Writer, prefix: []const u8, params: anytype, subcommands: []const u8) !void {
    try printCommandHelp(writer, prefix, params);
    try writer.print("Subcommands:\n{s}", .{subcommands});
}

fn printCommandHelp(writer: *std.Io.Writer, prefix: []const u8, params: anytype) !void {
    try writer.print("usage: {s}", .{prefix});
    try clap.usage(writer, clap.Help, params);
    try writer.writeAll("\n");
    try clap.help(writer, clap.Help, params, .{});
}

fn reportCommandParseFailure(prefix: []const u8, comptime Id: type, params: []const clap.Param(Id), err: anyerror, diag: clap.Diagnostic) !void {
    try diag.reportToFile(.stderr(), err);
    std.debug.print("usage: {s}", .{prefix});
    try clap.usageToFile(.stderr(), Id, params);
    std.debug.print("\n", .{});
}

fn printUsageError(prefix_msg: []const u8, prefix: []const u8, comptime Id: type, params: []const clap.Param(Id)) !void {
    std.debug.print("error: {s}\nusage: {s}", .{ prefix_msg, prefix });
    try clap.usageToFile(.stderr(), Id, params);
    std.debug.print("\n", .{});
}

fn renderUsageString(allocator: std.mem.Allocator, prefix: []const u8, comptime Id: type, params: []const clap.Param(Id)) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll(prefix);
    try clap.usage(&out.writer, Id, params);
    return allocator.dupe(u8, out.written());
}

pub fn parseForTest(allocator: std.mem.Allocator, cmdline: []const u8) !Parsed {
    var iter = try std.process.ArgIteratorGeneral(.{}).init(allocator, cmdline);
    defer iter.deinit();
    _ = iter.next();
    return parseIter(allocator, &iter);
}

test "parse global config and cp args" {
    const parsed = try parseForTest(std.testing.allocator, "jbofs --config /tmp/j.json cp /tmp/source.txt media/file.txt");
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/tmp/j.json", parsed.config_override.?);
    switch (parsed.action) {
        .cp => |args| {
            try std.testing.expectEqualStrings("/tmp/source.txt", args.source);
            try std.testing.expectEqualStrings("media/file.txt", args.logical_path);
        },
        else => return error.UnexpectedAction,
    }
}

test "parse init force" {
    const parsed = try parseForTest(std.testing.allocator, "jbofs init --force");
    defer parsed.deinit(std.testing.allocator);

    switch (parsed.action) {
        .init => |args| try std.testing.expect(args.force),
        else => return error.UnexpectedAction,
    }
}

test "parse query root-for-shortname args" {
    const parsed = try parseForTest(std.testing.allocator, "jbofs query root-for-shortname disk-0");
    defer parsed.deinit(std.testing.allocator);

    switch (parsed.action) {
        .query_root_for_shortname => |args| try std.testing.expectEqualStrings("disk-0", args.shortname),
        else => return error.UnexpectedAction,
    }
}

test "query usage includes subcommand positional" {
    const usage = try renderUsageString(std.testing.allocator, "jbofs query ", clap.Help, &query_params);
    defer std.testing.allocator.free(usage);
    try std.testing.expect(std.mem.indexOf(u8, usage, "<QUERY>") != null);
}

test "query root-for-shortname usage includes shortname positional" {
    const usage = try renderUsageString(std.testing.allocator, "jbofs query root-for-shortname ", clap.Help, &query_root_for_shortname_params);
    defer std.testing.allocator.free(usage);
    try std.testing.expect(std.mem.indexOf(u8, usage, "<SHORTNAME>") != null);
}

test "query help mentions root-for-shortname subcommand" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    try printRecCommandHelp(&out.writer, "jbofs query ", &query_params, "  root-for-shortname\n");
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "root-for-shortname") != null);
}

test "top level usage mentions command positional" {
    const usage = try renderUsageString(std.testing.allocator, "jbofs ", clap.Help, &top_params);
    defer std.testing.allocator.free(usage);
    try std.testing.expect(std.mem.indexOf(u8, usage, "<COMMAND>") != null);
}

test "cp usage includes source and logical path" {
    const usage = try renderUsageString(std.testing.allocator, "jbofs cp ", clap.Help, &cp_params);
    defer std.testing.allocator.free(usage);
    try std.testing.expect(std.mem.indexOf(u8, usage, "<SOURCE>") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "<LOGICAL_PATH>") != null);
}
