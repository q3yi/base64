const std = @import("std");
const mem = std.mem;
const base64 = @import("base64");
const zon = @import("build.zig.zon");

pub fn main(init: std.process.Init) void {
    const allocator = init.gpa;
    const io = init.io;

    var args_iter = std.process.Args.Iterator.initAllocator(init.minimal.args, allocator) catch {
        std.debug.print("base64: out of memory\n", .{});
        std.process.exit(1);
    };
    defer args_iter.deinit();
    _ = args_iter.next();

    var args = CmdArgs.parse(allocator, io, &args_iter) catch |err| switch (err) {
        error.InvalidArgs => exitWithError("invalid args"),
        error.InvalidWrapCols => exitWithError("invalid wrap cols"),
        else => exitWithError("parse args failed"),
    };
    defer args.deinit(allocator);

    var input_file: std.Io.File = undefined;
    if (args.file) |file| {
        input_file = std.Io.Dir.cwd().openFile(io, file, .{}) catch {
            std.debug.print("base64: fail to open file {s}", .{file});
            std.process.exit(1);
        };
    } else {
        input_file = std.Io.File.stdin();
    }
    defer input_file.close(io);

    var read_buf: [1024]u8 = undefined;
    var file_reader = input_file.reader(io, &read_buf);
    const reader = &file_reader.interface;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    if (args.decode) {
        base64.decode(reader, stdout, args.ignore_garbage) catch |err| switch (err) {
            base64.DecodeError.NonAlphabet => exitWithError("non alphabet"),
            base64.DecodeError.InvalidInput => exitWithError("invalid input"),
            else => exitWithError("io error"),
        };
    } else {
        base64.encode(reader, stdout, args.wrap) catch exitWithError("io error");
    }
}

const CmdArgs = struct {
    wrap: usize = 76,
    file: ?[]u8 = null,
    decode: bool = false,
    ignore_garbage: bool = false,

    fn parse(allocator: mem.Allocator, io: std.Io, args_iter: *std.process.Args.Iterator) !CmdArgs {
        var self: CmdArgs = .{};
        while (args_iter.next()) |arg| {
            if (mem.eql(u8, "-d", arg) or mem.eql(u8, "--decode", arg)) {
                self.decode = true;
            } else if (mem.eql(u8, "-i", arg) or mem.eql(u8, "--ignore-garbage", arg)) {
                self.ignore_garbage = true;
            } else if (mem.eql(u8, "-w", arg) or mem.eql(u8, "--wrap", arg)) {
                const val = args_iter.next() orelse return error.InvalidWrapCols;
                self.wrap = std.fmt.parseInt(usize, val, 10) catch return error.InvalidWrapCols;
            } else if (mem.startsWith(u8, arg, "-w")) {
                self.wrap = std.fmt.parseInt(usize, arg[2..], 10) catch return error.InvalidWrapCols;
            } else if (mem.startsWith(u8, arg, "--wrap=")) {
                self.wrap = std.fmt.parseInt(usize, arg[7..], 10) catch return error.InvalidWrapCols;
            } else if (mem.eql(u8, "-h", arg) or mem.eql(u8, "--help", arg)) {
                var stdout_buf: [1024]u8 = undefined;
                var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
                try stdout_writer.interface.writeAll(USAGE);
                try stdout_writer.interface.flush();
                std.process.exit(0);
            } else if (mem.eql(u8, "--version", arg)) {
                var stdout_buf: [1024]u8 = undefined;
                var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
                try stdout_writer.interface.writeAll(zon.version);
                try stdout_writer.interface.flush();
                std.process.exit(0);
            } else if (mem.startsWith(u8, arg, "-")) {
                for (arg[1..]) |ch| switch (ch) {
                    'd' => self.decode = true,
                    'i' => self.ignore_garbage = true,
                    else => return error.InvalidArgs,
                };
            } else {
                self.file = try allocator.dupe(u8, arg);
            }
        }
        return self;
    }

    fn deinit(self: *CmdArgs, allocator: mem.Allocator) void {
        if (self.file) |f| {
            allocator.free(f);
        }
    }
};

const USAGE =
    \\Usage: base64 [OPTION]... [FILE]
    \\Base64 encode or decode FILE, or standard input, to standard output.
    \\
    \\With no FILE, or when FILE is -, read standard input.
    \\
    \\Mandatory arguments to long options are mandatory for short options too.
    \\  -d, --decode          decode data
    \\  -i, --ignore-garbage  when decoding, ignore non-alphabet characters
    \\  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76).
    \\                          Use 0 to disable line wrapping
    \\      --help        display this help and exit
    \\      --version     output version information and exit
    \\
    \\The data are encoded as described for the base64 alphabet in RFC 4648.
    \\When decoding, the input may contain newlines in addition to the bytes of
    \\the formal base64 alphabet.  Use --ignore-garbage to attempt to recover
    \\from any other non-alphabet bytes in the encoded stream.
;

fn exitWithError(msg: []const u8) noreturn {
    std.debug.print("base64: {s}", .{msg});
    std.process.exit(1);
}
