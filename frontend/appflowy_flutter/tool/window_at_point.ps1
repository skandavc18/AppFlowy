# Reports which window owns a screen point, to find anything sitting invisibly
# on top of the app and swallowing clicks.
param(
    [int]$X = 94,
    [int]$Y = 236
)

$signature = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class HitApi {
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    public struct POINT { public int X, Y; }
}
'@
if (-not ('HitApi' -as [type])) { Add-Type -TypeDefinition $signature }

$point = New-Object HitApi+POINT
$point.X = $X
$point.Y = $Y

$hWnd = [HitApi]::WindowFromPoint($point)
$root = [HitApi]::GetAncestor($hWnd, 2)

foreach ($h in @(@{n = 'at point'; h = $hWnd }, @{n = 'root window'; h = $root })) {
    $title = New-Object System.Text.StringBuilder 256
    $class = New-Object System.Text.StringBuilder 256
    [HitApi]::GetWindowText($h.h, $title, 256) | Out-Null
    [HitApi]::GetClassName($h.h, $class, 256) | Out-Null
    $pid = 0
    [HitApi]::GetWindowThreadProcessId($h.h, [ref]$pid) | Out-Null
    $proc = (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName
    $exStyle = [HitApi]::GetWindowLong($h.h, -20)
    $layered = ($exStyle -band 0x00080000) -ne 0
    $transparent = ($exStyle -band 0x00000020) -ne 0
    $topmost = ($exStyle -band 0x00000008) -ne 0
    Write-Output ("{0,-12} hwnd={1} proc={2} class='{3}' title='{4}' layered={5} transparent={6} topmost={7}" -f `
            $h.n, $h.h, $proc, $class.ToString(), $title.ToString(), $layered, $transparent, $topmost)
}
