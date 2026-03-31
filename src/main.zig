const std = @import("std");
const lc3 = @import("lc3/emulator.zig");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    var rbuf: [1024]u8 = undefined;
    var wbuf: [1024]u8 = undefined;

    var emulator = try lc3.Emulator.initStd(init.io, &rbuf, &wbuf);

    _ = args.skip();
    while (args.next()) |image| {
        var file = try std.Io.Dir.cwd().openFile(init.io, image, .{});
        var buf: [512]u8 = undefined;
        var reader = file.reader(init.io, &buf);
        try emulator.loadImage(&reader.interface);
    }

    try emulator.run();
}
