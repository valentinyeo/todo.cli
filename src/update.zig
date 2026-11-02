//! Self-update from GitHub Releases.
//!
//! CI publishes every push to main as release `v<N>` with `zigtodo.exe` and a
//! `version.txt` holding N, and bakes N into the exe. The worker downloads a
//! newer exe, swaps it in beside the running one, and posts `done_msg`; the UI
//! restarts into it when the panel is idle.
const std = @import("std");
const w = @import("win32.zig");
const build_options = @import("build_options");

/// 0 marks a local build: it never updates on its own, only from the tray.
pub const version: u32 = build_options.version;

const host = "github.com";
const repo_path = "/valentinyeo/todo.cli/releases";

pub const Status = enum { idle, checking, up_to_date, ready, failed };

pub var status: Status = .idle;
pub var latest: u32 = 0;
pub var target: w.HWND = null;
pub var done_msg: w.UINT = 0;

var busy = std.atomic.Value(bool).init(false);
var exe_buf: [4 << 20]u8 = undefined;

pub fn parseVersion(body: []const u8) ?u32 {
    return std.fmt.parseInt(u32, std.mem.trim(u8, body, " \t\r\n"), 10) catch null;
}

/// A downloaded exe is accepted only if it is a whole PE image.
pub fn looksLikeExe(bytes: []const u8, buf_len: usize) bool {
    return bytes.len >= 64 * 1024 and bytes.len < buf_len and std.mem.startsWith(u8, bytes, "MZ");
}

/// Starts a background check unless one is already running.
pub fn checkAsync() void {
    // Once swapped in, a second download would try to overwrite the running
    // image's `.old` name, fail, and hide the pending restart.
    if (status == .ready) return;
    if (busy.swap(true, .acq_rel)) return;
    status = .checking;
    const t = std.Thread.spawn(.{}, worker, .{}) catch {
        status = .failed;
        busy.store(false, .release);
        return;
    };
    t.detach();
}

fn worker() void {
    status = check();
    busy.store(false, .release);
    if (target != null and done_msg != 0) _ = w.PostMessageW(target, done_msg, 0, 0);
}

fn check() Status {
    var vbuf: [64]u8 = undefined;
    const vbody = get(repo_path ++ "/latest/download/version.txt", &vbuf) orelse return .failed;
    latest = parseVersion(vbody) orelse return .failed;
    if (latest <= version) return .up_to_date;

    var pbuf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pbuf, repo_path ++ "/download/v{d}/zigtodo.exe", .{latest}) catch return .failed;
    const exe = get(path, &exe_buf) orelse return .failed;
    if (!looksLikeExe(exe, exe_buf.len)) return .failed;
    return if (swapIn(exe)) .ready else .failed;
}

const Paths = struct {
    exe: [272:0]u16 = undefined,
    new: [272:0]u16 = undefined,
    old: [272:0]u16 = undefined,
};

fn paths() ?Paths {
    var p: Paths = .{};
    const n = w.GetModuleFileNameW(null, &p.exe, 260);
    if (n == 0 or n >= 260) return null;
    const ext_new = std.unicode.utf8ToUtf16LeStringLiteral(".new");
    const ext_old = std.unicode.utf8ToUtf16LeStringLiteral(".old");
    p.exe[n] = 0;
    @memcpy(p.new[0..n], p.exe[0..n]);
    @memcpy(p.new[n .. n + 4], ext_new);
    p.new[n + 4] = 0;
    @memcpy(p.old[0..n], p.exe[0..n]);
    @memcpy(p.old[n .. n + 4], ext_old);
    p.old[n + 4] = 0;
    return p;
}

/// Windows lets a running exe be renamed, so the old one steps aside as
/// `.old` and the download takes its name.
fn swapIn(bytes: []const u8) bool {
    const p = paths() orelse return false;
    const h = w.CreateFileW(&p.new, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return false;
    var written: w.DWORD = 0;
    const ok = w.WriteFile(h, bytes.ptr, @intCast(bytes.len), &written, null) != 0 and
        written == bytes.len and w.FlushFileBuffers(h) != 0;
    _ = w.CloseHandle(h);
    if (!ok) {
        _ = w.DeleteFileW(&p.new);
        return false;
    }
    if (w.MoveFileExW(&p.exe, &p.old, w.MOVEFILE_REPLACE_EXISTING | w.MOVEFILE_WRITE_THROUGH) == 0) {
        _ = w.DeleteFileW(&p.new);
        return false;
    }
    if (w.MoveFileExW(&p.new, &p.exe, w.MOVEFILE_WRITE_THROUGH) == 0) {
        _ = w.MoveFileExW(&p.old, &p.exe, w.MOVEFILE_WRITE_THROUGH);
        return false;
    }
    return true;
}

/// Removes the exe a previous update set aside.
pub fn cleanup() void {
    const p = paths() orelse return;
    _ = w.DeleteFileW(&p.old);
}

/// Starts the freshly swapped-in exe. Call after the window is gone and the
/// single-instance mutex is released, or the new process just pokes this one.
pub fn relaunch() void {
    const p = paths() orelse return;
    _ = w.ShellExecuteW(null, null, &p.exe, null, null, w.SW_SHOW);
}

fn get(path: []const u8, out: []u8) ?[]u8 {
    const agent = std.unicode.utf8ToUtf16LeStringLiteral("zigtodo-updater");
    const server = std.unicode.utf8ToUtf16LeStringLiteral(host);
    var path16: [256:0]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&path16, path) catch return null;
    path16[n] = 0;

    const session = w.WinHttpOpen(agent, w.WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, null, null, 0);
    if (session == null) return null;
    defer _ = w.WinHttpCloseHandle(session);
    _ = w.WinHttpSetTimeouts(session, 5000, 5000, 10000, 30000);

    const conn = w.WinHttpConnect(session, server, 443, 0);
    if (conn == null) return null;
    defer _ = w.WinHttpCloseHandle(conn);

    // GitHub answers with a redirect to its asset host; WinHTTP follows it.
    const req = w.WinHttpOpenRequest(conn, null, &path16, null, null, null, w.WINHTTP_FLAG_SECURE);
    if (req == null) return null;
    defer _ = w.WinHttpCloseHandle(req);

    if (w.WinHttpSendRequest(req, null, 0, null, 0, 0, 0) == 0) return null;
    if (w.WinHttpReceiveResponse(req, null) == 0) return null;

    var code: w.DWORD = 0;
    var code_len: w.DWORD = @sizeOf(w.DWORD);
    if (w.WinHttpQueryHeaders(req, w.WINHTTP_QUERY_STATUS_CODE | w.WINHTTP_QUERY_FLAG_NUMBER, null, &code, &code_len, null) == 0) return null;
    if (code != 200) return null;

    var len: usize = 0;
    while (len < out.len) {
        var got: w.DWORD = 0;
        if (w.WinHttpReadData(req, out[len..].ptr, @intCast(out.len - len), &got) == 0) return null;
        if (got == 0) break;
        len += got;
    }
    return out[0..len];
}

test "parseVersion reads the number CI writes" {
    try std.testing.expectEqual(@as(?u32, 42), parseVersion("42\n"));
    try std.testing.expectEqual(@as(?u32, 7), parseVersion(" 7\r\n"));
    try std.testing.expectEqual(@as(?u32, null), parseVersion("Not Found"));
    try std.testing.expectEqual(@as(?u32, null), parseVersion(""));
}

test "looksLikeExe rejects error pages and truncated downloads" {
    var img = [_]u8{0} ** (100 * 1024);
    img[0] = 'M';
    img[1] = 'Z';
    try std.testing.expect(looksLikeExe(&img, 4 << 20));
    try std.testing.expect(!looksLikeExe("<html>Not Found</html>", 4 << 20));
    try std.testing.expect(!looksLikeExe(&img, img.len)); // filled the buffer: cut off
    try std.testing.expect(!looksLikeExe(img[0..1000], 4 << 20));
}
