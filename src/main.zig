const std = @import("std");
const cli = @import("cli.zig");
const cp_cmd = @import("commands/cp.zig");
const init_cmd = @import("commands/init.zig");
const prune_cmd = @import("commands/prune.zig");
const query_cmd = @import("commands/query.zig");
const rm_cmd = @import("commands/rm.zig");
const sync_cmd = @import("commands/sync.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed = cli.parseProcess(allocator) catch |err| {
        if (err == error.MissingSubcommand or
            err == error.MissingPositionalArguments or
            err == error.MutuallyExclusiveOptions or
            err == error.InvalidCli)
        {
            return;
        }
        return err;
    };
    defer parsed.deinit(allocator);

    switch (parsed.action) {
        .help_top,
        .help_init,
        .help_cp,
        .help_rm,
        .help_prune,
        .help_sync,
        .help_query,
        .help_query_root_for_shortname,
        => try cli.printHelp(parsed.action),
        .init => |args| try init_cmd.run(allocator, args, parsed.config_override),
        .cp => |args| try cp_cmd.run(allocator, args, parsed.config_override),
        .rm => |args| try rm_cmd.run(allocator, args, parsed.config_override),
        .prune => |args| try prune_cmd.run(allocator, args, parsed.config_override),
        .sync => |args| try sync_cmd.run(allocator, args, parsed.config_override),
        .query_root_for_shortname => |args| try query_cmd.runRootForShortname(allocator, args, parsed.config_override),
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("pathing.zig");
    _ = @import("commands/init.zig");
    _ = @import("commands/cp.zig");
    _ = @import("commands/rm.zig");
    _ = @import("commands/prune.zig");
    _ = @import("commands/query.zig");
    _ = @import("commands/sync.zig");
    _ = @import("lib/init.zig");
    _ = @import("lib/cp.zig");
    _ = @import("lib/rm.zig");
    _ = @import("lib/prune.zig");
    _ = @import("lib/sync.zig");
}
