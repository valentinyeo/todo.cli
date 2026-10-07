Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class K {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  static void Down(byte k){ keybd_event(k,0,0,UIntPtr.Zero); }
  static void Up(byte k){ keybd_event(k,0,2,UIntPtr.Zero); }
  public static void CtrlAltKey(byte key){
    Down(0x11); Down(0x12); Down(key); Up(key); Up(0x12); Up(0x11);   // Ctrl + Alt + key
  }
}
'@

$exe = Join-Path $PSScriptRoot '..\zig-out\bin\zigtodo.exe'
$todo = Join-Path $PSScriptRoot '..\zig-out\bin\todos.txt'
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Milliseconds 900

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]($b.X + $b.Width/2), [int]($b.Y + $b.Height/2))
Start-Sleep -Milliseconds 400

# Fire the global hotkey with genuine injected input: Ctrl+Alt+Space
[K]::CtrlAltKey(0x20)
Start-Sleep -Milliseconds 800

# The panel should now have focus; type and commit.
[System.Windows.Forms.SendKeys]::SendWait('tray and hotkey work{ENTER}')
Start-Sleep -Milliseconds 800

$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
$bmp.Save((Join-Path $PSScriptRoot 'shot_hotkey.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# crop the tray corner (bottom-right) and scale up 4x
$cw = 460; $ch = 90
$crop = New-Object System.Drawing.Bitmap($cw, $ch)
$cg = [System.Drawing.Graphics]::FromImage($crop)
$cg.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0,0,$cw,$ch)), (New-Object System.Drawing.Rectangle(($b.Width-$cw), ($b.Height-$ch), $cw, $ch)), [System.Drawing.GraphicsUnit]::Pixel)
$big = New-Object System.Drawing.Bitmap(($cw*3), ($ch*3))
$bg = [System.Drawing.Graphics]::FromImage($big)
$bg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$bg.DrawImage($crop, 0, 0, ($cw*3), ($ch*3))
$big.Save((Join-Path $PSScriptRoot 'shot_tray.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $cg.Dispose(); $crop.Dispose(); $bg.Dispose(); $big.Dispose()

Stop-Process -Id $p.Id -Force
Start-Sleep -Milliseconds 300
Write-Host "--- todos.txt ---"
Get-Content $todo
