//! Voice dictation: hold a key, speak, get a task.
//!
//! Records mono 16 kHz PCM through `waveIn`, wraps it in a WAV container and
//! POSTs it to Deepgram's prerecorded endpoint over WinHTTP (so we get TLS for
//! free without pulling in a crypto stack). The transcript is extracted from
//! the JSON response and handed back to the UI.
//!
//! The API key is read from the `DEEPGRAM_API_KEY` environment variable, or
//! from `deepgram.key` next to the executable (first line).

const std = @import("std");
const w = @import("win32.zig");

const REC_SECONDS = 20;
const SAMPLE_RATE = 16000;
const MAX_REC: usize = SAMPLE_RATE * 2 * REC_SECONDS;
const NBUF = 8;
const BUF = 16384;
const MAX_TEXT = 1024;
const MAX_RESP = 128 * 1024;

pub const State = enum { idle, recording, transcribing, no_key, failed };

pub var state: State = .idle;
pub var text_buf: [MAX_TEXT]u8 = undefined;
pub var text_len: usize = 0;

/// Set by the UI before use.
pub var target: w.HWND = null;
pub var done_msg: w.UINT = 0;

var rec: [MAX_REC]u8 = undefined;
var rec_len: usize = 0;
var recording: bool = false;

var hwi: w.HWAVEIN = null;
var hdrs: [NBUF]w.WAVEHDR = undefined;
var abufs: [NBUF][BUF]u8 = undefined;

var api_key: [512]u8 = undefined;
var api_key_len: usize = 0;

// ---------------------------------------------------------------------------
// Key loading
// ---------------------------------------------------------------------------

fn setKey(bytes: []const u8) void {
    const line = std.mem.trim(u8, bytes, " \t\r\n");
    if (line.len == 0) return;
    const n = @min(line.len, api_key.len);
    @memcpy(api_key[0..n], line[0..n]);
    api_key_len = n;
}

fn keyFromEnv() void {
    if (api_key_len != 0) return;
    const name = std.unicode.utf8ToUtf16LeStringLiteral("DEEPGRAM_API_KEY");
    var buf: [512]u16 = undefined;
    const n = w.GetEnvironmentVariableW(name, &buf, buf.len);
    if (n == 0 or n >= buf.len) return;
    var u8buf: [1024]u8 = undefined;
    const m = std.unicode.utf16LeToUtf8(&u8buf, buf[0..n]) catch return;
    setKey(u8buf[0..m]);
}

fn keyFilePath() w.PCWSTR {
    const S = struct {
        var buf: [260]u16 = [_]u16{0} ** 260;
    };
    if (S.buf[0] != 0) return @ptrCast(&S.buf);

    var exe: [260]u16 = undefined;
    const n: usize = w.GetModuleFileNameW(null, &exe, 260);
    var i: usize = n;
    while (i > 0 and exe[i - 1] != '\\' and exe[i - 1] != '/') : (i -= 1) {}
    var k: usize = 0;
    while (k < i and k < S.buf.len - 1) : (k += 1) S.buf[k] = exe[k];
    const suffix = std.unicode.utf8ToUtf16LeStringLiteral("deepgram.key");
    var j: usize = 0;
    while (j < suffix.len and k < S.buf.len - 1) {
        S.buf[k] = suffix[j];
        j += 1;
        k += 1;
    }
    S.buf[k] = 0;
    return @ptrCast(&S.buf);
}

fn keyFromFile() void {
    if (api_key_len != 0) return;
    const h = w.CreateFileW(keyFilePath(), w.GENERIC_READ, 1, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);
    var buf: [1024]u8 = undefined;
    var read: w.DWORD = 0;
    if (w.ReadFile(h, &buf, @intCast(buf.len), &read, null) == 0) return;
    setKey(buf[0..read]);
}

pub fn loadKey() void {
    keyFromEnv();
    keyFromFile();
    if (api_key_len == 0) state = .no_key;
}

pub fn hasKey() bool {
    return api_key_len != 0;
}

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------

fn waveInProc(h: w.HWAVEIN, msg: w.UINT, inst: usize, p1: usize, p2: usize) callconv(.winapi) void {
    _ = inst;
    _ = p2;
    if (msg != w.WOM_DONE) return;
    const hdr: *w.WAVEHDR = @ptrFromInt(p1);
    const n: usize = hdr.dwBytesRecorded;
    if (recording and n > 0 and rec_len + n <= MAX_REC) {
        @memcpy(rec[rec_len .. rec_len + n], hdr.lpData[0..n]);
        rec_len += n;
    }
    if (recording) _ = w.waveInAddBuffer(h, hdr, @sizeOf(w.WAVEHDR));
}

pub fn start() void {
    if (recording) return;
    if (api_key_len == 0) {
        state = .no_key;
        return;
    }

    var fmt = w.WAVEFORMATEX{};
    rec_len = 0;
    if (w.waveInOpen(&hwi, w.WAVE_MAPPER, &fmt, @intFromPtr(&waveInProc), 0, w.CALLBACK_FUNCTION) != 0) {
        state = .failed;
        return;
    }
    recording = true;
    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        hdrs[i] = .{ .lpData = &abufs[i], .dwBufferLength = BUF };
        _ = w.waveInPrepareHeader(hwi, &hdrs[i], @sizeOf(w.WAVEHDR));
        _ = w.waveInAddBuffer(hwi, &hdrs[i], @sizeOf(w.WAVEHDR));
    }
    _ = w.waveInStart(hwi);
    state = .recording;
}

fn stop() void {
    if (!recording) return;
    recording = false;
    _ = w.waveInStop(hwi);
    _ = w.waveInReset(hwi);
    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        _ = w.waveInUnprepareHeader(hwi, &hdrs[i], @sizeOf(w.WAVEHDR));
    }
    _ = w.waveInClose(hwi);
    hwi = null;
}

pub fn stopAndTranscribe() void {
    if (!recording and state != .recording) return;
    stop();
    if (rec_len < SAMPLE_RATE) { // under ~0.5 s of audio: ignore
        state = .idle;
        return;
    }
    state = .transcribing;
    const t = std.Thread.spawn(.{}, worker, .{}) catch {
        state = .failed;
        return;
    };
    t.detach();
}

pub fn toggle() void {
    if (recording) stopAndTranscribe() else start();
}

// ---------------------------------------------------------------------------
// Deepgram request
// ---------------------------------------------------------------------------

fn putU32(dst: []u8, off: usize, v: u32) void {
    dst[off] = @truncate(v);
    dst[off + 1] = @truncate(v >> 8);
    dst[off + 2] = @truncate(v >> 16);
    dst[off + 3] = @truncate(v >> 24);
}

fn putU16(dst: []u8, off: usize, v: u16) void {
    dst[off] = @truncate(v);
    dst[off + 1] = @truncate(v >> 8);
}

var body: [MAX_REC + 44]u8 = undefined;

fn buildWav() usize {
    const data_len: u32 = @intCast(rec_len);
    const b = &body;
    @memcpy(b[0..4], "RIFF");
    putU32(b, 4, 36 + data_len);
    @memcpy(b[8..12], "WAVE");
    @memcpy(b[12..16], "fmt ");
    putU32(b, 16, 16);
    putU16(b, 20, 1); // PCM
    putU16(b, 22, 1); // mono
    putU32(b, 24, SAMPLE_RATE);
    putU32(b, 28, SAMPLE_RATE * 2);
    putU16(b, 32, 2);
    putU16(b, 34, 16);
    @memcpy(b[36..40], "data");
    putU32(b, 40, data_len);
    @memcpy(b[44 .. 44 + rec_len], rec[0..rec_len]);
    return 44 + rec_len;
}

fn hexVal(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

/// Decode a JSON string body (after the opening quote) into text_buf.
fn extractTranscript(resp: []const u8) bool {
    const marker = "\"transcript\":\"";
    const marker_pos = std.mem.indexOf(u8, resp, marker) orelse return false;
    var i = marker_pos + marker.len;
    var out: usize = 0;
    while (i < resp.len and out < text_buf.len - 1) {
        const c = resp[i];
        if (c == '"') break;
        if (c == '\\' and i + 1 < resp.len) {
            i += 1;
            const e = resp[i];
            switch (e) {
                '"', '\\', '/' => {
                    text_buf[out] = e;
                    out += 1;
                },
                'n' => {
                    text_buf[out] = '\n';
                    out += 1;
                },
                't' => {
                    text_buf[out] = '\t';
                    out += 1;
                },
                'r' => {
                    text_buf[out] = '\r';
                    out += 1;
                },
                'b', 'f' => {},
                'u' => {
                    if (i + 4 < resp.len) {
                        var cp: u21 = 0;
                        var ok = true;
                        var j: usize = 1;
                        while (j <= 4) : (j += 1) {
                            const hv = hexVal(resp[i + j]) orelse {
                                ok = false;
                                break;
                            };
                            cp = cp * 16 + hv;
                        }
                        if (ok) {
                            i += 4;
                            var enc: [4]u8 = undefined;
                            const n = std.unicode.utf8Encode(cp, &enc) catch 0;
                            var k: usize = 0;
                            while (k < n and out < text_buf.len - 1) : (k += 1) {
                                text_buf[out] = enc[k];
                                out += 1;
                            }
                        }
                    }
                },
                else => {
                    text_buf[out] = e;
                    out += 1;
                },
            }
            i += 1;
            continue;
        }
        text_buf[out] = c;
        out += 1;
        i += 1;
    }
    const t = std.mem.trim(u8, text_buf[0..out], " \t\r\n");
    if (t.len == 0) {
        text_len = 0;
        return false;
    }
    std.mem.copyForwards(u8, text_buf[0..t.len], t);
    text_len = t.len;
    return true;
}

fn doRequest() bool {
    const agent = std.unicode.utf8ToUtf16LeStringLiteral("zigtodo/1.0");
    const server = std.unicode.utf8ToUtf16LeStringLiteral("api.deepgram.com");
    const verb = std.unicode.utf8ToUtf16LeStringLiteral("POST");
    const object = std.unicode.utf8ToUtf16LeStringLiteral("/v1/listen?model=nova-2&smart_format=true&punctuate=true&language=en");

    const session = w.WinHttpOpen(agent, w.WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, null, null, 0);
    if (session == null) return false;
    defer _ = w.WinHttpCloseHandle(session);
    _ = w.WinHttpSetTimeouts(session, 5000, 5000, 8000, 20000);

    const conn = w.WinHttpConnect(session, server, 443, 0);
    if (conn == null) return false;
    defer _ = w.WinHttpCloseHandle(conn);

    const req = w.WinHttpOpenRequest(conn, verb, object, null, null, null, w.WINHTTP_FLAG_SECURE);
    if (req == null) return false;
    defer _ = w.WinHttpCloseHandle(req);

    // Header: Authorization + Content-Type.
    var h8: [768]u8 = undefined;
    const prefix = "Authorization: Token ";
    const suffix = "\r\nContent-Type: audio/wav\r\n";
    var hlen: usize = 0;
    @memcpy(h8[hlen .. hlen + prefix.len], prefix);
    hlen += prefix.len;
    @memcpy(h8[hlen .. hlen + api_key_len], api_key[0..api_key_len]);
    hlen += api_key_len;
    @memcpy(h8[hlen .. hlen + suffix.len], suffix);
    hlen += suffix.len;

    var h16: [1024]u16 = undefined;
    const hn = std.unicode.utf8ToUtf16Le(&h16, h8[0..hlen]) catch return false;
    h16[hn] = 0;

    const blen = buildWav();
    if (w.WinHttpSendRequest(req, @ptrCast(&h16), -1, &body, @intCast(blen), @intCast(blen), 0) == 0) return false;
    if (w.WinHttpReceiveResponse(req, null) == 0) return false;

    var resp: [MAX_RESP]u8 = undefined;
    var resp_len: usize = 0;
    while (resp_len < resp.len) {
        var got: w.DWORD = 0;
        if (w.WinHttpReadData(req, resp[resp_len..].ptr, @intCast(resp.len - resp_len), &got) == 0) break;
        if (got == 0) break;
        resp_len += got;
    }
    return extractTranscript(resp[0..resp_len]);
}

fn worker() void {
    const ok = doRequest();
    state = if (ok) .idle else .failed;
    if (target != null and done_msg != 0) _ = w.PostMessageW(target, done_msg, 0, 0);
}
