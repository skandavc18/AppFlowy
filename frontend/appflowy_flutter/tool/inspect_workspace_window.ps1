param(
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [string]$Keys,
  [double]$ClickX = -1,
  [double]$ClickY = -1
)

# Capture only the requested AppFlowy window, including at non-100% DPI.
# Optional input is a deliberate UI audit action, never a workspace-data edit.
# No sleeps, process termination, preferences, or native backend calls.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
if (-not ('WorkspaceWindowAudit' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WorkspaceWindowAudit {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
}
'@
}

$app = Get-Process -Id $ProcessId
if ($app.ProcessName -ne 'AppFlowy' -or $app.MainWindowHandle -eq 0) {
  throw 'The requested process is not an AppFlowy window.'
}
$window = $app.MainWindowHandle
$previousDpi = [WorkspaceWindowAudit]::SetThreadDpiAwarenessContext([IntPtr](-4))
try {
  $rect = [WorkspaceWindowAudit+Rect]::new()
  if (-not [WorkspaceWindowAudit]::GetWindowRect($window, [ref]$rect)) {
    throw 'Unable to measure the AppFlowy window.'
  }
  if ($Keys -or $ClickX -ge 0 -or $ClickY -ge 0) {
    [WorkspaceWindowAudit]::SetForegroundWindow($window) | Out-Null
    if ([WorkspaceWindowAudit]::GetForegroundWindow() -ne $window) {
      throw 'AppFlowy did not gain focus; refusing to send input to another app.'
    }
    if ($ClickX -ge 0 -or $ClickY -ge 0) {
      if ($ClickX -lt 0 -or $ClickX -gt 1 -or $ClickY -lt 0 -or $ClickY -gt 1) {
        throw 'Click coordinates must both be fractions within the window.'
      }
      $cursor = [WorkspaceWindowAudit+Point]::new()
      [WorkspaceWindowAudit]::GetCursorPos([ref]$cursor) | Out-Null
      try {
        [WorkspaceWindowAudit]::SetCursorPos(
          [int]($rect.Left + ($rect.Right - $rect.Left) * $ClickX),
          [int]($rect.Top + ($rect.Bottom - $rect.Top) * $ClickY)
        ) | Out-Null
        [WorkspaceWindowAudit]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [WorkspaceWindowAudit]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
      } finally {
        [WorkspaceWindowAudit]::SetCursorPos($cursor.X, $cursor.Y) | Out-Null
      }
    }
    if ($Keys) { [System.Windows.Forms.SendKeys]::SendWait($Keys) }
    # This waits for the native message queue, not a fixed animation delay.
    $app.WaitForInputIdle(10000) | Out-Null
  }

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) { throw 'The window has no capture area.' }
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $dc = $graphics.GetHdc()
    try {
      if (-not [WorkspaceWindowAudit]::PrintWindow($window, $dc, 2)) {
        throw 'Windows refused to capture the app window.'
      }
    } finally { $graphics.ReleaseHdc($dc) }
    $absolute = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($absolute)) | Out-Null
    $bitmap.Save($absolute, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
  $app.Refresh()
  [pscustomobject]@{
    ProcessId = $app.Id
    Executable = $app.Path
    Responding = $app.Responding
    StartedUtc = $app.StartTime.ToUniversalTime().ToString('o')
    CapturedUtc = [DateTime]::UtcNow.ToString('o')
    Width = $width
    Height = $height
    Image = $absolute
  }
} finally {
  [WorkspaceWindowAudit]::SetThreadDpiAwarenessContext($previousDpi) | Out-Null
}