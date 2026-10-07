//! Minimal hand-written Win32 bindings.
//!
//! We deliberately do NOT use @cImport/libc: that pulls in a static MinGW libc
//! and balloons the binary from ~30 KB to ~500 KB. Only the handful of
//! functions this app needs are declared here.

// ---------------------------------------------------------------------------
// Primitive types
// ---------------------------------------------------------------------------
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HMENU = *anyopaque;
pub const HBRUSH = *anyopaque;
pub const HFONT = *anyopaque;
pub const HDC = *anyopaque;
pub const HGDIOBJ = *anyopaque;

pub const ATOM = u16;
pub const UINT = u32;
pub const DWORD = u32;
pub const BOOL = i32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const LONG_PTR = isize;
pub const COLORREF = u32;

pub const PCWSTR = [*:0]const u16;
pub const PWSTR = [*:0]u16;

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
pub const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };

pub const MSG = extern struct {
    hwnd: HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
    lPrivate: DWORD = 0,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?PCWSTR,
    lpszClassName: PCWSTR,
    hIconSm: HICON,
};

// ---------------------------------------------------------------------------
// Window styles / ex-styles
// ---------------------------------------------------------------------------
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_VSCROLL: DWORD = 0x00200000;
pub const WS_EX_TOPMOST: DWORD = 0x00000008;
pub const WS_EX_TOOLWINDOW: DWORD = 0x00000080;
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;
pub const WS_EX_CLIENTEDGE: DWORD = 0x00000200;

pub const CS_HREDRAW: UINT = 0x0002;
pub const CS_VREDRAW: UINT = 0x0001;

pub const ES_AUTOHSCROLL: DWORD = 0x0080;

pub const LBS_NOTIFY: DWORD = 0x0001;
pub const LBS_HASSTRINGS: DWORD = 0x0040;

pub const SS_LEFT: DWORD = 0x00000000;

pub const SW_SHOWNOACTIVATE: i32 = 4;

pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;

pub const HWND_TOPMOST: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WA_INACTIVE: usize = 0;
pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_SETFOCUS: UINT = 0x0007;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KILLFOCUS: UINT = 0x0008;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_TIMER: UINT = 0x0113;
pub const WM_SETFONT: UINT = 0x0030;
pub const WM_GETTEXT: UINT = 0x000D;
pub const WM_SETTEXT: UINT = 0x000C;
pub const WM_HOTKEY: UINT = 0x0312;
pub const WM_NULL: UINT = 0x0000;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_LBUTTONDBLCLK: UINT = 0x0203;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_APP: UINT = 0x8000;
pub const WM_CTLCOLOREDIT: UINT = 0x0133;
pub const WM_CTLCOLORLISTBOX: UINT = 0x0134;
pub const WM_CTLCOLORBTN: UINT = 0x0135;
pub const WM_CTLCOLORSTATIC: UINT = 0x0138;

pub const LB_ADDSTRING: UINT = 0x0180;
pub const LB_DELETESTRING: UINT = 0x0182;
pub const LB_RESETCONTENT: UINT = 0x0184;
pub const LB_SETCURSEL: UINT = 0x0186;
pub const LB_GETCURSEL: UINT = 0x0188;
pub const LB_GETTEXT: UINT = 0x0189;
pub const LB_GETTEXTLEN: UINT = 0x018A;
pub const LB_GETCOUNT: UINT = 0x018B;
pub const LB_SETITEMHEIGHT: UINT = 0x01A0;
pub const LB_SETTOPINDEX: UINT = 0x0197;

pub const BN_CLICKED: u16 = 0;
pub const LBN_DBLCLK: u16 = 2;
pub const LB_ERR: LRESULT = -1;

// ---------------------------------------------------------------------------
// Keys / hotkeys
// ---------------------------------------------------------------------------
pub const VK_RETURN: WPARAM = 0x0D;
pub const VK_ESCAPE: WPARAM = 0x1B;
pub const VK_DELETE: WPARAM = 0x2E;

pub const MOD_ALT: UINT = 0x0001;
pub const MOD_CONTROL: UINT = 0x0002;
pub const MOD_SHIFT: UINT = 0x0004;
pub const MOD_NOREPEAT: UINT = 0x4000;
pub const MOD_WIN: UINT = 0x0008;

// System tray / popup menu
pub const NIM_ADD: DWORD = 0;
pub const NIM_MODIFY: DWORD = 1;
pub const NIM_DELETE: DWORD = 2;
pub const NIF_MESSAGE: UINT = 0x0001;
pub const NIF_ICON: UINT = 0x0002;
pub const NIF_TIP: UINT = 0x0004;
pub const MF_STRING: UINT = 0x0000;
pub const TPM_RIGHTBUTTON: UINT = 0x0002;
pub const LR_DEFAULTCOLOR: UINT = 0x0000;
pub const IDI_APPLICATION: usize = 32512;
pub const RT_ICON: DWORD = 3;
pub const RT_ICON_VERSION: DWORD = 0x00030000;
pub const IMAGE_ICON: UINT = 1;

// ---------------------------------------------------------------------------
// Misc constants
// ---------------------------------------------------------------------------
pub const SM_CXSCREEN: i32 = 0;
pub const SM_CYSCREEN: i32 = 1;

pub const GWLP_WNDPROC: i32 = -4;
pub const GWLP_USERDATA: i32 = -21;

pub const IDC_ARROW: usize = 32512;

pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const CREATE_ALWAYS: DWORD = 2;
pub const OPEN_EXISTING: DWORD = 3;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x00000080;
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub const TRANSPARENT: i32 = 1;

pub const GUID = extern struct {
    data1: u32 = 0,
    data2: u16 = 0,
    data3: u16 = 0,
    data4: [8]u8 = [_]u8{0} ** 8,
};

pub const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = 0,
    hWnd: HWND = null,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: HICON = null,
    szTip: [128]u16 = [_]u16{0} ** 128,
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = [_]u16{0} ** 256,
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = [_]u16{0} ** 64,
    dwInfoFlags: DWORD = 0,
    guidItem: GUID = .{},
    hBalloonIcon: HICON = null,
};

pub const FW_NORMAL: i32 = 400;
pub const FW_SEMIBOLD: i32 = 600;
pub const DEFAULT_CHARSET: DWORD = 1;
pub const CLEARTYPE_QUALITY: DWORD = 5;
pub const DEFAULT_PITCH: DWORD = 0;

// ---------------------------------------------------------------------------
// kernel32
// ---------------------------------------------------------------------------
pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?PCWSTR) callconv(.winapi) HINSTANCE;
pub extern "kernel32" fn GetModuleFileNameW(hModule: HINSTANCE, lpFilename: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateFileW(
    lpFileName: PCWSTR,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: HANDLE,
) callconv(.winapi) HANDLE;
pub extern "kernel32" fn ReadFile(
    hFile: HANDLE,
    lpBuffer: [*]u8,
    nNumberOfBytesToRead: DWORD,
    lpNumberOfBytesRead: *DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(
    hFile: HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: DWORD,
    lpNumberOfBytesWritten: *DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) BOOL;
pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// user32
// ---------------------------------------------------------------------------
pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: ?PCWSTR,
    lpWindowName: ?PCWSTR,
    dwStyle: DWORD,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) HWND;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetTimer(hWnd: HWND, nIDEvent: usize, uElapse: UINT, lpTimerFunc: ?*anyopaque) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(hWnd: HWND, uIDEvent: usize) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn RegisterHotKey(hWnd: HWND, id: i32, fsModifiers: UINT, vk: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn UnregisterHotKey(hWnd: HWND, id: i32) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(.winapi) HWND;
pub extern "user32" fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: ?*DWORD) callconv(.winapi) DWORD;
pub extern "user32" fn AttachThreadInput(idAttach: DWORD, idAttachTo: DWORD, fAttach: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn BringWindowToTop(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: PCWSTR) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "user32" fn FindWindowW(lpClassName: ?PCWSTR, lpWindowName: ?PCWSTR) callconv(.winapi) HWND;
pub extern "shell32" fn SHGetKnownFolderPath(rfid: *const GUID, dwFlags: DWORD, hToken: HANDLE, ppszPath: *PWSTR) callconv(.winapi) i32;
pub extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;
pub const ERROR_ALREADY_EXISTS: DWORD = 183;
pub extern "user32" fn SetFocus(hWnd: HWND) callconv(.winapi) HWND;
pub extern "user32" fn GetFocus() callconv(.winapi) HWND;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) LONG_PTR;
pub extern "user32" fn CallWindowProcW(lpPrevWndFunc: WNDPROC, hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: PCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn GetSystemMetrics(nIndex: i32) callconv(.winapi) i32;
pub extern "user32" fn SystemParametersInfoW(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT) callconv(.winapi) BOOL;
pub const SPI_GETWORKAREA: UINT = 0x0030;
pub extern "user32" fn SetProcessDPIAware() callconv(.winapi) BOOL;
pub extern "user32" fn GetDpiForSystem() callconv(.winapi) UINT;
pub extern "user32" fn LoadCursorW(hInstance: HINSTANCE, lpCursorName: ?*const anyopaque) callconv(.winapi) HCURSOR;
pub extern "user32" fn MessageBeep(uType: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?PCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: ?*const RECT) callconv(.winapi) BOOL;
pub extern "user32" fn CreateIconFromResourceEx(presbits: [*]const u8, dwResSize: DWORD, fIcon: BOOL, dwVer: DWORD, cxDesired: i32, cyDesired: i32, flags: UINT) callconv(.winapi) HICON;
pub extern "user32" fn LoadIconW(hInstance: HINSTANCE, lpIconName: ?PCWSTR) callconv(.winapi) HICON;
pub extern "user32" fn DestroyIcon(hIcon: HICON) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// shell32
// ---------------------------------------------------------------------------
pub extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *const NOTIFYICONDATAW) callconv(.winapi) BOOL;

pub const PAINTSTRUCT = extern struct {
    hdc: HDC = undefined,
    fErase: BOOL = 0,
    rcPaint: RECT = .{},
    fRestore: BOOL = 0,
    fIncUpdate: BOOL = 0,
    rgbReserved: [32]u8 = [_]u8{0} ** 32,
};

// ---------------------------------------------------------------------------
// gdi32
// ---------------------------------------------------------------------------
pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.winapi) HBRUSH;
pub extern "gdi32" fn CreateFontW(
    cHeight: i32,
    cWidth: i32,
    cEscapement: i32,
    cOrientation: i32,
    cWeight: i32,
    bItalic: DWORD,
    bUnderline: DWORD,
    bStrikeOut: DWORD,
    iCharSet: DWORD,
    iOutPrecision: DWORD,
    iClipPrecision: DWORD,
    iQuality: DWORD,
    iPitchAndFamily: DWORD,
    pszFaceName: PCWSTR,
) callconv(.winapi) HFONT;
pub extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(.winapi) HGDIOBJ;
pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
pub extern "gdi32" fn SetBkColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
pub extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) i32;

// ---------------------------------------------------------------------------
// Redesign additions: mouse/keyboard, double buffering, custom drawing
// ---------------------------------------------------------------------------
pub const HBITMAP = *anyopaque;
pub const HPEN = *anyopaque;

pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_RBUTTONDOWN: UINT = 0x0204;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WM_MOUSELEAVE: UINT = 0x02A3;
pub const WM_SETCURSOR: UINT = 0x0020;
pub const WM_SIZE: UINT = 0x0005;

pub const VK_SHIFT: WPARAM = 0x10;
pub const VK_CONTROL: WPARAM = 0x11;
pub const VK_MENU: WPARAM = 0x12;
pub const VK_BACK: WPARAM = 0x08;
pub const VK_TAB: WPARAM = 0x09;
pub const VK_SPACE: WPARAM = 0x20;
pub const VK_PRIOR: WPARAM = 0x21;
pub const VK_NEXT: WPARAM = 0x22;
pub const VK_END: WPARAM = 0x23;
pub const VK_HOME: WPARAM = 0x24;
pub const VK_LEFT: WPARAM = 0x25;
pub const VK_UP: WPARAM = 0x26;
pub const VK_RIGHT: WPARAM = 0x27;
pub const VK_DOWN: WPARAM = 0x28;
pub const VK_E: WPARAM = 0x45;
pub const VK_J: WPARAM = 0x4A;
pub const VK_K: WPARAM = 0x4B;

pub const SRCCOPY: DWORD = 0x00CC0020;

pub const DT_LEFT: UINT = 0x0000;
pub const DT_CENTER: UINT = 0x0001;
pub const DT_RIGHT: UINT = 0x0002;
pub const DT_VCENTER: UINT = 0x0004;
pub const DT_SINGLELINE: UINT = 0x0020;
pub const DT_NOPREFIX: UINT = 0x0800;
pub const DT_END_ELLIPSIS: UINT = 0x8000;

pub const NULL_PEN: i32 = 8;
pub const NULL_BRUSH: i32 = 5;
pub const PS_SOLID: i32 = 0;

pub const FW_MEDIUM: i32 = 500;
pub const FW_BOLD: i32 = 700;

pub const IDC_HAND: usize = 32649;
pub const IDC_SIZEWE: usize = 32644;
pub const TME_LEAVE: DWORD = 0x00000002;
pub const SW_HIDE: i32 = 0;
pub const SW_SHOW: i32 = 5;

pub const EM_SETMARGINS: UINT = 0x00D3;
pub const EM_SETSEL: UINT = 0x00B1;
pub const EC_LEFTMARGIN: WPARAM = 0x0001;
pub const EC_RIGHTMARGIN: WPARAM = 0x0002;

pub const TRACKMOUSEEVENT = extern struct {
    cbSize: DWORD = @sizeOf(TRACKMOUSEEVENT),
    dwFlags: DWORD = 0,
    hwndTrack: HWND = null,
    dwHoverTime: DWORD = 0,
};

pub extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(.winapi) HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: i32, cy: i32) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn BitBlt(dst: HDC, x: i32, y: i32, cx: i32, cy: i32, src: HDC, sx: i32, sy: i32, rop: DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreatePen(style: i32, width: i32, color: COLORREF) callconv(.winapi) HPEN;
pub extern "gdi32" fn MoveToEx(hdc: HDC, x: i32, y: i32, prev: ?*POINT) callconv(.winapi) BOOL;
pub extern "gdi32" fn LineTo(hdc: HDC, x: i32, y: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn RoundRect(hdc: HDC, l: i32, t: i32, r: i32, b: i32, ew: i32, eh: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn DrawTextW(hdc: HDC, text: [*]const u16, count: i32, rc: *RECT, format: UINT) callconv(.winapi) i32;
pub extern "gdi32" fn GetStockObject(i: i32) callconv(.winapi) HGDIOBJ;
pub extern "gdi32" fn SaveDC(hdc: HDC) callconv(.winapi) i32;
pub extern "gdi32" fn RestoreDC(hdc: HDC, saved: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn IntersectClipRect(hdc: HDC, l: i32, t: i32, r: i32, b: i32) callconv(.winapi) i32;

pub extern "user32" fn SetCapture(hWnd: HWND) callconv(.winapi) HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
pub extern "user32" fn GetCapture() callconv(.winapi) HWND;
pub extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.winapi) i16;
pub extern "user32" fn TrackMouseEvent(tme: *TRACKMOUSEEVENT) callconv(.winapi) BOOL;
pub extern "user32" fn SetCursor(hCursor: HCURSOR) callconv(.winapi) HCURSOR;
pub extern "user32" fn MoveWindow(hWnd: HWND, x: i32, y: i32, w: i32, h: i32, repaint: BOOL) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// winmm (microphone capture for dictation)
// ---------------------------------------------------------------------------
pub const HWAVEIN = ?*anyopaque;

pub const WAVEHDR = extern struct {
    lpData: [*]u8 = undefined,
    dwBufferLength: DWORD = 0,
    dwBytesRecorded: DWORD = 0,
    dwUser: usize = 0,
    dwFlags: DWORD = 0,
    dwLoops: DWORD = 0,
    lpNext: ?*WAVEHDR = null,
    reserved: usize = 0,
};

pub const WAVEFORMATEX = extern struct {
    wFormatTag: u16 = 1,
    nChannels: u16 = 1,
    nSamplesPerSec: DWORD = 16000,
    nAvgBytesPerSec: DWORD = 32000,
    nBlockAlign: u16 = 2,
    wBitsPerSample: u16 = 16,
    cbSize: u16 = 0,
};

pub const WAVE_MAPPER: UINT = 0xFFFFFFFF;
pub const CALLBACK_FUNCTION: DWORD = 0x00030000;
pub const WOM_DONE: UINT = 0x03BD;

pub extern "winmm" fn waveInOpen(phwi: *HWAVEIN, uDeviceID: UINT, pwfx: *WAVEFORMATEX, dwCallback: usize, dwInstance: usize, fdwOpen: DWORD) callconv(.winapi) UINT;
pub extern "winmm" fn waveInPrepareHeader(hwi: HWAVEIN, pwh: *WAVEHDR, cbwh: UINT) callconv(.winapi) UINT;
pub extern "winmm" fn waveInUnprepareHeader(hwi: HWAVEIN, pwh: *WAVEHDR, cbwh: UINT) callconv(.winapi) UINT;
pub extern "winmm" fn waveInAddBuffer(hwi: HWAVEIN, pwh: *WAVEHDR, cbwh: UINT) callconv(.winapi) UINT;
pub extern "winmm" fn waveInStart(hwi: HWAVEIN) callconv(.winapi) UINT;
pub extern "winmm" fn waveInStop(hwi: HWAVEIN) callconv(.winapi) UINT;
pub extern "winmm" fn waveInReset(hwi: HWAVEIN) callconv(.winapi) UINT;
pub extern "winmm" fn waveInClose(hwi: HWAVEIN) callconv(.winapi) UINT;

// ---------------------------------------------------------------------------
// winhttp (Deepgram HTTPS)
// ---------------------------------------------------------------------------
pub const HINTERNET = ?*anyopaque;
pub const WINHTTP_FLAG_SECURE: DWORD = 0x00800000;
pub const WINHTTP_ACCESS_TYPE_DEFAULT_PROXY: DWORD = 0;
pub const WINHTTP_QUERY_STATUS_CODE: DWORD = 19;

pub extern "winhttp" fn WinHttpOpen(agent: ?PCWSTR, access: DWORD, proxy: ?PCWSTR, bypass: ?PCWSTR, flags: DWORD) callconv(.winapi) HINTERNET;
pub extern "winhttp" fn WinHttpConnect(session: HINTERNET, server: PCWSTR, port: u16, reserved: DWORD) callconv(.winapi) HINTERNET;
pub extern "winhttp" fn WinHttpOpenRequest(connect: HINTERNET, verb: ?PCWSTR, object: PCWSTR, version: ?PCWSTR, referrer: ?PCWSTR, accept: ?*const ?PCWSTR, flags: DWORD) callconv(.winapi) HINTERNET;
pub extern "winhttp" fn WinHttpSendRequest(req: HINTERNET, headers: ?PCWSTR, headers_len: i32, optional: ?*const anyopaque, optional_len: DWORD, total_len: DWORD, context: usize) callconv(.winapi) BOOL;
pub extern "winhttp" fn WinHttpReceiveResponse(req: HINTERNET, reserved: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "winhttp" fn WinHttpReadData(req: HINTERNET, buffer: [*]u8, to_read: DWORD, read: *DWORD) callconv(.winapi) BOOL;
pub extern "winhttp" fn WinHttpSetTimeouts(session: HINTERNET, resolve: i32, connect: i32, send: i32, receive: i32) callconv(.winapi) BOOL;
pub extern "winhttp" fn WinHttpCloseHandle(h: HINTERNET) callconv(.winapi) BOOL;

pub extern "kernel32" fn GetEnvironmentVariableW(lpName: PCWSTR, lpBuffer: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;

// ---------------------------------------------------------------------------
// AppBar protocol (reserve desktop space, like the taskbar)
// ---------------------------------------------------------------------------
pub const APPBARDATA = extern struct {
    cbSize: DWORD = 0,
    hWnd: HWND = null,
    uCallbackMessage: UINT = 0,
    uEdge: UINT = 0,
    rc: RECT = .{},
    lParam: LPARAM = 0,
};

pub const ABM_NEW: DWORD = 0;
pub const ABM_REMOVE: DWORD = 1;
pub const ABM_QUERYPOS: DWORD = 2;
pub const ABM_SETPOS: DWORD = 3;
pub const ABM_GETTASKBARPOS: DWORD = 5;

pub const ABE_LEFT: UINT = 0;
pub const ABE_TOP: UINT = 1;
pub const ABE_RIGHT: UINT = 2;
pub const ABE_BOTTOM: UINT = 3;

pub const ABN_STATECHANGE: UINT = 0;
pub const ABN_POSCHANGED: UINT = 1;
pub const ABN_FULLSCREENAPP: UINT = 2;

pub const MF_CHECKED: UINT = 0x0008;

pub extern "shell32" fn SHAppBarMessage(dwMessage: DWORD, pData: *APPBARDATA) callconv(.winapi) usize;
pub extern "kernel32" fn CreateDirectoryW(lpPathName: PCWSTR, lpSecurityAttributes: ?*anyopaque) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// Console / command line / file metadata (for the CLI and file watching)
// ---------------------------------------------------------------------------
pub const STD_OUTPUT_HANDLE: DWORD = 0xFFFFFFF5;
pub const STD_ERROR_HANDLE: DWORD = 0xFFFFFFF4;
pub const GetFileExInfoStandard: i32 = 0;

pub const FILETIME = extern struct { dwLowDateTime: DWORD = 0, dwHighDateTime: DWORD = 0 };
pub const WIN32_FILE_ATTRIBUTE_DATA = extern struct {
    dwFileAttributes: DWORD = 0,
    ftCreationTime: FILETIME = .{},
    ftLastAccessTime: FILETIME = .{},
    ftLastWriteTime: FILETIME = .{},
    nFileSizeHigh: DWORD = 0,
    nFileSizeLow: DWORD = 0,
};

pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]u16;
pub extern "shell32" fn CommandLineToArgvW(lpCmdLine: PCWSTR, pNumArgs: *i32) callconv(.winapi) ?[*]PWSTR;
pub extern "kernel32" fn LocalFree(hMem: HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetFileAttributesExW(lpFileName: PCWSTR, fInfoLevelId: i32, lpFileInformation: *anyopaque) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// System theme (light / dark)
// ---------------------------------------------------------------------------
pub const HKEY = ?*anyopaque;
pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
pub const RRF_RT_REG_DWORD: DWORD = 0x00000010;
pub const WM_SETTINGCHANGE: UINT = 0x001A;
pub const WM_THEMECHANGED: UINT = 0x031A;
pub extern "advapi32" fn RegGetValueW(hkey: HKEY, lpSubKey: ?PCWSTR, lpValue: ?PCWSTR, dwFlags: DWORD, pdwType: ?*DWORD, pvData: ?*anyopaque, pcbData: ?*DWORD) callconv(.winapi) i32;
