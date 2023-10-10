const std = @import("std");
const io = std.io;
const clap = @import("clap");
const KSUID = @import("./KSUID.zig");

pub fn main() void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Print help
        \\-n, --number <usize>  Number of KSUIDs to generate (default 1)
        \\
    );

    var diag = clap.Diagnostic{};
    const res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        std.os.exit(2);
    };
    defer res.deinit();

    if (res.args.help != 0) {
        clap.help(io.getStdErr().writer(), clap.Help, &params, .{}) catch {};
        return;
    }
    const number = res.args.number orelse 1;

    const stdout_file = io.getStdOut().writer();
    var bw = io.bufferedWriter(stdout_file);
    defer bw.flush() catch {};
    const stdout = bw.writer();

    var buf: [27]u8 = undefined;
    for (0..number) |_| {
        KSUID.init().encodeToString(&buf);
        stdout.print("{s}\n", .{buf}) catch unreachable;
    }
}
