Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$exe = Join-Path $PSScriptRoot '..\zig-out\bin\zigtodo.exe'
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Milliseconds 900

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

function Shot($path) {
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function MoveTo($x, $y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y)
}

function CpuOverMs($ms) {
    $c1 = $p.TotalProcessorTime.TotalMilliseconds
    Start-Sleep -Milliseconds $ms
    $p.Refresh()
    return [math]::Round($p.TotalProcessorTime.TotalMilliseconds - $c1, 1)
}

# 1) mouse parked in the middle -> panel should be collapsed
MoveTo ($b.X + $b.Width / 2) ($b.Y + $b.Height / 2)
Start-Sleep -Milliseconds 600
Shot (Join-Path $PSScriptRoot 'shot_collapsed.png')
$cpuCollapsed = CpuOverMs 3000

# 2) mouse touching the right edge -> panel should slide out
MoveTo ($b.Right - 1) ($b.Y + $b.Height / 2)
Start-Sleep -Milliseconds 900
Shot (Join-Path $PSScriptRoot 'shot_expanded.png')
$cpuExpanded = CpuOverMs 3000

Write-Host ("CPU_collapsed = {0} ms / 3 s" -f $cpuCollapsed)
Write-Host ("CPU_expanded  = {0} ms / 3 s" -f $cpuExpanded)
Write-Host ("WorkingSetMB  = " + [math]::Round($p.WorkingSet64 / 1MB, 1))
Write-Host ("PrivateMB     = " + [math]::Round($p.PrivateMemorySize64 / 1MB, 1))
Write-Host ("Threads       = " + $p.Threads.Count)

Stop-Process -Id $p.Id -Force
