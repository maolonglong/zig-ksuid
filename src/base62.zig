const std = @import("std");
const testing = std.testing;

/// lexographic ordering (based on Unicode table) is 0-9A-Za-z
const base62_characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const zero_string = "000000000000000000000000000";
const offset_uppercase = 10;
const offset_lowercase = 36;

pub const Error = error{
    DestTooShort,
};

/// Converts a base 62 byte into the number value that it represents.
fn base62Value(digit: u8) u8 {
    return switch (digit) {
        '0'...'9' => digit - '0',
        'A'...'Z' => offset_uppercase + (digit - 'A'),
        'a'...'z' => offset_lowercase + (digit - 'a'),
        else => unreachable,
    };
}

/// This function encodes the base 62 representation of the src KSUID in binary
/// form into dst.
///
/// In order to support a couple of optimizations the function assumes that src
/// is 20 bytes long and dst is 27 bytes long.
///
/// Any unused bytes in dst will be set to the padding '0' byte.
pub fn encode(dst: *[27]u8, src: *const [20]u8) void {
    const src_base = 4294967296;
    const dst_base = 62;

    // Split src into 5 4-byte words, this is where most of the efficiency comes
    // from because this is a O(N^2) algorithm, and we make N = N / 4 by working
    // on 32 bits at a time.
    var parts = [5]u32{
        std.mem.readIntBig(u32, src[0..4]),
        std.mem.readIntBig(u32, src[4..8]),
        std.mem.readIntBig(u32, src[8..12]),
        std.mem.readIntBig(u32, src[12..16]),
        std.mem.readIntBig(u32, src[16..20]),
    };

    var n = dst.len;
    var bp: []u32 = parts[0..];
    var bq: [5]u32 = undefined;

    while (bp.len != 0) {
        var quotient_idx: usize = 0;
        var remainder: u64 = 0;

        for (bp) |c| {
            var value = @as(u64, @intCast(c)) + remainder * src_base;
            var digit = value / dst_base;
            remainder = value % dst_base;

            if (quotient_idx != 0 or digit != 0) {
                bq[quotient_idx] = @truncate(digit);
                quotient_idx += 1;
            }
        }

        // Writes at the end of the destination buffer because we computed the
        // lowest bits first.
        n -= 1;
        dst[n] = base62_characters[remainder];
        bp = bq[0..quotient_idx];
    }

    // Add padding at the head of the destination buffer for all bytes that were
    // not set.
    @memcpy(dst[0..n], zero_string[0..n]);
}

// This function decodes the base 62 representation of the src KSUID to the
// binary form into dst.
//
// In order to support a couple of optimizations the function assumes that src
// is 27 bytes long and dst is 20 bytes long.
//
// Any unused bytes in dst will be set to zero.
pub fn decode(dst: *[20]u8, src: *const [27]u8) !void {
    const src_base = 62;
    const dst_base = 4294967296;

    var parts: [27]u8 = undefined;
    inline for (0..27) |i| {
        parts[i] = base62Value(src[i]);
    }

    var n = dst.len;
    var bp: []u8 = parts[0..];
    var bq: [27]u8 = undefined;

    while (bp.len != 0) {
        var quotient_idx: usize = 0;
        var remainder: u64 = 0;

        for (bp) |c| {
            var value = @as(u64, @intCast(c)) + remainder * src_base;
            var digit = value / dst_base;
            remainder = value % dst_base;

            if (quotient_idx != 0 or digit != 0) {
                bq[quotient_idx] = @truncate(digit);
                quotient_idx += 1;
            }
        }

        if (n < 4) {
            return error.DestTooShort;
        }

        dst[n - 4] = @truncate(remainder >> 24);
        dst[n - 3] = @truncate(remainder >> 16);
        dst[n - 2] = @truncate(remainder >> 8);
        dst[n - 1] = @truncate(remainder);
        n -= 4;
        bp = bq[0..quotient_idx];
    }

    @memcpy(dst[0..n], zero_string[0..n]);
}

test "base62 encode" {
    var buf: [20]u8 = undefined;
    var src = try std.fmt.hexToBytes(&buf, "11972568CB727B4246F2A0B6BBE4D4A4F08D1C57");
    var dst: [27]u8 = undefined;
    encode(&dst, src[0..20]);
    const expected = "2VbwelKZHctiGJ4xKbqjMTcBpfr";
    try testing.expectEqualSlices(u8, expected, &dst);
}

test "base62 decode" {
    var dst: [20]u8 = undefined;
    try decode(&dst, "2VbwelKZHctiGJ4xKbqjMTcBpfr");
    var buf: [27]u8 = undefined;
    const expected = try std.fmt.hexToBytes(&buf, "11972568CB727B4246F2A0B6BBE4D4A4F08D1C57");
    try testing.expectEqualSlices(u8, expected, &dst);
}
