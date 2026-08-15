# Captures a screenshot of the running AppFlowy window, for diagnosing what the
# app is actually showing when it appears unresponsive.
param(
    [string]$Out = 'C:\AppFlowy\appflowy_screen.png',
    [int]$WaitSeconds = 0
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$signature = @'
using System;
using System.Runtime.InteropServices;
public class WinApi {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
if (-not ('WinApi' -as [type])) { Add-Type -TypeDefinition $signature }

if ($WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }

$proc = Get-Process AppFlowy -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $proc) {
    Write-Output 'AppFlowy has no main window'
    exit 1
}

Write-Output "pid=$($proc.Id) title='$($proc.MainWindowTitle)' responding=$($proc.Responding)"

[WinApi]::ShowWindow($proc.MainWindowHandle, 3) | Out-Null
[WinApi]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 2

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Output "saved $Out ($((Get-Item $Out).Length) bytes)"
