//! KSUIDs are 20 bytes:
//!
//! - 00-03 byte: uint32 BE UTC timestamp with custom epoch
//! - 04-19 byte: random "payload"

const std = @import("std");
const time = std.time;
const mem = std.mem;
const crypto = std.crypto;
const base62 = @import("./base62.zig");
const testing = std.testing;
const KSUID = @This();

bytes: [byte_length]u8 = undefined,

/// KSUID's epoch starts more recently so that the 32-bit number space gives a
/// significantly higher useful lifetime of around 136 years from March 2017.
/// This number (14e8) was picked to be easy to remember.
const epoch_stamp = 1400000000;
/// Timestamp is a uint32
const timestamp_length_in_bytes = 4;
/// Payload is 16-bytes
const payload_length_in_bytes = 16;
/// KSUIDs are 20 bytes when binary encoded
const byte_length = timestamp_length_in_bytes + payload_length_in_bytes;
/// The length of a KSUID when string (base62) encoded
const string_encoded_length = 27;

pub const Error = error{
    InvalidLength,
};

/// Generates a new KSUID
pub fn init() KSUID {
    return initTimestamp(time.timestamp());
}

pub fn initTimestamp(ts: i64) KSUID {
    var ksuid = KSUID{};
    mem.writeIntBig(u32, ksuid.bytes[0..timestamp_length_in_bytes], @as(u32, @intCast(ts - epoch_stamp)));
    crypto.random.bytes(ksuid.bytes[timestamp_length_in_bytes..]);
    return ksuid;
}

/// Parse decodes a string-encoded representation of a KSUID object
pub fn parse(text: []const u8) !KSUID {
    if (text.len != string_encoded_length) {
        return error.InvalidLength;
    }

    var ksuid = KSUID{};
    try base62.decode(&ksuid.bytes, text[0..string_encoded_length]);
    return ksuid;
}

/// The timestamp portion of the ID as a bare integer which is uncorrected
/// for KSUID's special epoch.
pub fn timestamp(self: *const KSUID) i64 {
    return @intCast(mem.readIntBig(u32, self.bytes[0..timestamp_length_in_bytes]));
}

pub fn correctedTimestamp(self: *const KSUID) i64 {
    return self.timestamp() + epoch_stamp;
}

/// The 16-byte random payload without the timestamp
pub fn payload(self: *const KSUID) *const [payload_length_in_bytes]u8 {
    return self.bytes[timestamp_length_in_bytes..];
}

pub fn encodeToString(self: *const KSUID, dst: *[string_encoded_length]u8) void {
    base62.encode(dst, &self.bytes);
}

pub fn format(self: *const KSUID, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    var buf: [string_encoded_length]u8 = undefined;
    self.encodeToString(&buf);
    try writer.writeAll(&buf);
}

test {
    testing.refAllDecls(@This());
}

test "basic ksuid test" {
    var buf: [byte_length]u8 = undefined;
    var binary = try std.fmt.hexToBytes(&buf, "11972568CB727B4246F2A0B6BBE4D4A4F08D1C57");
    var expected = KSUID{
        .bytes = @as(*[byte_length]u8, @ptrCast(binary)).*,
    };

    var actual = try KSUID.parse("2VbwelKZHctiGJ4xKbqjMTcBpfr");
    try testing.expectEqual(expected, actual);

    try testing.expectEqual(@as(i64, 295118184), actual.timestamp());
    try testing.expectEqual(@as(i64, 295118184 + epoch_stamp), actual.correctedTimestamp());

    var payloadBuf: [payload_length_in_bytes]u8 = undefined;
    var data = try std.fmt.hexToBytes(&payloadBuf, "CB727B4246F2A0B6BBE4D4A4F08D1C57");
    try testing.expectEqualSlices(u8, data, actual.payload());
}

test "format" {
    const text = "2WX7SzNteVyKD8qMWcQFPOM9Ltq";
    const ksuid1 = KSUID.parse(text) catch unreachable;
    try testing.expectFmt(text, "{}", .{ksuid1});

    const ksuid2 = KSUID.init();
    const text2 = try std.fmt.allocPrint(testing.allocator, "{}", .{ksuid2});
    defer testing.allocator.free(text2);

    const ksuid3 = try KSUID.parse(text2);
    try testing.expect(mem.eql(u8, &ksuid2.bytes, &ksuid3.bytes));
}
