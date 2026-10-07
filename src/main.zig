//! zigtodo — a dark, ultra-light edge-reveal todo panel for Windows.
//!
//! The list, buttons and chrome are custom-drawn with GDI so the whole thing
//! shares one hand-rolled style guide (see the `C_*` palette and the README).
//! Only the two text fields are real EDIT controls.
//!
//! * Reveals when the cursor touches the middle quarter of the right edge.
//! * `Ctrl+Alt+Space` opens it anywhere.
//! * `Ctrl+Alt+D` dictates a task via Deepgram.
//! * j/k navigate, `Ctrl+Enter` edits, `Ctrl+E` toggles done, `Del` removes.

const std = @import("std");
const w = @import("win32.zig");
const dict = @import("dictation.zig");

// ---------------------------------------------------------------------------
// IDs / messages
// ---------------------------------------------------------------------------
const HOTKEY_OPEN: i32 = 1;
const HOTKEY_DICT: i32 = 2;
const HOTKEY_DOCK: i32 = 3;
const ID_TRAY_OPEN: usize = 201;
const ID_TRAY_QUIT: usize = 202;
const ID_TRAY_DOCK: usize = 203;
const WM_TRAY: w.UINT = w.WM_APP + 1;
const WM_DICT_DONE: w.UINT = w.WM_APP + 2;
const WM_SHOW: w.UINT = w.WM_APP + 3;
const WM_APPBAR: w.UINT = w.WM_APP + 4;

const TIMER_POLL: usize = 1;
const POLL_MS: u32 = 40;

const MAX_TASKS = 256;
const MAX_TEXT = 200;

// ---------------------------------------------------------------------------
// Compile-time UTF-16 literals
// ---------------------------------------------------------------------------
const utf8 = std.unicode.utf8ToUtf16LeStringLiteral;
const cls_name = utf8("ZigTodoPanel");
const cls_static = utf8("STATIC");
const cls_edit = utf8("EDIT");

const win_title = utf8("zigtodo");
const txt_title = utf8("TODO");
const txt_add = utf8("Add");
const txt_clear = utf8("Clear");
const txt_face = utf8("Segoe UI");
const txt_empty = utf8("");
const txt_confirm = utf8("Clear all tasks?");
const txt_confirm_hint = utf8("press  y  to confirm  ·  esc  to cancel");

// ---------------------------------------------------------------------------
// Style guide — deep grey / indigo.  Palette is a "zinc" base with one accent.
//   bg        #18181B    zinc-900   panel background
//   surface   #232327    card / idle row
//   input     #25252B    text field
//   hover     #2C2C31    row / button hover
//   selected  #2F2F36    row selection
//   border     #33333A    hairlines
//   accent    #6366F1    indigo-500, the one accent colour
//   accent-hi #818CF8    accent hover
//   text      #E4E4E7    primary text
//   muted     #A1A1AA    secondary text
//   faint     #71717A    tertiary text
//   danger    #EF4444    destructive
// ---------------------------------------------------------------------------
var C_BG: w.COLORREF = 0x001B1818;
var C_SURFACE: w.COLORREF = 0x00272323;
var C_INPUT: w.COLORREF = 0x002B2525;
var C_HOVER: w.COLORREF = 0x00312C2C;
var C_SEL: w.COLORREF = 0x00362F2F;
var C_BORDER: w.COLORREF = 0x003A3333;
var C_ACCENT: w.COLORREF = 0x00F16663;
var C_ACCENT_HI: w.COLORREF = 0x00F88C81;
var C_TEXT: w.COLORREF = 0x00E7E4E4;
var C_MUTED: w.COLORREF = 0x00AAA1A1;
var C_FAINT: w.COLORREF = 0x007A7171;
var C_DANGER: w.COLORREF = 0x004444EF;
var C_WHITE: w.COLORREF = 0x00FAFAFA;

const Palette = struct {
    bg: w.COLORREF,
    surface: w.COLORREF,
    input: w.COLORREF,
    hover: w.COLORREF,
    sel: w.COLORREF,
    border: w.COLORREF,
    accent: w.COLORREF,
    accent_hi: w.COLORREF,
    text: w.COLORREF,
    muted: w.COLORREF,
    faint: w.COLORREF,
    danger: w.COLORREF,
    on_accent: w.COLORREF,
};

const dark_pal = Palette{
    .bg = 0x001B1818,
    .surface = 0x00272323,
    .input = 0x002B2525,
    .hover = 0x00312C2C,
    .sel = 0x00362F2F,
    .border = 0x003A3333,
    .accent = 0x00F16663,
    .accent_hi = 0x00F88C81,
    .text = 0x00E7E4E4,
    .muted = 0x00AAA1A1,
    .faint = 0x007A7171,
    .danger = 0x004444EF,
    .on_accent = 0x00FAFAFA,
};

const light_pal = Palette{
    .bg = 0x00F5F4F4,
    .surface = 0x00FFFFFF,
    .input = 0x00FFFFFF,
    .hover = 0x00ECE9E9,
    .sel = 0x00FBE8E7,
    .border = 0x00DBD6D6,
    .accent = 0x00E5464F,
    .accent_hi = 0x00F16663,
    .text = 0x001B1818,
    .muted = 0x005B5252,
    .faint = 0x00AAA1A1,
    .danger = 0x002626DC,
    .on_accent = 0x00FFFFFF,
};

// ---------------------------------------------------------------------------
// Hotkeys
// ---------------------------------------------------------------------------
const Hotkey = struct { mods: w.UINT, vk: w.UINT, label: []const u8 };

const open_hotkeys = [_]Hotkey{
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = ' ', .label = "Ctrl+Alt+Space" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'Z', .label = "Ctrl+Alt+Z" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'Q', .label = "Ctrl+Alt+Q" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'J', .label = "Ctrl+Alt+J" },
    .{ .mods = w.MOD_CONTROL | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = ' ', .label = "Ctrl+Shift+Space" },
};

const dict_hotkeys = [_]Hotkey{
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'D', .label = "Ctrl+Alt+D" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'M', .label = "Ctrl+Alt+M" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_NOREPEAT, .vk = 'V', .label = "Ctrl+Alt+V" },
    .{ .mods = w.MOD_CONTROL | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = 'D', .label = "Ctrl+Shift+D" },
};

const dock_hotkeys = [_]Hotkey{
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = ' ', .label = "Ctrl+Alt+Shift+Space" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = 'K', .label = "Ctrl+Alt+Shift+K" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = 'Z', .label = "Ctrl+Alt+Shift+Z" },
    .{ .mods = w.MOD_CONTROL | w.MOD_ALT | w.MOD_SHIFT | w.MOD_NOREPEAT, .vk = 'J', .label = "Ctrl+Alt+Shift+J" },
};

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------
const Task = struct {
    text: [MAX_TEXT]u8 = undefined,
    len: usize = 0,
    done: bool = false,
};

const State = struct {
    hwnd: w.HWND = null,
    hinst: w.HINSTANCE = null,

    hInput: w.HWND = null,
    hRowEdit: w.HWND = null,
    old_input_proc: w.WNDPROC = undefined,
    old_rowedit_proc: w.WNDPROC = undefined,

    // GDI
    font_title: w.HFONT = undefined,
    font_body: w.HFONT = undefined,
    font_done: w.HFONT = undefined,
    font_caption: w.HFONT = undefined,
    font_button: w.HFONT = undefined,
    br_bg: w.HBRUSH = undefined,
    br_surface: w.HBRUSH = undefined,
    br_input: w.HBRUSH = undefined,
    br_hover: w.HBRUSH = undefined,
    br_sel: w.HBRUSH = undefined,
    br_accent: w.HBRUSH = undefined,
    br_accent_hi: w.HBRUSH = undefined,
    br_danger: w.HBRUSH = undefined,
    pen_border: w.HPEN = undefined,
    pen_accent: w.HPEN = undefined,
    pen_check: w.HPEN = undefined,
    pen_danger: w.HPEN = undefined,

    // geometry
    dpi: i32 = 96,
    area_top: i32 = 0,
    area_bottom: i32 = 0,
    area_right: i32 = 0,
    panel_w: i32 = 0,
    panel_h: i32 = 0,
    panel_y: i32 = 0,
    x: i32 = 0,
    x_expanded: i32 = 0,
    x_collapsed: i32 = 0,
    zone_top: i32 = 0,
    zone_bottom: i32 = 0,
    expanded: bool = false,
    pinned: bool = false,
    prev_fg: w.HWND = null,
    docked: bool = false,
    hover_dock: bool = false,
    resizing: bool = false,
    hover_resize: bool = false,
    dock_width: i32 = 0,
    light: bool = false,
    theme_ready: bool = false,
    config_path: [260]u16 = [_]u16{0} ** 260,

    // tasks
    tasks: [MAX_TASKS]Task = undefined,
    order: [MAX_TASKS]usize = undefined,
    count: usize = 0,
    sel: isize = -1,
    scroll: i32 = 0,

    // interaction
    hover_add: bool = false,
    hover_clear: bool = false,
    hover_row: isize = -1,
    drag_scroll: bool = false,
    drag_y: i32 = 0,
    drag_scroll0: i32 = 0,
    confirm_purge: bool = false,
    editing: bool = false,
    edit_index: isize = -1,

    open_label: []const u8 = "Tray icon",
    dict_label: []const u8 = "no key",
    hIcon: w.HICON = null,
    nid: w.NOTIFYICONDATAW = .{},
    todo_path: [260]u16 = [_]u16{0} ** 260,
};

var g: State = .{};

// ---------------------------------------------------------------------------
// Basics
// ---------------------------------------------------------------------------
fn px(v: i32) i32 {
    return @divTrunc(v * g.dpi + 48, 96);
}

fn wide(utf8_bytes: []const u8, out: []u16) ?[:0]u16 {
    if (out.len == 0) return null;
    const n = std.unicode.utf8ToUtf16Le(out[0..out.len - 1], utf8_bytes) catch return null;
    out[n] = 0;
    return out[0..n :0];
}

fn wideToUtf8(in: []const u16, out: []u8) ?[]u8 {
    const n = std.unicode.utf16LeToUtf8(out, in) catch return null;
    return out[0..n];
}

fn pathZ() w.PCWSTR {
    return @ptrCast(&g.todo_path);
}

fn rect(l: i32, t: i32, r: i32, b: i32) w.RECT {
    return .{ .left = l, .top = t, .right = r, .bottom = b };
}

fn invalidate() void {
    if (g.hwnd == null) return;
    _ = w.InvalidateRect(g.hwnd, null, 0);
}

// ---------------------------------------------------------------------------
// Theme: mirror the Windows light/dark setting
// ---------------------------------------------------------------------------
fn personalizeKey() w.PCWSTR {
    const S = struct {
        var buf: [128]u16 = undefined;
        var built: bool = false;
    };
    if (!S.built) {
        const parts = [_][]const u8{ "Software", "Microsoft", "Windows", "CurrentVersion", "Themes", "Personalize" };
        var k: usize = 0;
        for (parts, 0..) |part, idx| {
            if (idx != 0 and k < S.buf.len - 1) {
                S.buf[k] = 0x5C;
                k += 1;
            }
            for (part) |c| {
                if (k < S.buf.len - 1) {
                    S.buf[k] = c;
                    k += 1;
                }
            }
        }
        S.buf[k] = 0;
        S.built = true;
    }
    return @ptrCast(&S.buf);
}

fn isLightTheme() bool {
    var data: w.DWORD = 0;
    var size: w.DWORD = @sizeOf(w.DWORD);
    const name = std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme");
    const res = w.RegGetValueW(w.HKEY_CURRENT_USER, personalizeKey(), name, w.RRF_RT_REG_DWORD, null, &data, &size);
    if (res != 0) return false; // default to dark if the setting is absent
    return data != 0;
}

fn createThemeObjects() void {
    g.br_bg = w.CreateSolidBrush(C_BG);
    g.br_surface = w.CreateSolidBrush(C_SURFACE);
    g.br_input = w.CreateSolidBrush(C_INPUT);
    g.br_hover = w.CreateSolidBrush(C_HOVER);
    g.br_sel = w.CreateSolidBrush(C_SEL);
    g.br_accent = w.CreateSolidBrush(C_ACCENT);
    g.br_accent_hi = w.CreateSolidBrush(C_ACCENT_HI);
    g.br_danger = w.CreateSolidBrush(C_DANGER);
    g.pen_border = w.CreatePen(w.PS_SOLID, @max(1, px(1)), C_BORDER);
    g.pen_accent = w.CreatePen(w.PS_SOLID, @max(1, px(1)), C_ACCENT);
    g.pen_check = w.CreatePen(w.PS_SOLID, @max(2, px(2)), C_WHITE);
    g.pen_danger = w.CreatePen(w.PS_SOLID, @max(1, px(1)), C_DANGER);
}

fn destroyThemeObjects() void {
    _ = w.DeleteObject(g.br_bg);
    _ = w.DeleteObject(g.br_surface);
    _ = w.DeleteObject(g.br_input);
    _ = w.DeleteObject(g.br_hover);
    _ = w.DeleteObject(g.br_sel);
    _ = w.DeleteObject(g.br_accent);
    _ = w.DeleteObject(g.br_accent_hi);
    _ = w.DeleteObject(g.br_danger);
    _ = w.DeleteObject(g.pen_border);
    _ = w.DeleteObject(g.pen_accent);
    _ = w.DeleteObject(g.pen_check);
    _ = w.DeleteObject(g.pen_danger);
}

fn applyTheme(light: bool) void {
    const p = if (light) light_pal else dark_pal;
    C_BG = p.bg;
    C_SURFACE = p.surface;
    C_INPUT = p.input;
    C_HOVER = p.hover;
    C_SEL = p.sel;
    C_BORDER = p.border;
    C_ACCENT = p.accent;
    C_ACCENT_HI = p.accent_hi;
    C_TEXT = p.text;
    C_MUTED = p.muted;
    C_FAINT = p.faint;
    C_DANGER = p.danger;
    C_WHITE = p.on_accent;
    if (g.theme_ready) destroyThemeObjects();
    createThemeObjects();
    g.theme_ready = true;
    g.light = light;
    invalidate();
}

/// Re-read the OS theme and rebuild brushes/pens only if it actually changed.
fn refreshTheme() void {
    const light = isLightTheme();
    if (light != g.light or !g.theme_ready) applyTheme(light);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
const Layout = struct {
    pad: i32,
    header_y: i32,
    header_h: i32,
    input_y: i32,
    input_h: i32,
    add_x: i32,
    add_w: i32,
    clear_x: i32,
    clear_y: i32,
    clear_w: i32,
    clear_h: i32,
    dock_x: i32,
    dock_w: i32,
    dock_h: i32,
    list_y: i32,
    list_bottom: i32,
    list_right: i32,
    row_h: i32,
    row_gap: i32,
    footer_y: i32,
};

fn computeLayout() Layout {
    const pad = px(14);
    const header_h = px(42);
    const input_h = px(38);
    const gap = px(12);
    const row_h = px(36);
    const row_gap = px(6);
    const add_w = px(58);
    const clear_w = px(54);
    const clear_h = px(24);
    const header_y = pad;
    const input_y = header_y + header_h;
    const list_y = input_y + input_h + gap;
    const footer_h = px(26);

    return .{
        .pad = pad,
        .header_y = header_y,
        .header_h = header_h,
        .input_y = input_y,
        .input_h = input_h,
        .add_x = g.panel_w - pad - add_w,
        .add_w = add_w,
        .clear_x = g.panel_w - pad - clear_w,
        .clear_y = header_y + @divTrunc(header_h - clear_h, 2),
        .clear_w = clear_w,
        .clear_h = clear_h,
        .dock_x = g.panel_w - pad - clear_w - px(8) - px(64),
        .dock_w = px(64),
        .dock_h = clear_h,
        .list_y = list_y,
        .list_bottom = g.panel_h - pad - footer_h,
        .list_right = g.panel_w - pad - px(10),
        .row_h = row_h,
        .row_gap = row_gap,
        .footer_y = g.panel_h - pad - footer_h,
    };
}

fn visibleRows(L: Layout) i32 {
    const stride = L.row_h + L.row_gap;
    return @max(1, @divTrunc(L.list_bottom - L.list_y + L.row_gap, stride));
}

fn rowRect(L: Layout, di: i32) w.RECT {
    const stride = L.row_h + L.row_gap;
    const y = L.list_y + (di - g.scroll) * stride;
    return rect(L.pad, y, L.list_right, y + L.row_h);
}

// ---------------------------------------------------------------------------
// Task model
// ---------------------------------------------------------------------------
fn rebuildOrder() void {
    var n: usize = 0;
    var i: usize = 0;
    while (i < g.count) : (i += 1) {
        if (!g.tasks[i].done) {
            g.order[n] = i;
            n += 1;
        }
    }
    i = 0;
    while (i < g.count) : (i += 1) {
        if (g.tasks[i].done) {
            g.order[n] = i;
            n += 1;
        }
    }
}

fn displayPosOf(task_index: isize) isize {
    var i: usize = 0;
    while (i < g.count) : (i += 1) {
        if (g.order[i] == @as(usize, @intCast(task_index))) return @intCast(i);
    }
    return -1;
}

fn clampScroll(L: Layout) void {
    const max_scroll = @max(0, @as(i32, @intCast(g.count)) - visibleRows(L));
    if (g.scroll > max_scroll) g.scroll = max_scroll;
    if (g.scroll < 0) g.scroll = 0;
}

fn ensureVisible() void {
    if (g.sel < 0) return;
    const L = computeLayout();
    const di = displayPosOf(g.sel);
    if (di < 0) return;
    const vis = visibleRows(L);
    if (di < g.scroll) g.scroll = @intCast(di);
    if (di >= g.scroll + vis) g.scroll = @intCast(di - vis + 1);
    clampScroll(L);
}

fn setText(task: *Task, bytes: []const u8) void {
    const t = std.mem.trim(u8, bytes, " \t\r\n");
    var n = @min(t.len, MAX_TEXT);
    // never split a UTF-8 sequence
    while (n > 0 and (t[n - 1] & 0xC0) == 0x80) n -= 1;
    @memcpy(task.text[0..n], t[0..n]);
    task.len = n;
}

fn addTaskText(bytes: []const u8) void {
    if (g.count >= MAX_TASKS) return;
    const t = std.mem.trim(u8, bytes, " \t\r\n");
    if (t.len == 0) return;
    var task = &g.tasks[g.count];
    setText(task, t);
    task.done = false;
    g.count += 1;
    g.sel = @intCast(g.count - 1);
    rebuildOrder();
    ensureVisible();
    save();
    invalidate();
}

fn toggleDone(task_index: isize) void {
    if (task_index < 0 or task_index >= g.count) return;
    const i: usize = @intCast(task_index);
    g.tasks[i].done = !g.tasks[i].done;
    rebuildOrder();
    ensureVisible();
    save();
    invalidate();
}

fn deleteTask(task_index: isize) void {
    if (task_index < 0 or task_index >= g.count) return;
    const i: usize = @intCast(task_index);
    var j = i;
    while (j + 1 < g.count) : (j += 1) g.tasks[j] = g.tasks[j + 1];
    g.count -= 1;
    if (g.sel >= g.count) g.sel = @intCast(g.count);
    if (g.count == 0) g.sel = -1;
    rebuildOrder();
    ensureVisible();
    save();
    invalidate();
}

fn purgeAll() void {
    g.count = 0;
    g.sel = -1;
    g.scroll = 0;
    rebuildOrder();
    save();
    invalidate();
}

fn purgeDone() void {
    var dst: usize = 0;
    var i: usize = 0;
    while (i < g.count) : (i += 1) {
        if (!g.tasks[i].done) {
            g.tasks[dst] = g.tasks[i];
            dst += 1;
        }
    }
    g.count = dst;
    if (g.count == 0) {
        g.sel = -1;
    } else if (g.sel >= g.count) {
        g.sel = @intCast(g.count);
    }
    rebuildOrder();
    ensureVisible();
    save();
    invalidate();
}

fn moveSelection(dir: i32) void {
    if (g.count == 0) return;
    if (g.sel < 0) {
        g.sel = @intCast(g.order[0]);
    } else {
        var di = displayPosOf(g.sel);
        if (di < 0) di = 0;
        var nd = di + dir;
        if (nd < 0) nd = 0;
        if (nd > @as(isize, @intCast(g.count - 1))) nd = @intCast(g.count - 1);
        g.sel = @intCast(g.order[@intCast(nd)]);
    }
    ensureVisible();
    invalidate();
}

fn pageMove(dir: i32) void {
    const L = computeLayout();
    moveSelection(dir * visibleRows(L));
}

// ---------------------------------------------------------------------------
// Persistence  (format: "[x] text" / "[ ] text")
// ---------------------------------------------------------------------------
fn save() void {
    const h = w.CreateFileW(pathZ(), w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);

    var i: usize = 0;
    while (i < g.count) : (i += 1) {
        const t = &g.tasks[i];
        const prefix: []const u8 = if (t.done) "[x] " else "[ ] ";
        var written: w.DWORD = 0;
        _ = w.WriteFile(h, prefix.ptr, @intCast(prefix.len), &written, null);
        _ = w.WriteFile(h, t.text[0..t.len].ptr, @intCast(t.len), &written, null);
        const nl = [_]u8{'\n'};
        _ = w.WriteFile(h, &nl, 1, &written, null);
    }
}

fn load() void {
    const h = w.CreateFileW(pathZ(), w.GENERIC_READ, 1, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);

    var buf: [65536]u8 = undefined;
    var read: w.DWORD = 0;
    if (w.ReadFile(h, &buf, @intCast(buf.len), &read, null) == 0) return;

    var it = std.mem.splitScalar(u8, buf[0..read], '\n');
    while (it.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var done = false;
        if (line.len >= 4 and line[0] == '[' and line[2] == ']' and line[3] == ' ') {
            done = (line[1] == 'x' or line[1] == 'X');
            line = line[4..];
        }
        if (g.count >= MAX_TASKS) break;
        var task = &g.tasks[g.count];
        setText(task, line);
        if (task.len == 0) continue;
        task.done = done;
        g.count += 1;
    }
    rebuildOrder();
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
fn readInput(bytes: *[2048]u8) []const u8 {
    var wbuf: [1024]u16 = undefined;
    const n = w.GetWindowTextW(g.hInput, &wbuf, wbuf.len);
    if (n <= 0) return "";
    const u = wideToUtf8(wbuf[0..@intCast(n)], bytes) orelse return "";
    return std.mem.trim(u8, u, " \t\r\n");
}

fn addFromInput() void {
    var bytes: [2048]u8 = undefined;
    const text = readInput(&bytes);
    if (text.len == 0) return;
    _ = w.SetWindowTextW(g.hInput, txt_empty);
    addTaskText(text);
    _ = w.SetFocus(g.hInput);
}

fn positionInput() void {
    const L = computeLayout();
    const x = L.pad + px(12);
    const y = L.input_y + px(9);
    const wd = (L.add_x - px(10)) - x;
    const ht = L.input_h - px(18);
    _ = w.MoveWindow(g.hInput, x, y, wd, ht, 1);
}

fn startEdit() void {
    if (g.sel < 0 or g.sel >= g.count) return;
    const L = computeLayout();
    const di = displayPosOf(g.sel);
    if (di < 0) return;
    var rc = rowRect(L, @intCast(di));
    rc.left += px(38);
    rc.right -= px(8);
    rc.top += px(3);
    rc.bottom -= px(3);
    _ = w.MoveWindow(g.hRowEdit, rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top, 1);
    var wbuf: [MAX_TEXT * 2 + 2]u16 = undefined;
    const t = &g.tasks[@intCast(g.sel)];
    if (wide(t.text[0..t.len], &wbuf)) |z| _ = w.SetWindowTextW(g.hRowEdit, z.ptr);
    g.editing = true;
    g.edit_index = g.sel;
    _ = w.ShowWindow(g.hRowEdit, w.SW_SHOW);
    _ = w.SetFocus(g.hRowEdit);
    _ = w.SendMessageW(g.hRowEdit, w.EM_SETSEL, 0, -1);
    invalidate();
}

fn endEdit(commit: bool) void {
    if (!g.editing) return;
    g.editing = false;
    if (commit and g.edit_index >= 0 and g.edit_index < g.count) {
        var wbuf: [1024]u16 = undefined;
        const n = w.GetWindowTextW(g.hRowEdit, &wbuf, wbuf.len);
        if (n > 0) {
            var bytes: [2048]u8 = undefined;
            if (wideToUtf8(wbuf[0..@intCast(n)], &bytes)) |u| {
                const t = std.mem.trim(u8, u, " \t\r\n");
                if (t.len > 0) setText(&g.tasks[@intCast(g.edit_index)], t);
            }
        }
        rebuildOrder();
        save();
    }
    g.edit_index = -1;
    _ = w.ShowWindow(g.hRowEdit, w.SW_HIDE);
    _ = w.SetFocus(g.hwnd);
    invalidate();
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------
fn fill(hdc: w.HDC, rc: w.RECT, brush: w.HBRUSH) void {
    _ = w.FillRect(hdc, &rc, brush);
}

fn fillRounded(hdc: w.HDC, rc: w.RECT, radius: i32, brush: w.HBRUSH) void {
    const ob = w.SelectObject(hdc, brush);
    const op = w.SelectObject(hdc, w.GetStockObject(w.NULL_PEN));
    _ = w.RoundRect(hdc, rc.left, rc.top, rc.right, rc.bottom, radius * 2, radius * 2);
    _ = w.SelectObject(hdc, op);
    _ = w.SelectObject(hdc, ob);
}

fn strokeRounded(hdc: w.HDC, rc: w.RECT, radius: i32, pen: w.HPEN) void {
    const ob = w.SelectObject(hdc, w.GetStockObject(w.NULL_BRUSH));
    const op = w.SelectObject(hdc, pen);
    _ = w.RoundRect(hdc, rc.left, rc.top, rc.right, rc.bottom, radius * 2, radius * 2);
    _ = w.SelectObject(hdc, op);
    _ = w.SelectObject(hdc, ob);
}

fn drawText(hdc: w.HDC, text: []const u8, rc: *const w.RECT, flags: w.UINT, color: w.COLORREF, font: w.HFONT) void {
    var buf: [MAX_TEXT * 2 + 4]u16 = undefined;
    const z = wide(text, &buf) orelse return;
    var r = rc.*;
    const of = w.SelectObject(hdc, font);
    _ = w.SetTextColor(hdc, color);
    _ = w.SetBkMode(hdc, w.TRANSPARENT);
    _ = w.DrawTextW(hdc, z.ptr, @intCast(z.len), &r, flags);
    _ = w.SelectObject(hdc, of);
}

fn drawCheck(hdc: w.HDC, box: w.RECT, color: w.COLORREF) void {
    const pen = w.CreatePen(w.PS_SOLID, @max(2, px(2)), color);
    const op = w.SelectObject(hdc, pen);
    const x = box.left;
    const y = box.top;
    _ = w.MoveToEx(hdc, x + px(4), y + px(9), null);
    _ = w.LineTo(hdc, x + px(7), y + px(12));
    _ = w.LineTo(hdc, x + px(14), y + px(5));
    _ = w.SelectObject(hdc, op);
    _ = w.DeleteObject(pen);
}

fn drawScene(hdc: w.HDC, full: w.RECT) void {
    const L = computeLayout();
    fill(hdc, full, g.br_bg);

    // ---- header --------------------------------------------------------
    {
        var title_rc = rect(L.pad, L.header_y, g.panel_w, L.header_y + L.header_h);
        drawText(hdc, "TODO", &title_rc, w.DT_LEFT | w.DT_VCENTER | w.DT_SINGLELINE, C_TEXT, g.font_title);

        // active count
        var active: i32 = 0;
        var i: usize = 0;
        while (i < g.count) : (i += 1) {
            if (!g.tasks[i].done) active += 1;
        }
        var nbuf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&nbuf, "{d} left", .{active}) catch "";
        var count_rc = rect(L.pad + px(58), L.header_y, g.panel_w, L.header_y + L.header_h);
        drawText(hdc, label, &count_rc, w.DT_LEFT | w.DT_VCENTER | w.DT_SINGLELINE, C_FAINT, g.font_caption);

        // clear button (ghost)
        const crc = rect(L.clear_x, L.clear_y, L.clear_x + L.clear_w, L.clear_y + L.clear_h);
        if (g.hover_clear) fillRounded(hdc, crc, px(6), g.br_hover);
        drawText(hdc, "Clear", &crc, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE, if (g.hover_clear) C_DANGER else C_MUTED, g.font_caption);

        // dock toggle (ghost)
        const dock_label: []const u8 = if (g.docked) "Undock" else "Dock";
        const drc = rect(L.dock_x, L.clear_y, L.dock_x + L.dock_w, L.clear_y + L.dock_h);
        if (g.hover_dock) fillRounded(hdc, drc, px(6), g.br_hover);
        drawText(hdc, dock_label, &drc, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE, if (g.docked) C_ACCENT else C_MUTED, g.font_caption);
    }

    // ---- input + add ---------------------------------------------------
    {
        const box = rect(L.add_x - px(10) - (L.pad + px(12)) - L.pad, L.input_y, L.add_x - px(10), L.input_y + L.input_h);
        _ = box;
        const container = rect(L.pad, L.input_y, L.add_x - px(10), L.input_y + L.input_h);
        fillRounded(hdc, container, px(10), g.br_input);
        if (w.GetFocus() == g.hInput) {
            strokeRounded(hdc, container, px(10), g.pen_accent);
        } else {
            strokeRounded(hdc, container, px(10), g.pen_border);
        }

        const add = rect(L.add_x, L.input_y, L.add_x + L.add_w, L.input_y + L.input_h);
        fillRounded(hdc, add, px(10), if (g.hover_add) g.br_accent_hi else g.br_accent);
        drawText(hdc, "Add", &add, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE, C_WHITE, g.font_button);
    }

    // ---- list ----------------------------------------------------------
    {
        const saved = w.SaveDC(hdc);
        _ = w.IntersectClipRect(hdc, 0, L.list_y, g.panel_w, L.list_bottom);

        const vis = visibleRows(L);
        var slot: i32 = 0;
        while (slot < vis) : (slot += 1) {
            const di = g.scroll + slot;
            if (di >= g.count) break;
            const ti = g.order[@intCast(di)];
            const t = &g.tasks[ti];
            const rc = rowRect(L, di);
            if (rc.bottom > L.list_bottom) break;

            const selected = (@as(isize, @intCast(ti)) == g.sel);
            const hovered = (@as(isize, @intCast(ti)) == g.hover_row);
            const editing_row = g.editing and (@as(isize, @intCast(ti)) == g.edit_index);

            const bg = if (editing_row) g.br_input else if (selected) g.br_sel else if (hovered) g.br_hover else g.br_surface;
            fillRounded(hdc, rc, px(9), bg);

            if (selected and !editing_row) {
                const bar = rect(rc.left, rc.top + px(7), rc.left + px(3), rc.bottom - px(7));
                fillRounded(hdc, bar, px(2), g.br_accent);
            }

            // checkbox
            const cb = rect(rc.left + px(13), rc.top + @divTrunc(L.row_h - px(18), 2), rc.left + px(13) + px(18), rc.top + @divTrunc(L.row_h - px(18), 2) + px(18));
            if (t.done) {
                fillRounded(hdc, cb, px(5), g.br_accent);
                drawCheck(hdc, cb, C_WHITE);
            } else {
                fillRounded(hdc, cb, px(5), g.br_bg);
                strokeRounded(hdc, cb, px(5), if (hovered or selected) g.pen_accent else g.pen_border);
            }

            // label
            if (!editing_row) {
                var tr = rect(cb.right + px(12), rc.top, rc.right - px(10), rc.bottom);
                const font = if (t.done) g.font_done else g.font_body;
                const color = if (t.done) C_FAINT else C_TEXT;
                drawText(hdc, t.text[0..t.len], &tr, w.DT_LEFT | w.DT_VCENTER | w.DT_SINGLELINE | w.DT_END_ELLIPSIS | w.DT_NOPREFIX, color, font);
            }
        }

        // empty state
        if (g.count == 0) {
            var er = rect(L.pad, L.list_y, L.list_right, L.list_y + px(60));
            drawText(hdc, "Nothing here. Add a task or press Ctrl+Alt+D.", &er, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE | w.DT_END_ELLIPSIS, C_FAINT, g.font_caption);
        }

        // scrollbar
        const content = @as(i32, @intCast(g.count));
        if (content > vis) {
            const track = rect(g.panel_w - L.pad - px(4), L.list_y, g.panel_w - L.pad, L.list_bottom);
            fillRounded(hdc, track, px(2), g.br_surface);
            const track_h = track.bottom - track.top;
            const thumb_h = @max(px(28), @divTrunc(track_h * vis, content));
            const max_scroll = content - vis;
            const off = if (max_scroll == 0) 0 else @divTrunc((track_h - thumb_h) * g.scroll, max_scroll);
            const thumb = rect(track.left, track.top + off, track.right, track.top + off + thumb_h);
            fillRounded(hdc, thumb, px(2), g.br_hover);
        }

        _ = w.RestoreDC(hdc, saved);
    }

    // ---- footer --------------------------------------------------------
    {
        var fr = rect(L.pad, L.footer_y, g.panel_w - L.pad, L.footer_y + px(20));
        var hint: []const u8 = "j/k move   ctrl+enter edit   ctrl+e done   del remove";
        var color: w.COLORREF = C_FAINT;
        if (dict.state == .recording) {
            hint = "● Listening…  press again to stop";
            color = C_DANGER;
        } else if (dict.state == .transcribing) {
            hint = "Transcribing…";
        } else if (dict.state == .no_key) {
            hint = "Dictation: set DEEPGRAM_API_KEY";
        } else if (dict.state == .failed) {
            hint = "Dictation failed";
            color = C_DANGER;
        }
        drawText(hdc, hint, &fr, w.DT_LEFT | w.DT_VCENTER | w.DT_SINGLELINE | w.DT_END_ELLIPSIS, color, g.font_caption);
    }

    // ---- purge confirm -------------------------------------------------
    if (g.confirm_purge) {
        const cw = g.panel_w - L.pad * 4;
        const card = rect(L.pad * 2, @divTrunc(g.panel_h, 2) - px(52), L.pad * 2 + cw, @divTrunc(g.panel_h, 2) + px(52));
        fillRounded(hdc, card, px(12), g.br_surface);
        strokeRounded(hdc, card, px(12), g.pen_danger);
        var r1 = rect(card.left + px(8), card.top + px(14), card.right - px(8), card.top + px(40));
        drawText(hdc, "Clear tasks?", &r1, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE, C_TEXT, g.font_title);
        var r2 = rect(card.left + px(8), card.top + px(42), card.right - px(8), card.top + px(64));
        drawText(hdc, "y = clear all     d = clear checked", &r2, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE | w.DT_END_ELLIPSIS, C_TEXT, g.font_caption);
        var r3 = rect(card.left + px(8), card.top + px(66), card.right - px(8), card.bottom - px(12));
        drawText(hdc, "esc = cancel", &r3, w.DT_CENTER | w.DT_VCENTER | w.DT_SINGLELINE, C_MUTED, g.font_caption);
    }
}

fn paint(hwnd: w.HWND) void {
    var ps: w.PAINTSTRUCT = .{};
    const hdc = w.BeginPaint(hwnd, &ps);
    defer _ = w.EndPaint(hwnd, &ps);

    var rc: w.RECT = .{};
    _ = w.GetClientRect(hwnd, &rc);
    const cw = rc.right;
    const ch = rc.bottom;

    const mem = w.CreateCompatibleDC(hdc);
    const bmp = w.CreateCompatibleBitmap(hdc, cw, ch);
    const old = w.SelectObject(mem, bmp);
    drawScene(mem, rect(0, 0, cw, ch));
    _ = w.BitBlt(hdc, 0, 0, cw, ch, mem, 0, 0, w.SRCCOPY);
    _ = w.SelectObject(mem, old);
    _ = w.DeleteObject(bmp);
    _ = w.DeleteDC(mem);
}

// ---------------------------------------------------------------------------
// Hit testing
// ---------------------------------------------------------------------------
fn pointFromLp(lp: w.LPARAM) w.POINT {
    const u: usize = @bitCast(lp);
    const ux: u16 = @truncate(u & 0xFFFF);
    const uy: u16 = @truncate((u >> 16) & 0xFFFF);
    const sx: i16 = @bitCast(ux);
    const sy: i16 = @bitCast(uy);
    return .{ .x = sx, .y = sy };
}

fn hitDisplayRow(pt: w.POINT, L: Layout) ?i32 {
    if (pt.y < L.list_y or pt.y >= L.list_bottom) return null;
    if (pt.x < L.pad or pt.x > L.list_right) return null;
    const stride = L.row_h + L.row_gap;
    const rel = pt.y - L.list_y;
    const within = @mod(rel, stride);
    if (within >= L.row_h) return null;
    const di = g.scroll + @divTrunc(rel, stride);
    if (di < 0 or di >= g.count) return null;
    return di;
}

fn inRect(pt: w.POINT, rc: w.RECT) bool {
    return pt.x >= rc.left and pt.x < rc.right and pt.y >= rc.top and pt.y < rc.bottom;
}

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------
fn onMouseMove(pt: w.POINT) void {
    const L = computeLayout();
    var changed = false;

    if (g.resizing) {
        var cur: w.POINT = .{};
        _ = w.GetCursorPos(&cur);
        const right_edge = w.GetSystemMetrics(w.SM_CXSCREEN);
        var nw = right_edge - cur.x;
        const minw = px(220);
        const maxw = px(680);
        if (nw < minw) nw = minw;
        if (nw > maxw) nw = maxw;
        if (nw != g.dock_width) {
            g.dock_width = nw;
            positionDocked();
        }
        return;
    }

    const add = rect(L.add_x, L.input_y, L.add_x + L.add_w, L.input_y + L.input_h);
    const clear = rect(L.clear_x, L.clear_y, L.clear_x + L.clear_w, L.clear_y + L.clear_h);
    const dock = rect(L.dock_x, L.clear_y, L.dock_x + L.dock_w, L.clear_y + L.dock_h);
    const ha = inRect(pt, add);
    const hc = inRect(pt, clear) and !g.confirm_purge;
    const hd = inRect(pt, dock) and !g.confirm_purge;
    if (ha != g.hover_add or hc != g.hover_clear or hd != g.hover_dock) changed = true;
    g.hover_add = ha;
    g.hover_clear = hc;
    g.hover_dock = hd;
    const hrz = g.docked and pt.x <= px(6);
    if (hrz != g.hover_resize) changed = true;
    g.hover_resize = hrz;

    var hr: isize = -1;
    if (hitDisplayRow(pt, L)) |di| hr = @intCast(g.order[@intCast(di)]);
    if (hr != g.hover_row) changed = true;
    g.hover_row = hr;

    if (g.drag_scroll) {
        const track = rect(0, L.list_y, 0, L.list_bottom);
        _ = track;
        const track_h = L.list_bottom - L.list_y;
        const vis = visibleRows(L);
        const content = @as(i32, @intCast(g.count));
        const thumb_h = @max(px(28), @divTrunc(track_h * vis, @max(1, content)));
        const span = @max(1, track_h - thumb_h);
        const max_scroll = @max(0, content - vis);
        const dy = pt.y - g.drag_y;
        g.scroll = g.drag_scroll0 + @divTrunc(dy * max_scroll, span);
        clampScroll(L);
        changed = true;
    }

    if (changed) invalidate();

    var tme = w.TRACKMOUSEEVENT{ .dwFlags = w.TME_LEAVE, .hwndTrack = g.hwnd };
    _ = w.TrackMouseEvent(&tme);
}

fn onLButtonDown(pt: w.POINT) void {
    g.pinned = true; // interacting keeps the panel open
    _ = w.SetFocus(g.hwnd); // so keyboard shortcuts work after clicking the panel
    const L = computeLayout();

    if (g.confirm_purge) {
        // click outside the confirm card cancels
        g.confirm_purge = false;
        invalidate();
        return;
    }

    // Docked mode: drag the left edge to resize the bar.
    if (g.docked and pt.x <= px(6)) {
        g.resizing = true;
        _ = w.SetCapture(g.hwnd);
        return;
    }

    // scrollbar
    const content = @as(i32, @intCast(g.count));
    const vis = visibleRows(L);
    if (content > vis and pt.x >= g.panel_w - L.pad - px(8) and pt.y >= L.list_y and pt.y < L.list_bottom) {
        const track_h = L.list_bottom - L.list_y;
        const thumb_h = @max(px(28), @divTrunc(track_h * vis, content));
        const max_scroll = content - vis;
        const off = if (max_scroll == 0) 0 else @divTrunc((track_h - thumb_h) * g.scroll, max_scroll);
        if (pt.y >= L.list_y + off and pt.y < L.list_y + off + thumb_h) {
            g.drag_scroll = true;
            g.drag_y = pt.y;
            g.drag_scroll0 = g.scroll;
            _ = w.SetCapture(g.hwnd);
        }
        return;
    }

    if (hitDisplayRow(pt, L)) |di| {
        const ti = g.order[@intCast(di)];
        g.sel = @intCast(ti);
        const rc = rowRect(L, di);
        const cb_left = rc.left + px(13);
        const cb_right = cb_left + px(18);
        if (pt.x >= cb_left - px(4) and pt.x <= cb_right + px(4)) {
            toggleDone(g.sel);
        } else {
            _ = w.SetFocus(g.hwnd);
            invalidate();
        }
    }
}

fn onLButtonUp(pt: w.POINT) void {
    if (g.resizing) {
        g.resizing = false;
        _ = w.ReleaseCapture();
        saveConfig();
        return;
    }
    if (g.drag_scroll) {
        g.drag_scroll = false;
        _ = w.ReleaseCapture();
        return;
    }
    const L = computeLayout();
    const add = rect(L.add_x, L.input_y, L.add_x + L.add_w, L.input_y + L.input_h);
    const clear = rect(L.clear_x, L.clear_y, L.clear_x + L.clear_w, L.clear_y + L.clear_h);
    const dock = rect(L.dock_x, L.clear_y, L.dock_x + L.dock_w, L.clear_y + L.dock_h);
    if (inRect(pt, add)) {
        addFromInput();
    } else if (inRect(pt, dock)) {
        toggleDock();
    } else if (inRect(pt, clear)) {
        if (g.count > 0) {
            g.confirm_purge = true;
            invalidate();
        }
    }
}

fn onMouseWheel(wp: w.WPARAM) void {
    const delta: i16 = @bitCast(@as(u16, @truncate((wp >> 16) & 0xFFFF)));
    const L = computeLayout();
    if (delta > 0) g.scroll -= 3 else g.scroll += 3;
    clampScroll(L);
    invalidate();
}

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------
fn ctrlDown() bool {
    return w.GetKeyState(@intCast(w.VK_CONTROL)) < 0;
}

fn onKey(wp: w.WPARAM) void {
    g.pinned = true; // interacting keeps the panel open
    if (g.confirm_purge) {
        if (wp == 'Y' or wp == 'y') {
            g.confirm_purge = false;
            purgeAll();
        } else if (wp == 'D' or wp == 'd') {
            g.confirm_purge = false;
            purgeDone();
        } else if (wp == w.VK_ESCAPE or wp == 'N' or wp == 'n') {
            g.confirm_purge = false;
            invalidate();
        }
        return;
    }

    switch (wp) {
        w.VK_J, w.VK_DOWN => moveSelection(1),
        w.VK_K, w.VK_UP => moveSelection(-1),
        w.VK_NEXT => pageMove(1),
        w.VK_PRIOR => pageMove(-1),
        w.VK_ESCAPE => collapse(true),
        w.VK_DELETE => {
            if (ctrlDown()) {
                if (g.count > 0) {
                    g.confirm_purge = true;
                    invalidate();
                }
            } else deleteTask(g.sel);
        },
        w.VK_SPACE => toggleDone(g.sel),
        w.VK_RETURN => {
            if (ctrlDown()) startEdit() else toggleDone(g.sel);
        },
        w.VK_E => {
            if (ctrlDown()) toggleDone(g.sel);
        },
        'D' => {
            if (ctrlDown()) toggleDictation();
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Dictation
// ---------------------------------------------------------------------------
fn toggleDictation() void {
    if (!dict.hasKey()) {
        dict.state = .no_key;
        dict.loadKey();
        if (!dict.hasKey()) {
            g.expanded = true;
            g.pinned = true;
            invalidate();
            return;
        }
    }
    g.expanded = true;
    g.pinned = true;
    dict.toggle();
    invalidate();
}

// ---------------------------------------------------------------------------
// Window behaviour
// ---------------------------------------------------------------------------
/// Take the foreground and put the caret in the input field. Remembers the
/// previously focused window so we can hand focus back when we close.
fn stealFocus() void {
    const fg = w.GetForegroundWindow();
    if (fg != g.hwnd) g.prev_fg = fg;

    const fg_thread = w.GetWindowThreadProcessId(fg, null);
    const our_thread = w.GetCurrentThreadId();
    if (fg_thread != 0 and fg_thread != our_thread) {
        _ = w.AttachThreadInput(fg_thread, our_thread, 1);
        _ = w.BringWindowToTop(g.hwnd);
        _ = w.SetForegroundWindow(g.hwnd);
        _ = w.SetFocus(g.hInput);
        _ = w.AttachThreadInput(fg_thread, our_thread, 0);
    } else {
        _ = w.SetForegroundWindow(g.hwnd);
        _ = w.SetFocus(g.hInput);
    }
}

fn expandAndFocus() void {
    g.expanded = true;
    g.pinned = true;
    stealFocus();
    invalidate();
}

fn collapse(restore: bool) void {
    if (g.docked) {
        if (g.editing) endEdit(false);
        g.confirm_purge = false;
        invalidate();
        return;
    }
    if (g.editing) endEdit(false);
    g.confirm_purge = false;
    g.expanded = false;
    g.pinned = false;
    if (restore and g.prev_fg != null and g.prev_fg != g.hwnd) {
        _ = w.SetForegroundWindow(g.prev_fg);
    } else {
        _ = w.SetFocus(null);
    }
    g.prev_fg = null;
    invalidate();
}

fn togglePanel() void {
    if (g.docked) {
        stealFocus();
        return;
    }
    if (g.expanded) collapse(true) else expandAndFocus();
}

// ---------------------------------------------------------------------------
// Docked mode (AppBar: reserves desktop space so nothing overlaps)
// ---------------------------------------------------------------------------
fn initConfigPath() void {
    const appdata = w.GUID{
        .data1 = 0x3EB685DB,
        .data2 = 0x65F9,
        .data3 = 0x4CF6,
        .data4 = .{ 0xA0, 0x3A, 0xE3, 0xEF, 0x65, 0x72, 0x9F, 0x3D },
    };
    var p: w.PWSTR = undefined;
    if (w.SHGetKnownFolderPath(&appdata, 0, null, &p) != 0) return;
    defer w.CoTaskMemFree(p);

    var dir: [260]u16 = undefined;
    var k: usize = 0;
    while (p[k] != 0 and k < dir.len - 1) : (k += 1) dir[k] = p[k];
    if (k < dir.len - 1) {
        dir[k] = 0x5C;
        k += 1;
    }
    const sub = utf8("zigtodo");
    var j: usize = 0;
    while (j < sub.len and k < dir.len - 1) {
        dir[k] = sub[j];
        j += 1;
        k += 1;
    }
    dir[k] = 0;
    _ = w.CreateDirectoryW(@ptrCast(&dir), null);

    k = 0;
    while (dir[k] != 0 and k < g.config_path.len - 1) : (k += 1) g.config_path[k] = dir[k];
    if (k < g.config_path.len - 1) {
        g.config_path[k] = 0x5C;
        k += 1;
    }
    const name = utf8("config.txt");
    j = 0;
    while (j < name.len and k < g.config_path.len - 1) {
        g.config_path[k] = name[j];
        j += 1;
        k += 1;
    }
    g.config_path[k] = 0;
}

fn loadConfig() void {
    if (g.config_path[0] == 0) return;
    const h = w.CreateFileW(@ptrCast(&g.config_path), w.GENERIC_READ, 1, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);
    var buf: [256]u8 = undefined;
    var read: w.DWORD = 0;
    if (w.ReadFile(h, &buf, @intCast(buf.len), &read, null) == 0) return;
    if (std.mem.indexOf(u8, buf[0..read], "docked=1") != null) g.docked = true;
    if (std.mem.indexOf(u8, buf[0..read], "width=")) |p| {
        var n: i32 = 0;
        var i = p + 6;
        while (i < read and buf[i] >= '0' and buf[i] <= '9') : (i += 1) n = n * 10 + @as(i32, buf[i] - '0');
        if (n >= 150 and n <= 3000) g.dock_width = n;
    }
}

fn saveConfig() void {
    if (g.config_path[0] == 0) return;
    const h = w.CreateFileW(@ptrCast(&g.config_path), w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == null or h == w.INVALID_HANDLE_VALUE) return;
    defer _ = w.CloseHandle(h);
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "docked={s};width={d}", .{ if (g.docked) "1" else "0", g.dock_width }) catch return;
    var written: w.DWORD = 0;
    _ = w.WriteFile(h, text.ptr, @intCast(text.len), &written, null);
}

fn positionDocked() void {
    var abd: w.APPBARDATA = .{ .hWnd = g.hwnd, .uCallbackMessage = WM_APPBAR, .uEdge = w.ABE_RIGHT };
    abd.cbSize = @sizeOf(w.APPBARDATA);
    const sw = w.GetSystemMetrics(w.SM_CXSCREEN);
    const sh = w.GetSystemMetrics(w.SM_CYSCREEN);
    abd.rc = rect(0, 0, sw, sh);
    _ = w.SHAppBarMessage(w.ABM_QUERYPOS, &abd);
    const width = if (g.dock_width > 0) g.dock_width else px(360);
    g.dock_width = width;
    abd.rc.left = abd.rc.right - width;
    _ = w.SHAppBarMessage(w.ABM_SETPOS, &abd);

    const h = abd.rc.bottom - abd.rc.top;
    g.panel_w = width;
    g.panel_h = h;
    g.panel_y = abd.rc.top;
    g.x = abd.rc.left;
    g.x_expanded = abd.rc.left;
    _ = w.MoveWindow(g.hwnd, abd.rc.left, abd.rc.top, width, h, 1);
    positionInput();
    invalidate();
}

fn enterDockMode() void {
    var abd: w.APPBARDATA = .{ .hWnd = g.hwnd, .uCallbackMessage = WM_APPBAR, .uEdge = w.ABE_RIGHT };
    abd.cbSize = @sizeOf(w.APPBARDATA);
    _ = w.SHAppBarMessage(w.ABM_NEW, &abd);
    g.docked = true;
    if (g.dock_width == 0) g.dock_width = px(360);
    g.expanded = true;
    g.pinned = true;
    positionDocked();
    saveConfig();
}

fn exitDockMode() void {
    if (!g.docked) return;
    var abd: w.APPBARDATA = .{ .hWnd = g.hwnd };
    abd.cbSize = @sizeOf(w.APPBARDATA);
    _ = w.SHAppBarMessage(w.ABM_REMOVE, &abd);
    g.docked = false;
    g.panel_w = px(360);
    g.panel_y = g.area_top + px(10);
    g.panel_h = (g.area_bottom - g.area_top) - px(20);
    g.x_collapsed = g.area_right - px(6);
    g.x_expanded = g.area_right - g.panel_w;
    g.expanded = false;
    g.pinned = false;
    setPanelX(g.x_collapsed);
    positionInput();
    saveConfig();
}

fn toggleDock() void {
    if (g.docked) exitDockMode() else enterDockMode();
    invalidate();
}

fn setPanelX(x: i32) void {
    g.x = x;
    _ = w.SetWindowPos(g.hwnd, w.HWND_TOPMOST, x, g.panel_y, g.panel_w, g.panel_h, w.SWP_NOZORDER | w.SWP_NOACTIVATE);
}

fn animate() void {
    const target = if (g.expanded) g.x_expanded else g.x_collapsed;
    if (g.x == target) return;
    const diff = target - g.x;
    var step = @divTrunc(diff, 2);
    const min_step = px(12);
    if (step >= 0 and step < min_step) step = min_step;
    if (step <= 0 and step > -min_step) step = -min_step;
    if (@abs(step) > @abs(diff)) step = diff;
    setPanelX(g.x + step);
}

fn onTick() void {
    if (g.docked) return;
    var pt: w.POINT = .{};
    if (w.GetCursorPos(&pt) == 0) return;

    if (!g.expanded) {
        // Only the middle quarter of the right edge is a hot zone.
        if (pt.x >= g.area_right - px(3) and pt.y >= g.zone_top and pt.y < g.zone_bottom and !g.drag_scroll) {
            g.expanded = true;
            g.pinned = false;
            stealFocus();
            invalidate();
        }
    } else if (!g.pinned) {
        if (pt.x < g.x_expanded - px(8)) collapse(true);
    }
    animate();
}

// ---------------------------------------------------------------------------
// Edit subclass
// ---------------------------------------------------------------------------
fn editProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    const is_row = (hwnd == g.hRowEdit);
    const old = if (is_row) g.old_rowedit_proc else g.old_input_proc;

    switch (msg) {
        w.WM_LBUTTONDOWN => {
            g.pinned = true;
        },
        w.WM_KEYDOWN => {
            if (wp != w.VK_SHIFT and wp != w.VK_CONTROL and wp != w.VK_MENU) g.pinned = true;
            // The panel's own shortcuts must still work while the input has focus
            // (but let Ctrl+C/V/X/A/Z etc. fall through to the edit control).
            if (!is_row) {
                if (g.confirm_purge) {
                    onKey(wp);
                    return 0;
                }
                if (w.GetKeyState(@intCast(w.VK_CONTROL)) < 0 and (wp == w.VK_DELETE or wp == 'E')) {
                    onKey(wp);
                    return 0;
                }
            }
            if (wp == w.VK_RETURN or wp == w.VK_ESCAPE) {
                if (is_row) {
                    endEdit(wp == w.VK_RETURN);
                } else if (wp == w.VK_RETURN) {
                    addFromInput();
                } else {
                    collapse(true);
                }
                return 0;
            }
            if (!is_row and wp == w.VK_DOWN) {
                _ = w.SetFocus(g.hwnd);
                moveSelection(1);
                return 0;
            }
        },
        w.WM_CHAR => {
            if (wp == '\r' or wp == '\n') return 0;
        },
        w.WM_KILLFOCUS => {
            if (is_row and g.editing) {
                endEdit(true);
                return 0;
            }
        },
        else => {},
    }
    return w.CallWindowProcW(old, hwnd, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// Tray / hotkeys / icon
// ---------------------------------------------------------------------------
fn registerHotkeys() void {
    for (open_hotkeys) |c| {
        if (w.RegisterHotKey(g.hwnd, HOTKEY_OPEN, c.mods, c.vk) != 0) {
            g.open_label = c.label;
            break;
        }
    }
    for (dict_hotkeys) |c| {
        if (w.RegisterHotKey(g.hwnd, HOTKEY_DICT, c.mods, c.vk) != 0) {
            g.dict_label = c.label;
            break;
        }
    }
    for (dock_hotkeys) |c| {
        if (w.RegisterHotKey(g.hwnd, HOTKEY_DOCK, c.mods, c.vk) != 0) break;
    }
}

fn setWide(dst: []u16, text: []const u8) void {
    var buf: [256]u16 = undefined;
    const z = wide(text, &buf) orelse return;
    const n = @min(z.len, dst.len - 1);
    @memcpy(dst[0..n], z[0..n]);
    dst[n] = 0;
}

fn fallbackIcon() w.HICON {
    return w.LoadIconW(null, @ptrFromInt(w.IDI_APPLICATION));
}

fn loadEmbeddedIcon() w.HICON {
    const data = @embedFile("icon.ico");
    if (data.len < 22) return fallbackIcon();
    const count = @as(u16, data[4]) | (@as(u16, data[5]) << 8);
    if (count == 0) return fallbackIcon();
    const bytes_in_res = @as(u32, data[14]) | (@as(u32, data[15]) << 8) |
        (@as(u32, data[16]) << 16) | (@as(u32, data[17]) << 24);
    const image_offset = @as(u32, data[18]) | (@as(u32, data[19]) << 8) |
        (@as(u32, data[20]) << 16) | (@as(u32, data[21]) << 24);
    const end = @as(usize, image_offset) + bytes_in_res;
    if (end > data.len) return fallbackIcon();
    const img = data[image_offset..end];
    const h = w.CreateIconFromResourceEx(img.ptr, bytes_in_res, 1, w.RT_ICON_VERSION, 0, 0, w.LR_DEFAULTCOLOR);
    return if (h == null) fallbackIcon() else h;
}

fn addTrayIcon() void {
    g.nid = .{};
    g.nid.cbSize = @sizeOf(w.NOTIFYICONDATAW);
    g.nid.hWnd = g.hwnd;
    g.nid.uID = 1;
    g.nid.uFlags = w.NIF_ICON | w.NIF_MESSAGE | w.NIF_TIP;
    g.nid.uCallbackMessage = WM_TRAY;
    g.nid.hIcon = g.hIcon;
    setWide(&g.nid.szTip, "zigtodo · click to open");
    _ = w.Shell_NotifyIconW(w.NIM_ADD, &g.nid);
}

fn showTrayMenu() void {
    _ = w.SetForegroundWindow(g.hwnd);
    var pt: w.POINT = .{};
    _ = w.GetCursorPos(&pt);
    const menu = w.CreatePopupMenu();
    _ = w.AppendMenuW(menu, w.MF_STRING, ID_TRAY_OPEN, utf8("Open"));
    _ = w.AppendMenuW(menu, w.MF_STRING | (if (g.docked) w.MF_CHECKED else 0), ID_TRAY_DOCK, utf8("Docked mode"));
    _ = w.AppendMenuW(menu, w.MF_STRING, ID_TRAY_QUIT, utf8("Quit"));
    _ = w.TrackPopupMenu(menu, w.TPM_RIGHTBUTTON, pt.x, pt.y, 0, g.hwnd, null);
    _ = w.PostMessageW(g.hwnd, w.WM_NULL, 0, 0);
    _ = w.DestroyMenu(menu);
}

// ---------------------------------------------------------------------------
// Window proc
// ---------------------------------------------------------------------------
fn buildControls() void {
    g.hInput = w.CreateWindowExW(0, cls_edit, null, w.WS_CHILD | w.WS_VISIBLE | w.ES_AUTOHSCROLL, 0, 0, 10, 10, g.hwnd, @ptrFromInt(1001), g.hinst, null);
    g.hRowEdit = w.CreateWindowExW(0, cls_edit, null, w.WS_CHILD | w.ES_AUTOHSCROLL, 0, 0, 10, 10, g.hwnd, @ptrFromInt(1002), g.hinst, null);

    const oi = w.SetWindowLongPtrW(g.hInput, w.GWLP_WNDPROC, @bitCast(@intFromPtr(&editProc)));
    g.old_input_proc = @ptrFromInt(@as(usize, @bitCast(oi)));
    const orr = w.SetWindowLongPtrW(g.hRowEdit, w.GWLP_WNDPROC, @bitCast(@intFromPtr(&editProc)));
    g.old_rowedit_proc = @ptrFromInt(@as(usize, @bitCast(orr)));

    _ = w.SendMessageW(g.hInput, w.EM_SETMARGINS, w.EC_LEFTMARGIN | w.EC_RIGHTMARGIN, px(6));
    _ = w.SendMessageW(g.hRowEdit, w.EM_SETMARGINS, w.EC_LEFTMARGIN | w.EC_RIGHTMARGIN, px(6));

    positionInput();
    _ = w.SetFocus(g.hInput);
}

fn wndProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        w.WM_CREATE => {
            g.hwnd = hwnd;
            buildControls();
            return 0;
        },
        w.WM_SIZE => {
            positionInput();
            return 0;
        },
        w.WM_SETTINGCHANGE, w.WM_THEMECHANGED => {
            refreshTheme();
            return 0;
        },
        w.WM_ACTIVATE => {
            // Clicking anywhere outside the panel closes it immediately.
            if ((wp & 0xFFFF) == w.WA_INACTIVE and g.expanded and !g.docked) {
                g.prev_fg = null;
                collapse(false);
            }
            return 0;
        },
        w.WM_PAINT => {
            paint(hwnd);
            return 0;
        },
        w.WM_ERASEBKGND => return 1,
        w.WM_MOUSEMOVE => {
            onMouseMove(pointFromLp(lp));
            return 0;
        },
        w.WM_MOUSELEAVE => {
            g.hover_add = false;
            g.hover_clear = false;
            g.hover_dock = false;
            g.hover_resize = false;
            g.hover_row = -1;
            invalidate();
            return 0;
        },
        w.WM_LBUTTONDOWN => {
            onLButtonDown(pointFromLp(lp));
            return 0;
        },
        w.WM_LBUTTONUP => {
            onLButtonUp(pointFromLp(lp));
            return 0;
        },
        w.WM_LBUTTONDBLCLK => {
            const L = computeLayout();
            if (hitDisplayRow(pointFromLp(lp), L)) |di| {
                toggleDone(@intCast(g.order[@intCast(di)]));
            }
            return 0;
        },
        w.WM_MOUSEWHEEL => {
            onMouseWheel(wp);
            return 0;
        },
        w.WM_KEYDOWN => {
            onKey(wp);
            return 0;
        },
        w.WM_CTLCOLOREDIT => {
            const hdc: w.HDC = @ptrFromInt(wp);
            _ = w.SetTextColor(hdc, C_TEXT);
            _ = w.SetBkColor(hdc, C_INPUT);
            return @bitCast(@intFromPtr(g.br_input));
        },
        w.WM_HOTKEY => {
            if (wp == HOTKEY_OPEN) togglePanel();
            if (wp == HOTKEY_DICT) toggleDictation();
            if (wp == HOTKEY_DOCK) toggleDock();
            return 0;
        },
        WM_APPBAR => {
            if ((wp & 0xFFFF) == w.ABN_POSCHANGED and g.docked) positionDocked();
            return 0;
        },
        WM_SHOW => {
            expandAndFocus();
            return 0;
        },
        WM_DICT_DONE => {
            if (dict.text_len > 0) addTaskText(dict.text_buf[0..dict.text_len]);
            invalidate();
            return 0;
        },
        WM_TRAY => {
            const ev = lp & 0xFFFF;
            if (ev == w.WM_LBUTTONUP or ev == w.WM_LBUTTONDBLCLK) togglePanel();
            if (ev == w.WM_RBUTTONUP) showTrayMenu();
            return 0;
        },
        w.WM_COMMAND => {
            const id = wp & 0xFFFF;
            if (id == ID_TRAY_OPEN) expandAndFocus();
            if (id == ID_TRAY_DOCK) toggleDock();
            if (id == ID_TRAY_QUIT) _ = w.DestroyWindow(g.hwnd);
            return 0;
        },
        w.WM_TIMER => {
            onTick();
            return 0;
        },
        w.WM_SETCURSOR => {
            if (g.hover_resize) {
                _ = w.SetCursor(w.LoadCursorW(null, @ptrFromInt(w.IDC_SIZEWE)));
                return 1;
            }
            if (g.hover_add or g.hover_clear or g.hover_dock or g.hover_row >= 0) {
                _ = w.SetCursor(w.LoadCursorW(null, @ptrFromInt(w.IDC_HAND)));
                return 1;
            }
            return w.DefWindowProcW(hwnd, msg, wp, lp);
        },
        w.WM_DESTROY => {
            if (g.editing) endEdit(false);
            if (g.docked) {
                var abd: w.APPBARDATA = .{ .hWnd = hwnd };
                abd.cbSize = @sizeOf(w.APPBARDATA);
                _ = w.SHAppBarMessage(w.ABM_REMOVE, &abd);
                g.docked = false;
            }
            _ = w.KillTimer(hwnd, TIMER_POLL);
            _ = w.UnregisterHotKey(hwnd, HOTKEY_OPEN);
            _ = w.UnregisterHotKey(hwnd, HOTKEY_DICT);
            _ = w.UnregisterHotKey(hwnd, HOTKEY_DOCK);
            _ = w.Shell_NotifyIconW(w.NIM_DELETE, &g.nid);
            if (g.hIcon != null) _ = w.DestroyIcon(g.hIcon);
            _ = w.DeleteObject(g.font_title);
            _ = w.DeleteObject(g.font_body);
            _ = w.DeleteObject(g.font_done);
            _ = w.DeleteObject(g.font_caption);
            _ = w.DeleteObject(g.font_button);
            if (g.theme_ready) destroyThemeObjects();
            w.PostQuitMessage(0);
            return 0;
        },
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
fn initPath() void {
    // Optional override (tests / alternate lists), same as the CLI.
    const envname = std.unicode.utf8ToUtf16LeStringLiteral("TODO_CLI_FILE");
    var ebuf: [260]u16 = undefined;
    const en = w.GetEnvironmentVariableW(envname, &ebuf, ebuf.len);
    if (en != 0 and en < ebuf.len) {
        var k: usize = 0;
        while (k < en and k < g.todo_path.len - 1) : (k += 1) g.todo_path[k] = ebuf[k];
        g.todo_path[k] = 0;
        return;
    }

    // Always use the Desktop todo.txt (resolved through the shell, so a
    // OneDrive-redirected Desktop still works), reused on every launch.
    const desktop = w.GUID{
        .data1 = 0xB4BFCC3A,
        .data2 = 0xDB2C,
        .data3 = 0x424C,
        .data4 = .{ 0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41 },
    };
    var desktop_ptr: w.PWSTR = undefined;
    if (w.SHGetKnownFolderPath(&desktop, 0, null, &desktop_ptr) == 0) {
        defer w.CoTaskMemFree(desktop_ptr);
        var k: usize = 0;
        while (desktop_ptr[k] != 0 and k < g.todo_path.len - 1) : (k += 1) {
            g.todo_path[k] = desktop_ptr[k];
        }
        appendTodoName(&g.todo_path, &k);
        return;
    }

    // Fallback: next to the executable.
    var buf: [260]u16 = undefined;
    const n: usize = w.GetModuleFileNameW(null, &buf, 260);
    var i: usize = n;
    while (i > 0 and buf[i - 1] != 0x5C and buf[i - 1] != '/') : (i -= 1) {}
    var k: usize = 0;
    while (k < i and k < g.todo_path.len - 1) : (k += 1) g.todo_path[k] = buf[k];
    appendTodoName(&g.todo_path, &k);
}

fn appendTodoName(dst: *[260]u16, k: *usize) void {
    if (k.* < dst.len - 1) {
        dst[k.*] = 0x5C; // path separator
        k.* += 1;
    }
    const name = utf8("todo.txt");
    var j: usize = 0;
    while (j < name.len and k.* < dst.len - 1) {
        dst[k.*] = name[j];
        j += 1;
        k.* += 1;
    }
    dst[k.*] = 0;
}

pub fn main() void {
    // Single instance: a second launch just reveals the existing panel.
    _ = w.CreateMutexW(null, 1, utf8("zigtodo_singleton_mutex_v1"));
    if (w.GetLastError() == w.ERROR_ALREADY_EXISTS) {
        const existing = w.FindWindowW(cls_name, null);
        if (existing != null) _ = w.PostMessageW(existing, WM_SHOW, 0, 0);
        return;
    }

    _ = w.SetProcessDPIAware();
    g.hinst = w.GetModuleHandleW(null);
    g.dpi = @intCast(w.GetDpiForSystem());

    var work: w.RECT = .{};
    _ = w.SystemParametersInfoW(w.SPI_GETWORKAREA, 0, &work, 0);
    g.area_top = work.top;
    g.area_bottom = work.bottom;
    g.area_right = work.right;

    // Touch zone: middle quarter of the right edge only.
    const area_h = g.area_bottom - g.area_top;
    g.zone_top = g.area_top + @divTrunc(area_h, 2) - @divTrunc(area_h, 8);
    g.zone_bottom = g.area_top + @divTrunc(area_h, 2) + @divTrunc(area_h, 8);

    g.panel_w = px(360);
    g.dock_width = px(360);
    g.panel_y = g.area_top + px(10);
    g.panel_h = (g.area_bottom - g.area_top) - px(20);
    g.x_expanded = g.area_right - g.panel_w;
    g.x_collapsed = g.area_right - px(6);
    g.x = g.x_collapsed;

    refreshTheme();

    g.font_title = w.CreateFontW(-px(17), 0, 0, 0, w.FW_SEMIBOLD, 0, 0, 0, w.DEFAULT_CHARSET, 0, 0, w.CLEARTYPE_QUALITY, w.DEFAULT_PITCH, txt_face);
    g.font_body = w.CreateFontW(-px(15), 0, 0, 0, w.FW_NORMAL, 0, 0, 0, w.DEFAULT_CHARSET, 0, 0, w.CLEARTYPE_QUALITY, w.DEFAULT_PITCH, txt_face);
    g.font_done = w.CreateFontW(-px(15), 0, 0, 0, w.FW_NORMAL, 0, 1, 0, w.DEFAULT_CHARSET, 0, 0, w.CLEARTYPE_QUALITY, w.DEFAULT_PITCH, txt_face);
    g.font_caption = w.CreateFontW(-px(12), 0, 0, 0, w.FW_NORMAL, 0, 0, 0, w.DEFAULT_CHARSET, 0, 0, w.CLEARTYPE_QUALITY, w.DEFAULT_PITCH, txt_face);
    g.font_button = w.CreateFontW(-px(14), 0, 0, 0, w.FW_MEDIUM, 0, 0, 0, w.DEFAULT_CHARSET, 0, 0, w.CLEARTYPE_QUALITY, w.DEFAULT_PITCH, txt_face);

    initPath();
    initConfigPath();
    loadConfig();
    g.hIcon = loadEmbeddedIcon();

    dict.target = g.hwnd; // hwnd is set in WM_CREATE, but target is read later
    dict.done_msg = WM_DICT_DONE;
    dict.loadKey();

    var wc = w.WNDCLASSEXW{
        .cbSize = @sizeOf(w.WNDCLASSEXW),
        .style = w.CS_HREDRAW | w.CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = g.hinst,
        .hIcon = g.hIcon,
        .hCursor = w.LoadCursorW(null, @ptrFromInt(w.IDC_ARROW)),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = cls_name,
        .hIconSm = g.hIcon,
    };
    if (w.RegisterClassExW(&wc) == 0) return;

    g.hwnd = w.CreateWindowExW(
        w.WS_EX_TOPMOST | w.WS_EX_TOOLWINDOW,
        cls_name,
        win_title,
        w.WS_POPUP | w.WS_CLIPCHILDREN,
        g.x,
        g.panel_y,
        g.panel_w,
        g.panel_h,
        null,
        null,
        g.hinst,
        null,
    );
    if (g.hwnd == null) return;

    dict.target = g.hwnd;
    _ = w.ShowWindow(g.hwnd, w.SW_SHOWNOACTIVATE);
    _ = w.UpdateWindow(g.hwnd);
    _ = w.SetTimer(g.hwnd, TIMER_POLL, POLL_MS, null);
    registerHotkeys();
    addTrayIcon();

    if (g.docked) enterDockMode();

    load();

    var msg: w.MSG = .{};
    while (w.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
}
