const std = @import("std");
const cfg = @import("../config.zig");
const rm_lib = @import("../lib/rm.zig");

pub const Args = struct {
    logical_path: []u8,

    pub fn deinit(self: Args, allocator: std.mem.Allocator) void {
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

    _ = try rm_lib.removeManagedFile(allocator, parsed.value, args.logical_path);
}
