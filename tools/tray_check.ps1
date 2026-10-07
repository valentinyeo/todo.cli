Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Tray {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct NII { public uint cbSize; public IntPtr hWnd; public uint uID; public Guid guidItem; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string win);
  [DllImport("shell32.dll")] public static extern int Shell_NotifyIconGetRect(ref NII id, out RECT rc);
  public static string Check() {
    IntPtr h = FindWindow("ZigTodoPanel", null);
    if (h == IntPtr.Zero) return "window not found";
    NII id = new NII();
    id.cbSize = (uint)Marshal.SizeOf(typeof(NII));
    id.hWnd = h; id.uID = 1;
    RECT rc;
    int hr = Shell_NotifyIconGetRect(ref id, out rc);
    if (hr != 0) return "Shell_NotifyIconGetRect hr=0x" + hr.ToString("X8");
    return "registered, rect=(" + rc.left + "," + rc.top + ")-(" + rc.right + "," + rc.bottom + ")";
  }
}
'@

$exe = Join-Path $PSScriptRoot '..\zig-out\bin\zigtodo.exe'
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Milliseconds 1200
Write-Host ("tray icon: " + [Tray]::Check())
Stop-Process -Id $p.Id -Force
