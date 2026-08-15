# Clicks a point inside the AppFlowy window (given as a fraction of the window)
# and captures the result, to check whether the app responds to input at all.
param(
    [double]$X = 0.05,
    [double]$Y = 0.18,
    [string]$Out = 'C:\AppFlowy\appflowy_click.png'
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$signature = @'
using System;
using System.Runtime.InteropServices;
public class ClickApi {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    public struct RECT { public int Left, Top, Right, Bottom; }
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP = 0x0004;
}
'@
if (-not ('ClickApi' -as [type])) { Add-Type -TypeDefinition $signature }

$proc = Get-Process AppFlowy -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Output 'AppFlowy has no main window'; exit 1 }

[ClickApi]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 700

$rect = New-Object ClickApi+RECT
[ClickApi]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
$px = [int]($rect.Left + $w * $X)
$py = [int]($rect.Top + $h * $Y)
Write-Output "window=($($rect.Left),$($rect.Top))-($($rect.Right),$($rect.Bottom)) size=${w}x${h} click=($px,$py)"

[ClickApi]::SetCursorPos($px, $py) | Out-Null
Start-Sleep -Milliseconds 250
[ClickApi]::mouse_event([ClickApi]::LEFTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 60
[ClickApi]::mouse_event([ClickApi]::LEFTUP, 0, 0, 0, 0)
Start-Sleep -Seconds 2

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Output "saved $Out"
