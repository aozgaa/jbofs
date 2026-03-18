const std = @import("std");
const cfg = @import("../config.zig");
const doctor_lib = @import("../lib/doctor.zig");

pub const Args = struct {};

pub fn run(allocator: std.mem.Allocator, _: Args, config_override: ?[]const u8) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const config_path = try cfg.resolveConfigPath(allocator, config_override, &env_map);
    defer allocator.free(config_path);

    var parsed = try cfg.loadConfigFile(allocator, config_path);
    defer parsed.deinit();

    try doctor_lib.run(allocator, parsed.value);
}
