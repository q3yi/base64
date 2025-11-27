const std = @import("std");

const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const lower = "abcdefghijklmnopqrstuvwxyz";
const other = "0123456789+/";

const digits = upper ++ lower ++ other;
const null_sym = '=';

fn encode3Bytes(input: []const u8) [4]u8 {
    std.debug.assert(input.len > 0 and input.len <= 3);
    var encoded: [4]u8 = undefined;

    encoded[0] = digits[input[0] >> 2];

    if (input.len == 1) {
        encoded[1] = digits[(input[0] & 0x03) << 4];
        encoded[2] = null_sym;
        encoded[3] = null_sym;
        return encoded;
    }

    encoded[1] = digits[((input[0] & 0x03) << 4) | (input[1] >> 4)];

    if (input.len == 2) {
        encoded[2] = digits[(input[1] & 0x0F) << 2];
        encoded[3] = null_sym;
        return encoded;
    }

    encoded[2] = digits[((input[1] & 0x0F) << 2) | input[2] >> 6];
    encoded[3] = digits[input[2] & 0x3F];

    return encoded;
}

test "encode 1 byte slice" {
    const input: []const u8 = "0";
    const expect = "MA==";
    try std.testing.expectEqualSlices(u8, expect, &encode3Bytes(input));
}

test "encode 2 bytes slice" {
    const input: []const u8 = "Hi";
    const expect = "SGk=";
    try std.testing.expectEqualSlices(u8, expect, &encode3Bytes(input));
}

test "encode 3 bytes slice" {
    const input: []const u8 = "wow";
    const expect = "d293";
    try std.testing.expectEqualSlices(u8, expect, &encode3Bytes(input));
}

pub fn encode(input_stream: *std.Io.Reader, output_stream: *std.Io.Writer, wrap: usize) error{ ReadFailed, WriteFailed }!void {
    var row_size: usize = 0;
    OUTTER: while (true) {
        var buf: [3]u8 = undefined;
        var len: usize = 0;
        while (len < 3) : (len += 1) {
            buf[len] = input_stream.takeByte() catch |err| switch (err) {
                error.ReadFailed => |e| return e,
                error.EndOfStream => if (len == 0) break :OUTTER else break,
            };
        }

        const encoded = encode3Bytes(buf[0..len]);

        if (wrap == 0 or row_size + encoded.len < wrap) {
            const count = try output_stream.write(encoded[0..]);
            row_size += if (wrap != 0) count else 0;
            continue;
        }

        for (encoded) |ch| {
            if (row_size == wrap) {
                try output_stream.writeByte('\n');
                row_size = 0;
            }
            try output_stream.writeByte(ch);
            row_size += 1;
        }
    }

    try output_stream.flush();
}

pub const DecodeError = error{ NonAlphabet, InvalidInput };

fn charToIndex(ch: u8) DecodeError!u8 {
    return switch (ch) {
        'A'...'Z' => 0 + (ch - 'A'),
        'a'...'z' => 26 + (ch - 'a'),
        '0'...'9' => 52 + (ch - '0'),
        '+' => 62,
        '-' => 63,
        '=' => 64,
        else => DecodeError.NonAlphabet,
    };
}

fn decodeFromIndex(indexs: [4]u8, decoded: []u8) usize {
    var len: usize = 0;
    decoded[0] = (indexs[0] << 2) | ((indexs[1] >> 4) & 0x03);
    len += 1;

    if (indexs[2] != 64) {
        decoded[1] = ((indexs[1] & 0x0F) << 4) | ((indexs[2] >> 2) & 0x0F);
        len += 1;
    }

    if (indexs[3] != 64) {
        decoded[2] = ((indexs[2] & 0x03) << 6) | (indexs[3] & 0x3F);
        len += 1;
    }

    return len;
}

test "decode to 1 byte" {
    const input: [4]u8 = .{ 'M' - 'A', 'A' - 'A', 64, 64 };
    var buf: [3]u8 = undefined;
    try std.testing.expectEqual(1, decodeFromIndex(input, &buf));
    try std.testing.expectEqualSlices(u8, "0", buf[0..1]);
}

test "decode to 2 byte" {
    const encoded = "SGk=";
    var input: [4]u8 = undefined;
    for (encoded, 0..) |ch, i| {
        input[i] = charToIndex(ch) catch unreachable;
    }

    var buf: [3]u8 = undefined;
    try std.testing.expectEqual(2, decodeFromIndex(input, &buf));
    try std.testing.expectEqualSlices(u8, "Hi", buf[0..2]);
}

test "decode to 3 byte" {
    const encoded = "d293";
    var input: [4]u8 = undefined;
    for (encoded, 0..) |ch, i| {
        input[i] = charToIndex(ch) catch unreachable;
    }

    var buf: [3]u8 = undefined;
    try std.testing.expectEqual(3, decodeFromIndex(input, &buf));
    try std.testing.expectEqualSlices(u8, "wow", &buf);
}

pub fn decode(input_stream: *std.Io.Reader, output_stream: *std.Io.Writer, ignore_garbage: bool) (DecodeError || error{ ReadFailed, WriteFailed })!void {
    var buf: [4]u8 = undefined;
    var len: usize = 0;
    while (true) {
        const ch = input_stream.takeByte() catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.EndOfStream => if (len == 0) break else return DecodeError.InvalidInput,
        };

        if (ch == '\n' or ch == '\r') continue;

        buf[len] = charToIndex(ch) catch |err| switch (err) {
            DecodeError.NonAlphabet => |e| if (ignore_garbage) continue else return e,
            else => unreachable,
        };
        len += 1;

        if (len != 4) continue;

        var decoded: [3]u8 = undefined;
        const count = decodeFromIndex(buf, &decoded);
        _ = try output_stream.write(decoded[0..count]);
        len = 0;
    }

    try output_stream.flush();
}
