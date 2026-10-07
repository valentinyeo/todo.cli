//! todo.cli — a tiny, dependency-free command-line front-end for the task list.
//!
//! Shares the exact same store as the Windows GUI: `Desktop\todo.txt`
//! (`[ ] task` / `[x] task`, one per line). Built for AI agents / scripts:
//! stable exit codes and an optional `--json` output.
//!
//!   todo.cli list [--all] [--json]   list tasks (active only unless --all)
//!   todo.cli add <text...>           add a task
//!   todo.cli done <n>                mark task n done
//!   todo.cli undone <n>              mark task n not done
//!   todo.cli edit <n> <text...>      replace task n's text
//!   todo.cli rm <n>                  delete task n
//!   todo.cli clear --yes             delete everything
//!   todo.cli path                    print the store path
//!   todo.cli sync                    sync with the cloud (when configured)
//!
//! No libc, no runtime, ~20 KB.

const std = @import("std");
const w = @import("win32.zig");

const MAX_TASKS = 1024;
const MAX_TEXT = 512;
const FILE_MAX = 256 * 1024;

const Task = struct {
    done: bool = false,
    text: [MAX_TEXT]u8 = undefined,
    len: usize = 0,
};

var tasks: [MAX_TASKS]Task = undefined;
var count: usize = 0;

var path_buf: [260]u16 = [_]u16{0} ** 260;
var file_buf: [FILE_MAX]u8 = undefined;

const quote = [_]u8{0x22}; // "
const bs = [_]u8{0x5C}; // backslash

fn out(bytes: []const u8) void {
    var written: w.DWORD = 0;
    _ = w.WriteFile(w.GetStdHandle(w.STD_OUTPUT_HANDLE), bytes.ptr, @intCast(bytes.len), &written, null);
}

fn err(bytes: []const u8) void {
    var written: w.DWORD = 0;
    _ = w.WriteFile(w.GetStdHandle(w.STD_ERROR_HANDLE), bytes.ptr, @intCast(bytes.len), &written, null);
}

fn outz(s: []const u8) void {
    out(s);
}

// ---------------------------------------------------------------------------
// Store path (Desktop\todo.txt)
// ---------------------------------------------------------------------------
fn initPath() void {
    const desktop = w.GUID{
        .data1 = 0xB4BFCC3A,
        .data2 = 0xDB2C,
        .data3 = 0x424C,
        .data4 = .{ 0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41 },
    };
    var ptr: w.PWSTR = undefined;
    if (w.SHGetKnownFolderPath(&desktop, 0, null, &ptr) == 0) {
        defer w.CoTaskMemFree(ptr);
        var k: usize = 0;
        while (ptr[k] != 0 and k < path_buf.len - 1) : (k += 1) path_buf[k] = ptr[k];
        if (k < path_buf.len - 1) {
            path_buf[k] = 0x5C;
            k += 1;
        }
        const name = std.unicode.utf8ToUtf16LeStringLiteral("todo.txt");
        var j: usize = 0;
        while (j < name.len and k < path_buf.len - 1) {
            path_buf[k] = name[j];
            j += 1;
            k += 1;
        }
        path_buf[k] = 0;
    }

    // Optional override (handy for tests / alternate lists): TODO_CLI_FILE.
    const envname = std.unicode.utf8ToUtf16LeStringLiteral("TODO_CLI_FILE");
    var ebuf: [260]u16 = undefined;
    const en = w.GetEnvironmentVariableW(envname, &ebuf, ebuf.len);
    if (en != 0 and en < ebuf.len) {
        var k: usize = 0;
        while (k < en and k < path_buf.len - 1) : (k += 1) path_buf[k] = ebuf[k];
        path_buf[k] = 0;
    }
}

fn pathZ() w.PCWSTR {
    return @ptrCast(&path_buf);
}

// ---------------------------------------------------------------------------
// Read / parse / write
// ---------------------------------------------------------------------------
fn load() void {
    count = 0;
    const h = w.CreateFileW(pathZ(), w.GENERIC_READ, 1, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);

    var read: w.DWORD = 0;
    if (w.ReadFile(h, &file_buf, @intCast(file_buf.len), &read, null) == 0) return;

    var it = std.mem.splitScalar(u8, file_buf[0..read], '\n');
    while (it.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (count >= MAX_TASKS) break;
        var done = false;
        if (line.len >= 4 and line[0] == '[' and line[2] == ']' and line[3] == ' ') {
            done = (line[1] == 'x' or line[1] == 'X');
            line = line[4..];
        }
        if (line.len == 0) continue;
        var t = &tasks[count];
        const n = @min(line.len, MAX_TEXT);
        @memcpy(t.text[0..n], line[0..n]);
        t.len = n;
        t.done = done;
        count += 1;
    }
}

fn save() bool {
    const h = w.CreateFileW(pathZ(), w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return false;
    defer _ = w.CloseHandle(h);

    const nl = [_]u8{'\n'};
    var written: w.DWORD = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const t = &tasks[i];
        const pfx: []const u8 = if (t.done) "[x] " else "[ ] ";
        _ = w.WriteFile(h, pfx.ptr, @intCast(pfx.len), &written, null);
        _ = w.WriteFile(h, t.text[0..t.len].ptr, @intCast(t.len), &written, null);
        _ = w.WriteFile(h, &nl, 1, &written, null);
    }
    return true;
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------
fn jsonEscape(text: []const u8) void {
    for (text) |c| {
        switch (c) {
            '"' => {
                out(&bs);
                out(&quote);
            },
            0x5C => {
                out(&bs);
                out(&bs);
            },
            '\n' => {
                out(&bs);
                outz("n");
            },
            '\r' => {
                out(&bs);
                outz("r");
            },
            '\t' => {
                out(&bs);
                outz("t");
            },
            else => {
                const one = [_]u8{c};
                out(&one);
            },
        }
    }
}

fn printList(show_all: bool, as_json: bool) void {
    var buf: [64]u8 = undefined;
    if (as_json) {
        outz("[");
        var first = true;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const t = &tasks[i];
            if (!show_all and t.done) continue;
            if (!first) outz(",");
            first = false;
            const head = std.fmt.bufPrint(&buf, "{{\"i\":{d},\"done\":{s},\"text\":", .{ i + 1, if (t.done) "true" else "false" }) catch "";
            outz(head);
            out(&quote);
            jsonEscape(t.text[0..t.len]);
            out(&quote);
            outz("}");
        }
        outz("]\n");
        return;
    }
    var n: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const t = &tasks[i];
        if (!show_all and t.done) continue;
        const head = std.fmt.bufPrint(&buf, "{d:>3}. [{c}] ", .{ i + 1, if (t.done) @as(u8, 'x') else @as(u8, ' ') }) catch "";
        outz(head);
        out(t.text[0..t.len]);
        outz("\n");
        n += 1;
    }
    if (n == 0) outz("(no tasks)\n");
}

// ---------------------------------------------------------------------------
// Arg handling
// ---------------------------------------------------------------------------
fn wideToUtf8(z: [*:0]u16, dst: []u8) []u8 {
    var len: usize = 0;
    while (z[len] != 0) : (len += 1) {}
    const n = std.unicode.utf16LeToUtf8(dst, z[0..len]) catch return dst[0..0];
    return dst[0..n];
}

fn argInt(s: []const u8) ?usize {
    if (s.len == 0) return null;
    var v: usize = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

fn usage() void {
    outz(
        \\usage: todo.cli <command> [args]
        \\
        \\  list [--all] [--json]   list tasks (active only unless --all)
        \\  add <text...>           add a task
        \\  done|undone <n>         set completion of task n
        \\  edit <n> <text...>      replace task n's text
        \\  rm <n>                  delete task n
        \\  clear --yes             delete every task
        \\  path                    print the store path
        \\  sync                    sync with the cloud (when configured)
        \\
    );
}

pub fn main() u8 {
    initPath();

    var argc: i32 = 0;
    const argv = w.CommandLineToArgvW(w.GetCommandLineW(), &argc) orelse {
        err("todo.cli: cannot read command line\n");
        return 1;
    };
    defer _ = w.LocalFree(@ptrCast(argv));

    if (argc < 2) {
        usage();
        return 1;
    }

    var cmd_buf: [256]u8 = undefined;
    const cmd = wideToUtf8(argv[1], &cmd_buf);

    load();

    // ---- list ----------------------------------------------------------
    if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "ls")) {
        var show_all = false;
        var as_json = false;
        var i: usize = 2;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            var b: [64]u8 = undefined;
            const a = wideToUtf8(argv[i], &b);
            if (std.mem.eql(u8, a, "--all") or std.mem.eql(u8, a, "-a")) show_all = true;
            if (std.mem.eql(u8, a, "--json")) as_json = true;
        }
        printList(show_all, as_json);
        return 0;
    }

    // ---- path ----------------------------------------------------------
    if (std.mem.eql(u8, cmd, "path")) {
        var u8buf: [520]u8 = undefined;
        const wide = std.mem.sliceTo(&path_buf, 0);
        const n = std.unicode.utf16LeToUtf8(&u8buf, wide) catch 0;
        out(u8buf[0..n]);
        outz("\n");
        return 0;
    }

    // ---- add -----------------------------------------------------------
    if (std.mem.eql(u8, cmd, "add") or std.mem.eql(u8, cmd, "a")) {
        if (count >= MAX_TASKS) {
            err("todo.cli: list full\n");
            return 1;
        }
        var text: [MAX_TEXT]u8 = undefined;
        var len: usize = 0;
        var i: usize = 2;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            var b: [MAX_TEXT]u8 = undefined;
            const a = wideToUtf8(argv[i], &b);
            if (len != 0 and len < MAX_TEXT) {
                text[len] = ' ';
                len += 1;
            }
            var j: usize = 0;
            while (j < a.len and len < MAX_TEXT) : (j += 1) {
                text[len] = a[j];
                len += 1;
            }
        }
        if (len == 0) {
            err("todo.cli: nothing to add\n");
            return 1;
        }
        var t = &tasks[count];
        @memcpy(t.text[0..len], text[0..len]);
        t.len = len;
        t.done = false;
        count += 1;
        if (!save()) {
            err("todo.cli: cannot write store\n");
            return 1;
        }
        var buf: [48]u8 = undefined;
        outz(std.fmt.bufPrint(&buf, "added #{d}\n", .{count}) catch "");
        return 0;
    }

    // ---- done / undone -------------------------------------------------
    if (std.mem.eql(u8, cmd, "done") or std.mem.eql(u8, cmd, "undone")) {
        if (argc < 3) {
            err("todo.cli: missing task number\n");
            return 1;
        }
        var b: [64]u8 = undefined;
        const idx = argInt(wideToUtf8(argv[2], &b)) orelse {
            err("todo.cli: bad task number\n");
            return 1;
        };
        if (idx < 1 or idx > count) {
            err("todo.cli: no such task\n");
            return 1;
        }
        tasks[idx - 1].done = std.mem.eql(u8, cmd, "done");
        _ = save();
        return 0;
    }

    // ---- edit ----------------------------------------------------------
    if (std.mem.eql(u8, cmd, "edit")) {
        if (argc < 4) {
            err("todo.cli: usage: edit <n> <text...>\n");
            return 1;
        }
        var b: [64]u8 = undefined;
        const idx = argInt(wideToUtf8(argv[2], &b)) orelse 0;
        if (idx < 1 or idx > count) {
            err("todo.cli: no such task\n");
            return 1;
        }
        var text: [MAX_TEXT]u8 = undefined;
        var len: usize = 0;
        var i: usize = 3;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            var ab: [MAX_TEXT]u8 = undefined;
            const a = wideToUtf8(argv[i], &ab);
            if (len != 0 and len < MAX_TEXT) {
                text[len] = ' ';
                len += 1;
            }
            var j: usize = 0;
            while (j < a.len and len < MAX_TEXT) : (j += 1) {
                text[len] = a[j];
                len += 1;
            }
        }
        tasks[idx - 1].len = len;
        @memcpy(tasks[idx - 1].text[0..len], text[0..len]);
        _ = save();
        return 0;
    }

    // ---- rm ------------------------------------------------------------
    if (std.mem.eql(u8, cmd, "rm") or std.mem.eql(u8, cmd, "remove")) {
        if (argc < 3) {
            err("todo.cli: missing task number\n");
            return 1;
        }
        var b: [64]u8 = undefined;
        const idx = argInt(wideToUtf8(argv[2], &b)) orelse 0;
        if (idx < 1 or idx > count) {
            err("todo.cli: no such task\n");
            return 1;
        }
        var k = idx - 1;
        while (k + 1 < count) : (k += 1) tasks[k] = tasks[k + 1];
        count -= 1;
        _ = save();
        return 0;
    }

    // ---- clear ---------------------------------------------------------
    if (std.mem.eql(u8, cmd, "clear")) {
        var yes = false;
        var done_only = false;
        var i: usize = 2;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            var b: [64]u8 = undefined;
            const a = wideToUtf8(argv[i], &b);
            if (std.mem.eql(u8, a, "--yes") or std.mem.eql(u8, a, "-y")) yes = true;
            if (std.mem.eql(u8, a, "--done") or std.mem.eql(u8, a, "--checked") or std.mem.eql(u8, a, "-d")) done_only = true;
        }
        if (!yes) {
            err("todo.cli: refusing to clear without --yes\n");
            return 1;
        }
        if (done_only) {
            var dst: usize = 0;
            var k: usize = 0;
            while (k < count) : (k += 1) {
                if (!tasks[k].done) {
                    tasks[dst] = tasks[k];
                    dst += 1;
                }
            }
            count = dst;
        } else {
            count = 0;
        }
        _ = save();
        return 0;
    }

    // ---- sync ----------------------------------------------------------
    if (std.mem.eql(u8, cmd, "sync")) {
        err("todo.cli: cloud sync is not configured yet\n");
        return 1;
    }

    err("todo.cli: unknown command\n");
    usage();
    return 1;
}
