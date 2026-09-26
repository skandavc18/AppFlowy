param(
  [string]$FlutterExecutable = 'flutter.bat',
  [ValidateSet('Release', 'Debug')]
  [string[]]$Configurations = @('Release', 'Debug'),
  [switch]$FlutterKeySimulation
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
Push-Location $appRoot
try {
  $flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
  $output = Join-Path $appRoot 'build/performance'
  New-Item -Path $output -ItemType Directory -Force | Out-Null
  $useOsKeys = !$FlutterKeySimulation
  $inputSuffix = if ($useOsKeys) { '' } else { '-flutter-keys' }
  $inputDescription = if ($useOsKeys) { 'guarded Windows Ctrl+F input' } else { 'Flutter key events only; NOT OS input verification' }
  Write-Host "Find fixture input: $inputDescription"
  foreach ($config in @('Release', 'Debug') | Where-Object { $_ -in $Configurations }) {
    if (@(Get-Process AppFlowy,MSBuild -ErrorAction SilentlyContinue).Count) {
      throw 'An app or build is running; nothing was closed or interrupted.'
    }
    $mode = $config.ToLower()
    $reportStem = "image-find-native-$mode$inputSuffix"
    $report = Join-Path $output "$reportStem.json"
    if (Test-Path $report) {
      Move-Item -LiteralPath $report -Destination "$report.$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').previous"
    }
    $include = 'build/windows/x64/include'
    if (Test-Path $include) {
      Move-Item -LiteralPath $include -Destination "${include}_image_find_${mode}_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
    }
    & $flutter build windows "--$mode" --no-pub `
      --target=integration_test/desktop/image_find_routing_native_test.dart `
      --dart-define=IMAGE_FIND_FIXTURE=true `
      "--dart-define=IMAGE_FIND_OS_KEYS=$($useOsKeys.ToString().ToLowerInvariant())" `
      "--dart-define=IMAGE_FIND_PROJECT_ROOT=$appRoot" `
      --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false 2>&1 |
      Tee-Object -FilePath (Join-Path $output "$reportStem-build.log")
    if ($LASTEXITCODE -ne 0) { throw "$config image-find fixture build failed." }

    $started = [DateTime]::UtcNow
    $exe = Join-Path $appRoot "build/windows/x64/runner/$config/AppFlowy.exe"
    $watcher = [IO.FileSystemWatcher]::new($output, (Split-Path -Leaf $report))
    $watcher.NotifyFilter = [IO.NotifyFilters]::Size -bor [IO.NotifyFilters]::LastWrite
    $watcher.EnableRaisingEvents = $true
    $process = $null
    try {
      $process = Start-Process -FilePath $exe -WorkingDirectory $appRoot -PassThru `
        -RedirectStandardOutput (Join-Path $output "$reportStem.out.log") `
        -RedirectStandardError (Join-Path $output "$reportStem.err.log")
      $null = $process.Handle
      $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::Changed, 300000)
      if ($change.TimedOut) { throw "$config image-find fixture exceeded five minutes." }
      $process.Refresh()
      if (-not $process.HasExited -and -not $process.CloseMainWindow()) {
        throw "$config fixture did not accept normal close."
      }
      if (-not $process.WaitForExit(30000)) { throw "$config fixture did not close normally." }
      $process.WaitForExit()
      if ($process.ExitCode -ne 0) { throw "$config fixture exit code $($process.ExitCode)." }
    } finally {
      $watcher.Dispose()
      # This PID is our synthetic test process, never an existing user app.
      if ($null -ne $process -and -not $process.HasExited) { $process.Kill() }
    }
    $file = Get-Item -LiteralPath $report
    $result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -DateKind String
    $cases = @($result.results.PSObject.Properties | Where-Object { $_.Name -match 'image Find with navigation focus=' })
    $pages = @($result.results.PSObject.Properties | Where-Object { $_.Name -match 'sidebar focus opens real Find|sidebar Find on' })
    $databases = @($result.results.PSObject.Properties | Where-Object { $_.Name -match 'page Find searches from navigation focus without a mouse' })
    if ($file.LastWriteTimeUtc -lt $started -or !$result.success -or $result.osFindKeys -ne $useOsKeys -or $result.mode -ne $mode -or $cases.Count -ne 12 -or $pages.Count -ne 8 -or $databases.Count -ne 3) {
      throw "$config image-find report is stale, incomplete or failed. See $report"
    }
    Write-Host "${config}: 12 image + 8 page/folder/collection + 3 keyboard-only database scenarios and database guard regressions passed ($inputDescription)."
  }
  Write-Host 'Native fixture complete. Rebuild BOTH normal bundles before launching AppFlowy.'
} finally {
  Pop-Location
}