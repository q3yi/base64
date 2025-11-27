const std = @import("std");
const mem = std.mem;
const base64 = @import("base64");
const zon = @import("build.zig.zon");

pub fn main() void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    var args: CmdArgs = .{};
    parseArgs(allocator, &args) catch |err| switch (err) {
        ArgsParseError.InvalidArgs => exitWithError("invalid args"),
        ArgsParseError.InvalidWrapCols => exitWithError("invalid wrap cols"),
        else => exitWithError("parse args failed"),
    };

    var input_file: std.fs.File = undefined;
    if (args.file) |file| {
        input_file = std.fs.cwd().openFile(file, .{ .mode = .read_only }) catch {
            std.debug.print("base64: fail to open file {s}", .{file});
            std.process.exit(1);
        };
    } else {
        input_file = std.fs.File.stdin();
    }
    defer input_file.close();

    var read_buf: [1024]u8 = undefined;
    var file_reader = input_file.reader(&read_buf);
    const reader = &file_reader.interface;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
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
};

const ArgsParseError = error{ InvalidArgs, InvalidWrapCols };

fn parseArgs(allocator: mem.Allocator, parsed: *CmdArgs) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, "-d", arg) or mem.eql(u8, "--decode", arg)) {
            parsed.decode = true;
        } else if (mem.eql(u8, "-i", arg) or mem.eql(u8, "--ignore-garbage", arg)) {
            parsed.ignore_garbage = true;
        } else if (mem.eql(u8, "-w", arg) or mem.eql(u8, "--wrap", arg)) {
            if (i + 1 >= args.len) return ArgsParseError.InvalidWrapCols;
            parsed.wrap = std.fmt.parseInt(usize, args[i + 1], 10) catch return ArgsParseError.InvalidWrapCols;
            i += 1;
        } else if (mem.startsWith(u8, arg, "-w")) {
            parsed.wrap = std.fmt.parseInt(usize, arg[2..], 10) catch return ArgsParseError.InvalidWrapCols;
        } else if (mem.startsWith(u8, arg, "--wrap=")) {
            parsed.wrap = std.fmt.parseInt(usize, arg[7..], 10) catch return ArgsParseError.InvalidWrapCols;
        } else if (mem.eql(u8, "-h", arg) or mem.eql(u8, "--help", arg)) {
            _ = try std.fs.File.stdout().write(USAGE);
            std.process.exit(0);
        } else if (mem.eql(u8, "--version", arg)) {
            _ = try std.fs.File.stdout().write(zon.version);
            std.process.exit(0);
        } else if (mem.startsWith(u8, arg, "-")) {
            for (arg[1..]) |ch| switch (ch) {
                'd' => parsed.decode = true,
                'i' => parsed.ignore_garbage = true,
                else => return ArgsParseError.InvalidArgs,
            };
        } else {
            parsed.file = try allocator.dupe(u8, arg);
        }
    }
}

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

fn exitWithError(msg: []const u8) void {
    std.debug.print("base64: {s}", .{msg});
    std.process.exit(1);
}
