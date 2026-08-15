# Sends a keystroke to AppFlowy and captures the result, to tell a frozen UI
# apart from one that only ignores the mouse.
param(
    [string]$Keys = '^p',
    [string]$Out = 'C:\AppFlowy\appflowy_keys.png'
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$signature = @'
using System;
using System.Runtime.InteropServices;
public class KeyApi {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
if (-not ('KeyApi' -as [type])) { Add-Type -TypeDefinition $signature }

$proc = Get-Process AppFlowy -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Output 'AppFlowy has no main window'; exit 1 }

[KeyApi]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait($Keys)
Start-Sleep -Seconds 2

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Output "sent '$Keys', saved $Out"
