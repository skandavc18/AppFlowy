param(
  [string]$FlutterExecutable = 'flutter.bat',
  [ValidateSet('Release', 'Debug')]
  [string[]]$Configurations = @('Release', 'Debug')
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
Push-Location $appRoot
try {
  $flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
  $output = Join-Path $appRoot 'build/performance'
  New-Item -Path $output -ItemType Directory -Force | Out-Null
  foreach ($config in @('Release', 'Debug') | Where-Object { $_ -in $Configurations }) {
    if (@(Get-Process AppFlowy -ErrorAction SilentlyContinue).Count -gt 0) {
      throw 'Close AppFlowy before building the isolated feature-parity fixture.'
    }
    if (@(Get-Process MSBuild -ErrorAction SilentlyContinue).Count -gt 0) {
      throw 'Another MSBuild is running; do not overlap builds.'
    }
    $mode = $config.ToLower()
    $report = Join-Path $output "build-mode-parity-$mode.json"
    if (Test-Path $report) {
      Move-Item -LiteralPath $report -Destination "$report.$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').previous"
    }
    $include = 'build/windows/x64/include'
    if (Test-Path $include) {
      Move-Item -LiteralPath $include -Destination "${include}_parity_${mode}_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
    }
    & $flutter build windows "--$mode" --no-pub `
      --target=integration_test/performance/build_mode_feature_parity_test.dart `
      --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false 2>&1 |
      Tee-Object -FilePath (Join-Path $output "build-mode-parity-$mode-build.log")
    if ($LASTEXITCODE -ne 0) { throw "$config parity fixture build failed." }

    $started = [DateTime]::UtcNow
    $exe = Join-Path $appRoot "build/windows/x64/runner/$config/AppFlowy.exe"
    $watcher = [IO.FileSystemWatcher]::new($output, (Split-Path -Leaf $report))
    $watcher.NotifyFilter = [IO.NotifyFilters]::Size -bor [IO.NotifyFilters]::LastWrite
    $watcher.EnableRaisingEvents = $true
    $process = $null
    try {
      $process = Start-Process -FilePath $exe -WorkingDirectory $appRoot -PassThru `
        -RedirectStandardOutput (Join-Path $output "build-mode-parity-$mode.out.log") `
        -RedirectStandardError (Join-Path $output "build-mode-parity-$mode.err.log")
      # Retain the OS handle so ExitCode is available even after it ends.
      $null = $process.Handle
      $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::Changed, 180000)
      if ($change.TimedOut) {
        throw "$config feature-parity tests exceeded three minutes. See $output."
      }
      # SystemNavigator.pop does not close this Windows runner. Close only
      # our completed fixture through its ordinary WM_CLOSE teardown path.
      $process.Refresh()
      if (-not $process.HasExited -and -not $process.CloseMainWindow()) {
        throw "$config test window did not accept its close request."
      }
      if (-not $process.WaitForExit(30000)) {
        throw "$config test window failed to close normally."
      }
      $process.WaitForExit()
      if ($process.ExitCode -ne 0) {
        throw "$config feature-parity fixture exited $($process.ExitCode). See $output."
      }
    } finally {
      $watcher.Dispose()
      # A failing fixture is ours, never the user's normal app instance.
      if ($null -ne $process -and -not $process.HasExited) { $process.Kill() }
    }
    $file = Get-Item -LiteralPath $report
    $result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if ($file.LastWriteTimeUtc -lt $started -or -not $result.success -or
        $result.mode -ne $mode -or $result.caseCount -ne 25) {
      throw "$config feature-parity report is stale, incomplete or failed."
    }
    Write-Host "${config}: $($result.caseCount) isolated feature-parity cases passed."
  }
  Write-Host 'Rebuild normal bundles with tool/build_windows_bundles.ps1 before launching the app.'
} finally {
  Pop-Location
}