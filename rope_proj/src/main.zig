const std = @import("std");
const lib = @import("rope_proj_lib");
const testing = std.testing;

const Atomic = std.atomic.Value;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const RwLock = Thread.RwrLock;
const Pool = Thread.Pool;

const Rope = lib.Rope.Rope;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var myRope = Rope.init(allocator);
    defer myRope.deinit();
    // myRope.init(allocator);

    try myRope.build("Hello There here is a big \n world That I know \nisn't well appreciated");
    const large_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ** 100;

    try myRope.append(large_text);
    try myRope.delete(200, 5500);
    try myRope.rebalance();
    try myRope.insert(5, " wonderful");
    // inline for (0..5) |_| {
    for (0..5) |_| {
        try myRope.append("Hello ");
    }

    const mystr = try myRope.collectLeaves(allocator);
    defer allocator.free(mystr);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{mystr});

    try stdout.print("\n", .{});
    myRope.report();
    try stdout.print("\n", .{});

    const my_pattern: []const u8 = "Hello";
    try stdout.print("Attempting to find pattern:{s}\n", .{my_pattern});
    if (myRope.find(my_pattern)) |pattern_index| {
        try stdout.print("Pattern was first found at index:{d}\n", .{pattern_index});
        const pattern_idx_slice = try myRope.findAll(my_pattern, allocator);
        defer allocator.free(pattern_idx_slice);

        try stdout.print("Pattern was first found at indexes:", .{});
        for (pattern_idx_slice) |idx| {
            try stdout.print("{d},", .{idx});
        }
        try stdout.print("\n", .{});

        for (0..my_pattern.len) |pattern_char| {
            if (myRope.index(pattern_index + pattern_char)) |char| {
                try stdout.print("{c}", .{char});
            }
        }
        try stdout.print("\n", .{});
        try stdout.print("\n", .{});
        try stdout.print("Since pattern was found attemp to replace\n", .{});
        const replace_pattern = "universe";
        const replace_count = try myRope.replace(my_pattern, replace_pattern);
        try stdout.print("Pattern was replaced:{d} # times\n", .{replace_count});
        const mystr2 = try myRope.collectLeaves(allocator);
        defer allocator.free(mystr2);
        try stdout.print("data now = {s}\n", .{mystr2});

        try stdout.print("\nAttempt a single replace at pos 0 by switching {s} for {s}\n", .{ replace_pattern, my_pattern });
        try myRope.replaceIndex(replace_pattern, my_pattern, 0);
        const mystr3 = try myRope.collectLeaves(allocator);
        defer allocator.free(mystr3);
        try stdout.print("data after single index replace :\n {s}\n", .{mystr3});
    } else {
        try stdout.print("couldn't find pattern\n", .{});
    }

    try stdout.print("\n", .{});

    try stdout.print("MyRope:\n", .{});
    myRope.report();
    try stdout.print("\n", .{});
    try stdout.print("Attempt a split at index 90, and make other Rope with data from split  \n", .{});

    const otherNode: ?*Rope.Node = try myRope.split(90);
    var otherRope = Rope.init(allocator);
    defer otherRope.deinit();

    try stdout.print("MyRope:\n", .{});
    myRope.report();
    try stdout.print("\n", .{});

    if (otherNode) |node| {
        try otherRope.concat(node);
        try stdout.print("otherRope:\n", .{});
        otherRope.report();
        try stdout.print("\n", .{});
    }

    try myRope.rebalance();
    try stdout.print("MyRope:\n", .{});
    myRope.report();
    try stdout.print("\n", .{});

    try otherRope.rebalance();
    try stdout.print("otherRope:\n", .{});
    otherRope.report();
    try stdout.print("\n", .{});

    // test iter
    var myRope_iter = myRope.iterator();
    for (0..myRope.len()) |_| {
        if (myRope_iter.next()) |char| {
            try stdout.print("{c}", .{char});
        }
    }

    try stdout.print("\n", .{});
    try stdout.print("\n", .{});

    var otherRope_iter = otherRope.iterator();
    for (0..otherRope.len()) |_| {
        if (otherRope_iter.next()) |char| {
            try stdout.print("{c}", .{char});
        }
    }
    try stdout.print("\n", .{});
}
