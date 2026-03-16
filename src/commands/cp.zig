const std = @import("std");
const cfg = @import("../config.zig");
const cp_lib = @import("../lib/cp.zig");

pub const PolicyName = enum {
    first,
    @"most-free",

    pub fn toPlacementPolicy(self: PolicyName) cfg.PlacementPolicy {
        return switch (self) {
            .first => .first,
            .@"most-free" => .@"most-free",
        };
    }
};

pub const Args = struct {
    disk: ?[]u8,
    policy: ?cfg.PlacementPolicy,
    source: []u8,
    logical_path: []u8,

    pub fn deinit(self: Args, allocator: std.mem.Allocator) void {
        if (self.disk) |disk| allocator.free(disk);
        allocator.free(self.source);
        allocator.free(self.logical_path);
    }
};

pub fn run(allocator: std.mem.Allocator, args: Args, config_override: ?[]const u8) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const config_path = try cfg.resolveConfigPath(allocator, config_override, &env_map);
    defer allocator.free(config_path);

    var parsed = try cfg.loadConfigFile(allocator, config_path);
    defer parsed.deinit();

    _ = try cp_lib.copyManagedFile(allocator, parsed.value, args.source, args.logical_path, .{
        .disk = args.disk,
        .policy = args.policy,
    });
}
