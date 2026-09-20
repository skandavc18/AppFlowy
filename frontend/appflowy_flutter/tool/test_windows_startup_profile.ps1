#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$script = Get-Content (Join-Path $PSScriptRoot 'profile_windows_startup.ps1') -Raw
$source = [regex]::Match($script, "(?s)\`$measurementSource = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if ([string]::IsNullOrWhiteSpace($source)) { throw 'Startup capture helper not found.' }
if (-not ('AppFlowy.StartupProfiling.V1.MeasurementRunner' -as [type])) {
  Add-Type -TypeDefinition $source
}
$type = 'AppFlowy.StartupProfiling.V1.MeasurementRunner' -as [type]
$static = [Reflection.BindingFlags]'Static, NonPublic'
$instance = [Reflection.BindingFlags]'Instance, NonPublic'
$parse = $type.GetMethod('ParsePhase', $static)
$checks = 0

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
  $script:checks++
}

function Parse-Phase([string]$Json) {
  $parse.Invoke($null, @("AF_STARTUP $Json", [double]12.5))
}

$valid = Parse-Phase '{"phase":"sdk.native_init","elapsed_us":1250,"duration_us":1200,"succeeded":true}'
Assert-True ($valid.phase -eq 'sdk.native_init' -and $valid.duration_us -eq 1200 -and
  $valid.elapsed_us -eq 1250 -and $valid.arrival_ms -eq 12.5 -and $valid.succeeded) 'Valid phase rejected.'
foreach ($json in @(
  '[]',
  '{}',
  '{"phase":"sdk","elapsed_us":-1}',
  '{"phase":"sdk","elapsed_us":1.5}',
  '{"phase":"sdk","elapsed_us":1,"duration_us":-1}',
  '{"phase":"sdk","elapsed_us":1,"succeeded":"true"}',
  '{"phase":"sdk","elapsed_us":1,"content":"FAKE_PRIVATE_DATA"}',
  '{"phase":"sdk","elapsed_us":1,"phase":"other"}',
  '{"phase":"path/FAKE_PRIVATE_DATA","elapsed_us":1}',
  '{"phase":"application_launch","elapsed_us":1}',
  '{"phase":"application_launch","elapsed_us":1,"duration_us":1}',
  '{"phase":null,"elapsed_us":1}',
  '{'
)) {
  # A null phase is rejected by the capture callback even if a regex throws.
  $record = $null
  try { $record = Parse-Phase $json } catch { }
  Assert-True ($null -eq $record) 'Invalid/private marker was accepted.'
}

# Exercise capture in memory, never Execute/Process.Start. The private helper's
# constructor allocates handles only; cleanup releases them without closing apps.
$constructor = $type.GetConstructor($instance, $null, @([string], [int]), $null)
$fixtureExecutable = [string](Join-Path $PSScriptRoot 'AppFlowy.exe')
$capture = $constructor.Invoke(@($fixtureExecutable, 1))
$line = $type.GetMethod('OnLine', $instance)
$result = $type.GetField('result', $instance).GetValue($capture)
$captured = $type.GetField('captured', $instance).GetValue($capture)
try {
  $line.Invoke($capture, @('ordinary FAKE_PRIVATE_DATA', $false))
  $line.Invoke($capture, @('ERROR FAKE_PRIVATE_ERROR', $true))
  $line.Invoke($capture, @('AF_STARTUP {"phase":"bad name","elapsed_us":0}', $false))
  Assert-True ($result.stderr_error_marker_lines -eq 1 -and $result.invalid_phase_marker_count -eq 1) 'Capture counters are incorrect.'
  for ($i = 0; $i -lt 3; $i++) {
    $line.Invoke($capture, @('AF_STARTUP {"phase":"first_frame_rasterized","elapsed_us":1}', $false))
  }
  Assert-True ($captured.Count -eq 1 -and $result.phase_counts['first_frame_rasterized'] -eq 3) 'Duplicate milestones substituted for distinct readiness.'
  foreach ($phase in @('workspace_shell_frame', 'page_host_frame')) {
    $line.Invoke($capture, @("AF_STARTUP {`"phase`":`"$phase`",`"elapsed_us`":2}", $false))
  }
  Assert-True ($captured.Count -eq 3) 'Readiness accepted an incomplete application launch.'
  $line.Invoke($capture, @('AF_STARTUP {"phase":"application_launch","elapsed_us":3,"duration_us":2,"succeeded":true}', $false))
  Assert-True ($captured.Count -eq 4) 'Complete distinct milestones not recognized.'
  for ($i = 0; $i -lt 300; $i++) {
    $line.Invoke($capture, @("AF_STARTUP {`"phase`":`"stage.$i`",`"elapsed_us`":4}", $false))
  }
  Assert-True ($result.phases.Count -eq 256 -and $result.discarded_phase_record_count -gt 0 -and
    $result.phase_counts.Count -eq 256 -and $result.untracked_phase_event_count -gt 0) 'Noisy output exceeded capture bounds.'
  Assert-True (($result | ConvertTo-Json -Depth 8) -notmatch 'FAKE_PRIVATE') 'Raw/private log text was retained.'
} finally {
  $type.GetMethod('StopCaptureAndDispose', $instance).Invoke($capture, @())
}
Write-Host "$checks startup-capture checks passed without launching an application."