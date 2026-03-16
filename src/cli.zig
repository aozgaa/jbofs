const std = @import("std");
const clap = @import("clap");
const cp_cmd = @import("commands/cp.zig");
const init_cmd = @import("commands/init.zig");
const prune_cmd = @import("commands/prune.zig");
const rm_cmd = @import("commands/rm.zig");
const sync_cmd = @import("commands/sync.zig");

pub const Subcommand = enum { init, cp, rm, prune, sync };

pub const Action = union(enum) {
    help_top,
    help_init,
    help_cp,
    help_rm,
    help_prune,
    help_sync,
    init: init_cmd.Args,
    cp: cp_cmd.Args,
    rm: rm_cmd.Args,
    prune: prune_cmd.Args,
    sync: sync_cmd.Args,
};

pub const Parsed = struct {
    config_override: ?[]u8,
    action: Action,

    pub fn deinit(self: Parsed, allocator: std.mem.Allocator) void {
        if (self.config_override) |path| allocator.free(path);
        switch (self.action) {
            .cp => |args| args.deinit(allocator),
            .rm => |args| args.deinit(allocator),
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

pub fn printHelp(action: Action) !void {
    switch (action) {
        .help_top => {
            std.debug.print("usage: jbofs ", .{});
            try clap.usageToFile(.stderr(), clap.Help, &top_params);
            std.debug.print("\n\nsubcommands:\n  init\n  cp\n  rm\n  prune\n  sync\n", .{});
        },
        .help_init => try printCommandHelp("jbofs init ", &init_params),
        .help_cp => try printCommandHelp("jbofs cp ", &cp_params),
        .help_rm => try printCommandHelp("jbofs rm ", &rm_params),
        .help_prune => try printCommandHelp("jbofs prune ", &prune_params),
        .help_sync => try printCommandHelp("jbofs sync ", &sync_params),
        else => {},
    }
}

fn printCommandHelp(prefix: []const u8, params: anytype) !void {
    std.debug.print("usage: {s}", .{prefix});
    try clap.usageToFile(.stderr(), clap.Help, params);
    std.debug.print("\n", .{});
    try clap.helpToFile(.stderr(), clap.Help, params, .{});
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

pub fn renderUsageString(allocator: std.mem.Allocator, prefix: []const u8, comptime Id: type, params: []const clap.Param(Id)) ![]u8 {
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
