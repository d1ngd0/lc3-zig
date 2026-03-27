const std = @import("std");
const lc3 = @import("lc3/emulator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var emulator: lc3.Emulator = lc3.Emulator.init();

    while (args.next()) |image| {
        var file = try std.fs.cwd().openFile(image, .{});
        var buf: [512]u8 = undefined;
        emulator.loadImage(&file.reader(&buf).interface);
    }

    emulator.run(args);
}
