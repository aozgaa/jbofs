const std = @import("std");

pub fn validateLogicalRelativePath(path: []const u8) !void {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) {
        return error.InvalidLogicalPath;
    }

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return error.InvalidLogicalPath;
        }
    }
}

pub fn normalizeLogicalPath(
    allocator: std.mem.Allocator,
    logical_root: []const u8,
    input_path: []const u8,
) ![]u8 {
    if (!std.fs.path.isAbsolute(logical_root)) {
        return error.InvalidLogicalRoot;
    }

    if (!std.fs.path.isAbsolute(input_path)) {
        try validateLogicalRelativePath(input_path);
        return allocator.dupe(u8, input_path);
    }

    const resolved_root = try std.fs.path.resolve(allocator, &.{logical_root});
    defer allocator.free(resolved_root);

    const resolved_input = try std.fs.path.resolve(allocator, &.{input_path});
    defer allocator.free(resolved_input);

    if (!isSubPath(resolved_input, resolved_root)) {
        return error.InvalidLogicalPath;
    }

    if (resolved_input.len == resolved_root.len) {
        return error.InvalidLogicalPath;
    }

    const start = if (resolved_root[resolved_root.len - 1] == std.fs.path.sep) resolved_root.len else resolved_root.len + 1;
    const relative = resolved_input[start..];
    try validateLogicalRelativePath(relative);
    return allocator.dupe(u8, relative);
}

pub fn isPathWithinRoot(
    allocator: std.mem.Allocator,
    candidate_path: []const u8,
    root_path: []const u8,
) !bool {
    const resolved_candidate = try std.fs.path.resolve(allocator, &.{candidate_path});
    defer allocator.free(resolved_candidate);

    const resolved_root = try std.fs.path.resolve(allocator, &.{root_path});
    defer allocator.free(resolved_root);

    return isSubPath(resolved_candidate, resolved_root);
}

pub fn joinUnderRoot(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    relative_path: []const u8,
) ![]u8 {
    try validateLogicalRelativePath(relative_path);
    return std.fs.path.join(allocator, &.{ root_path, relative_path });
}

fn isSubPath(candidate: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, candidate, root)) return false;
    if (candidate.len == root.len) return true;
    return candidate[root.len] == std.fs.path.sep;
}

test "reject invalid logical relative path" {
    try std.testing.expectError(error.InvalidLogicalPath, validateLogicalRelativePath("../escape.txt"));
    try std.testing.expectError(error.InvalidLogicalPath, validateLogicalRelativePath("/absolute.txt"));
}

test "accept absolute logical path only when under logical root" {
    const relative = try normalizeLogicalPath(std.testing.allocator, "/srv/jbofs/logical", "/srv/jbofs/logical/media/file.txt");
    defer std.testing.allocator.free(relative);

    try std.testing.expectEqualStrings("media/file.txt", relative);
    try std.testing.expectError(error.InvalidLogicalPath, normalizeLogicalPath(std.testing.allocator, "/srv/jbofs/logical", "/tmp/file.txt"));
}

test "detect whether path is inside configured physical root" {
    try std.testing.expect(try isPathWithinRoot(std.testing.allocator, "/srv/jbofs/raw/disk-a/media/file.txt", "/srv/jbofs/raw/disk-a"));
    try std.testing.expect(!(try isPathWithinRoot(std.testing.allocator, "/srv/jbofs/raw/disk-b/media/file.txt", "/srv/jbofs/raw/disk-a")));
}

test "relative logical path stays relative" {
    const relative = try normalizeLogicalPath(std.testing.allocator, "/srv/jbofs/logical", "media/file.txt");
    defer std.testing.allocator.free(relative);

    try std.testing.expectEqualStrings("media/file.txt", relative);
}

test "join under root appends validated relative path" {
    const joined = try joinUnderRoot(std.testing.allocator, "/srv/jbofs/logical", "media/file.txt");
    defer std.testing.allocator.free(joined);

    try std.testing.expectEqualStrings("/srv/jbofs/logical/media/file.txt", joined);
}
