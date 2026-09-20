#requires -Version 7.0
<#
.SYNOPSIS
Measures structured startup markers from repeated, normally closed Windows launches.
.DESCRIPTION
Run only after saving work and normally closing every existing AppFlowy instance.
This helper refuses existing AppFlowy processes, including other installations. It
owns only the Process objects it starts; it never terminates a process forcibly.
The calling owner must reopen the updated Release normally after profiling. Every
measured launch is closed, so a final interactive instance is not left with stdout
and stderr redirected to a finished measurement helper.

Requires Windows, PowerShell 7, and an already-built AppFlowy.exe supporting
--profile-startup. Does not build, change environment variables, inspect secrets,
or read/write application data, preferences, profiles, or caches. Normal AppFlowy
execution can itself perform its usual persistence; this is not an isolated profile.
Samples are relaunches, NOT proof of cold startup or a controlled warm-cache state.
The OS cache is never flushed and no aggregate is presented as a cold-start result.

Only AF_STARTUP JSON on stdout is retained, projected onto phase, elapsed_us,
optional duration_us, optional succeeded, and parent-stopwatch arrival_ms. Phase
names must be symbolic identifiers (letters, digits, underscore, dot, hyphen; up
to 96 characters). Extra/duplicate JSON keys and malformed markers are rejected.
No arbitrary stdout/stderr lines, exception messages, or log excerpts are saved or
echoed. Error-marker detection retains line counts only, and is a heuristic.
At most 256 phase records and 256 distinct phase counters are kept PER RUN;
truncation is reported as failure rather than silently claiming complete capture.

Readiness requires all four DISTINCT milestones: first_frame_rasterized,
workspace_shell_frame, page_host_frame, and a completed application_launch with
duration_us and succeeded. dart_entry is also required for the reported launch
boundary. Repeated markers cannot substitute for missing milestones. Arrival
times start immediately before Process.Start and include native/DLL loading and
stdout delivery/scheduling, whereas elapsed_us/duration_us are Dart's own clock.

Startup waits on captured-marker/process-exit events (default 90 seconds). After
one window/Responding check and executable-path verification, cleanup requests
CloseMainWindow (WM_CLOSE), waits at most 60 seconds for exit, and at most five
seconds for redirected-stream EOF. Failure stops subsequent runs. An unconfirmed
exit is explicitly reported with its PID; disposing Process does NOT stop it.

The source-relative build/performance/startup-{Label}.json is updated before any
launch and after each run, including failures. Reusing a label replaces that
report. All other logs are discarded; no raw-log file or JSONL sidecar is written.
Exit code is zero only if all requested runs succeed and their processes exit.
.PARAMETER Executable
AppFlowy.exe to measure; defaults to build/windows/x64/runner/Release/AppFlowy.exe.
Relative overrides are resolved against this script's parent app directory, NOT
the current directory or PATH. No alternate application arguments are accepted.
.PARAMETER Label
Report filename component: 1-64 ASCII letters/digits/underscores/hyphens, starting
with a letter or digit. Defaults to release. Paths and traversal are not accepted.
.PARAMETER Runs
Number of measured relaunches, 1-100; defaults to 3. Stops at the first failure.
.PARAMETER TimeoutSeconds
Marker-wait timeout per launch, 1-3600 seconds; defaults to 90. Graceful shutdown
has its own fixed 60-second bound, separate from this startup budget.
.EXAMPLE
pwsh -NoProfile -File .\tool\profile_windows_startup.ps1 -Label release-after -Runs 3 -TimeoutSeconds 90
#>
[CmdletBinding()]
param(
  [ValidateNotNullOrEmpty()]
  [string]$Executable = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\AppFlowy.exe'),

  [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z')]
  [string]$Label = 'release',

  [ValidateRange(1, 100)]
  [int]$Runs = 3,

  [ValidateRange(1, 3600)]
  [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$reportDirectory = Join-Path $appRoot 'build/performance'
$reportPath = Join-Path $reportDirectory "startup-$Label.json"
$report = [ordered]@{
  schema_version = 1
  label = $Label
  sample_kind = 'relaunch'
  cache_state = 'uncontrolled; no OS cache flushing or application cache changes by this runner'
  timing_note = 'arrival_ms includes Process.Start, native loading and stdout delivery; elapsed_us/duration_us are Dart monotonic timings'
  requested_runs = $Runs
  timeout_seconds = $TimeoutSeconds
  graceful_exit_timeout_seconds = 60
  stream_drain_timeout_seconds = 5
  phase_record_limit_per_run = 256
  phase_counter_limit_per_run = 256
  started_utc = [DateTime]::UtcNow.ToString('o')
  finished_utc = $null
  os_version = [Environment]::OSVersion.Version.ToString()
  os_architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  runner_architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
  powershell_version = $PSVersionTable.PSVersion.ToString()
  executable = $null
  executable_unchanged = $null
    runtime_artifacts = @()
    runtime_unchanged = $null
  runs = [Collections.Generic.List[object]]::new()
  failure_codes = [Collections.Generic.List[string]]::new()
  unconfirmed_exit_pids = [Collections.Generic.List[int]]::new()
  succeeded = $false
  final_reopen = 'calling owner must reopen updated Release normally; this helper closes every measured launch'
}

function Save-StartupReport {
  # Only this schema is serialized, never ErrorRecord/Exception/Process objects.
  $json = $report | ConvertTo-Json -Depth 10
  $temporaryPath = "$reportPath.tmp"
  [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
  [IO.File]::Move($temporaryPath, $reportPath, $true)
}

function Get-ExecutableIdentity([string]$Path) {
  $file = Get-Item -LiteralPath $Path -ErrorAction Stop
  $length = $file.Length
  $modifiedUtc = $file.LastWriteTimeUtc
  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
  $file.Refresh()
  if ($file.Length -ne $length -or $file.LastWriteTimeUtc -ne $modifiedUtc) {
    throw 'executable_changed_while_hashing'
  }
  [ordered]@{
    path = $file.FullName
    sha256 = $hash.ToLowerInvariant()
    last_write_time_utc = $modifiedUtc.ToString('o')
    bytes = $length
  }
}

# All asynchronous handlers are C#: a redirected-output thread has no PowerShell
# runspace. Keep this versioned helper in one type definition for one-shot pwsh use.
$measurementSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;

namespace AppFlowy.StartupProfiling.V1
{
    public sealed class PhaseRecord
    {
        public string phase { get; set; }
        public long elapsed_us { get; set; }
        public long? duration_us { get; set; }
        public bool? succeeded { get; set; }
        public double arrival_ms { get; set; }
    }

    public sealed class Sample
    {
        public int run { get; set; }
        public string sample_kind { get; set; } = "relaunch";
        public int? pid { get; set; }
        public List<int> blocking_pids { get; } = new List<int>();
        public string process_state { get; set; } = "not_started";
        public int? exit_code { get; set; }
        public double? process_exit_arrival_ms { get; set; }
        public bool all_milestones_captured { get; set; }
        public List<string> missing_milestones { get; } = new List<string>();
        public double? process_to_dart_entry_ms { get; set; }
        public double? process_to_first_raster_ms { get; set; }
        public double? process_to_workspace_shell_ms { get; set; }
        public double? process_to_page_host_ms { get; set; }
        public double? process_to_application_launch_ms { get; set; }
        public double? application_launch_duration_ms { get; set; }
        public bool image_path_verified_before_close { get; set; }
        public bool? main_window_present { get; set; }
        public bool? window_responding { get; set; }
        public bool close_requested { get; set; }
        public bool close_accepted { get; set; }
        public double? graceful_close_ms { get; set; }
        public bool output_drained { get; set; }
        public long phase_event_count { get; set; }
        public long discarded_phase_record_count { get; set; }
        public long untracked_phase_event_count { get; set; }
        public long invalid_phase_marker_count { get; set; }
        public long failed_phase_count { get; set; }
        public long stdout_error_marker_lines { get; set; }
        public long stderr_error_marker_lines { get; set; }
        public long callback_error_count { get; set; }
        public Dictionary<string, long> phase_counts { get; } =
            new Dictionary<string, long>(StringComparer.Ordinal);
        public List<PhaseRecord> phases { get; } = new List<PhaseRecord>();
        public List<string> failure_codes { get; } = new List<string>();
        public bool succeeded { get; set; }
    }

    public sealed class MeasurementRunner
    {
        private const int RecordLimit = 256;
        private const int CloseTimeoutMs = 60000;
        private const int DrainTimeoutMs = 5000;
        private const string Prefix = "AF_STARTUP ";
        private static readonly string[] Milestones = {
            "first_frame_rasterized", "workspace_shell_frame",
            "page_host_frame", "application_launch"
        };
        private static readonly Regex PhaseName = new Regex(
            @"\A[A-Za-z][A-Za-z0-9_.-]{0,95}\z", RegexOptions.CultureInvariant);
        // Store ONLY a count of matching lines, never the match or original text.
        private static readonly Regex ErrorMarker = new Regex(
            @"\b(?:ERROR|FATAL|panicked)\b|\bunhandled\s+(?:exception|error)\b",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant,
            TimeSpan.FromMilliseconds(100));

        private readonly object gate = new object();
        private readonly ManualResetEventSlim startupOrExit = new ManualResetEventSlim(false, 0);
        private readonly ManualResetEventSlim streamsEnded = new ManualResetEventSlim(false, 0);
        private readonly HashSet<string> captured = new HashSet<string>(StringComparer.Ordinal);
        private readonly Stopwatch clock = new Stopwatch();
        private readonly Process process = new Process();
        private readonly Sample result;
        private readonly string executable;
        private bool ownsProcess;
        private bool acceptEvents = true;
        private bool stdoutEnded;
        private bool stderrEnded;
        private bool stdoutStarted;
        private bool stderrStarted;

        private MeasurementRunner(string executable, int run)
        {
            this.executable = Path.GetFullPath(executable);
            result = new Sample { run = run };
            // Reserve required counters even if a noisy producer exhausts the cap.
            result.phase_counts.Add("dart_entry", 0);
            foreach (string phase in Milestones) result.phase_counts.Add(phase, 0);
            process.StartInfo = new ProcessStartInfo {
                FileName = this.executable,
                WorkingDirectory = Path.GetDirectoryName(this.executable),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = new UTF8Encoding(false),
                StandardErrorEncoding = new UTF8Encoding(false),
                CreateNoWindow = true
            };
            process.StartInfo.ArgumentList.Add("--profile-startup");
            process.EnableRaisingEvents = true;
            process.OutputDataReceived += OnStdout;
            process.ErrorDataReceived += OnStderr;
            process.Exited += OnExited;
        }

        public static Sample Measure(string executable, int run, int timeoutSeconds)
        {
            return new MeasurementRunner(executable, run).Execute(timeoutSeconds);
        }

        private void Fail(string code)
        {
            if (!result.failure_codes.Contains(code)) result.failure_codes.Add(code);
        }

        private bool RefuseExistingProcesses()
        {
            Process[] existing = Process.GetProcessesByName("AppFlowy");
            try
            {
                foreach (Process other in existing) result.blocking_pids.Add(other.Id);
                if (existing.Length == 0) return false;
                Fail("existing_appflowy_process");
                return true;
            }
            finally
            {
                // Releasing a handle is not a request to close the other process.
                foreach (Process other in existing) other.Dispose();
            }
        }

        private Sample Execute(int timeoutSeconds)
        {
            try
            {
                if (!RefuseExistingProcesses())
                {
                    // No managed work between the launch boundary and Start.
                    clock.Start();
                    ownsProcess = process.Start();
                    if (!ownsProcess) Fail("process_start_failed");
                    else
                    {
                        result.pid = process.Id;
                        process.BeginOutputReadLine();
                        stdoutStarted = true;
                        process.BeginErrorReadLine();
                        stderrStarted = true;
                        if (!startupOrExit.Wait(TimeSpan.FromSeconds(timeoutSeconds)))
                            Fail("startup_timeout");
                        lock (gate)
                        {
                            result.all_milestones_captured = captured.Count == Milestones.Length;
                            foreach (string phase in Milestones)
                                if (!captured.Contains(phase)) result.missing_milestones.Add(phase);
                            if (!result.all_milestones_captured) Fail("missing_startup_milestones");
                            if (!result.process_to_dart_entry_ms.HasValue) Fail("missing_dart_entry");
                        }
                        if (ObserveExit()) Fail("process_exited_before_window_verification");
                    }
                }
            }
            catch (Exception)
            {
                // OS and application exception messages can contain paths/data.
                Fail("measurement_exception");
            }
            finally
            {
                if (ownsProcess)
                {
                    try { CloseOwnedProcess(); }
                    catch (Exception) { Fail("graceful_close_exception"); }
                    try
                    {
                        if (ObserveExit())
                        {
                            result.exit_code = process.ExitCode;
                            if (result.exit_code != 0) Fail("nonzero_process_exit");
                            result.output_drained = streamsEnded.Wait(DrainTimeoutMs);
                            if (!result.output_drained) Fail("stream_drain_timeout");
                        }
                        else Fail("owned_process_not_confirmed_exited");
                    }
                    catch (Exception)
                    {
                        result.process_state = "unknown_at_last_observation";
                        Fail("exit_observation_failed");
                    }
                }
                // A handle/reader cleanup error must not discard an owned PID or
                // bypass the caller's structured failure report.
                try { StopCaptureAndDispose(); }
                catch (Exception) { Fail("capture_disposal_failed"); }
                if (result.invalid_phase_marker_count != 0) Fail("invalid_startup_marker");
                if (result.failed_phase_count != 0) Fail("startup_phase_failed");
                if (result.discarded_phase_record_count != 0) Fail("phase_record_limit_exceeded");
                if (result.untracked_phase_event_count != 0) Fail("phase_counter_limit_exceeded");
                if (result.stdout_error_marker_lines != 0 || result.stderr_error_marker_lines != 0)
                    Fail("error_marker_detected");
                if (result.callback_error_count != 0) Fail("capture_callback_failed");
                result.succeeded = result.failure_codes.Count == 0 &&
                    result.all_milestones_captured && result.process_state == "exited" &&
                    result.image_path_verified_before_close && result.main_window_present == true &&
                    result.window_responding == true && result.close_requested &&
                    result.close_accepted && result.output_drained && result.exit_code == 0;
            }
            return result;
        }

        private bool ObserveExit()
        {
            bool exited = process.HasExited;
            lock (gate)
            {
                result.process_state = exited ? "exited" : "running_at_last_observation";
                if (exited && !result.process_exit_arrival_ms.HasValue)
                    result.process_exit_arrival_ms = clock.Elapsed.TotalMilliseconds;
            }
            return exited;
        }

        private void CloseOwnedProcess()
        {
            if (!ownsProcess) return;
            if (ObserveExit())
            {
                Fail("process_exited_before_normal_close");
                return;
            }
            // Never look a process up by PID to close it: keep the original object
            // and verify its identity/path immediately before a normal WM_CLOSE.
            if (!result.pid.HasValue || process.Id != result.pid.Value)
            {
                Fail("owned_process_identity_unverified");
                return;
            }
            process.Refresh();
            ProcessModule module = process.MainModule;
            string imagePath = module == null ? null : module.FileName;
            if (imagePath == null || !String.Equals(Path.GetFullPath(imagePath), executable,
                StringComparison.OrdinalIgnoreCase))
            {
                Fail("owned_process_image_path_mismatch");
                return;
            }
            result.image_path_verified_before_close = true;
            result.main_window_present = process.MainWindowHandle != IntPtr.Zero;
            if (result.main_window_present != true)
            {
                Fail("main_window_missing");
                return;
            }
            result.window_responding = process.Responding;
            if (result.window_responding != true) Fail("main_window_not_responding");
            Stopwatch closing = Stopwatch.StartNew();
            result.close_requested = true;
            result.close_accepted = process.CloseMainWindow();
            if (!result.close_accepted) Fail("normal_close_refused");
            else if (!process.WaitForExit(CloseTimeoutMs)) Fail("graceful_exit_timeout");
            result.graceful_close_ms = closing.Elapsed.TotalMilliseconds;
        }

        private void OnExited(object sender, EventArgs args)
        {
            double arrival = clock.Elapsed.TotalMilliseconds;
            lock (gate)
            {
                if (!acceptEvents) return;
                if (!result.process_exit_arrival_ms.HasValue) result.process_exit_arrival_ms = arrival;
                startupOrExit.Set();
            }
        }

        private void OnStdout(object sender, DataReceivedEventArgs args) { OnLine(args.Data, false); }
        private void OnStderr(object sender, DataReceivedEventArgs args) { OnLine(args.Data, true); }

        private void OnLine(string line, bool stderr)
        {
            double arrival = clock.Elapsed.TotalMilliseconds;
            lock (gate)
            {
                if (!acceptEvents) return;
                if (line == null)
                {
                    if (stderr) stderrEnded = true; else stdoutEnded = true;
                    if (stdoutEnded && stderrEnded) streamsEnded.Set();
                    return;
                }
                try
                {
                    if (!stderr && line.StartsWith(Prefix, StringComparison.Ordinal))
                    {
                        PhaseRecord record = ParsePhase(line, arrival);
                        if (record == null) result.invalid_phase_marker_count++;
                        else RecordPhase(record);
                    }
                    else if (ErrorMarker.IsMatch(line))
                    {
                        if (stderr) result.stderr_error_marker_lines++;
                        else result.stdout_error_marker_lines++;
                    }
                    // Do not keep or forward line: it may contain user content.
                }
                catch (Exception) { result.callback_error_count++; }
            }
        }

        private static PhaseRecord ParsePhase(string line, double arrival)
        {
            if (line.Length > 2048) return null;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(line.Substring(Prefix.Length),
                    new JsonDocumentOptions { MaxDepth = 2 }))
                {
                    if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
                    PhaseRecord record = new PhaseRecord { arrival_ms = arrival };
                    int seen = 0;
                    foreach (JsonProperty property in document.RootElement.EnumerateObject())
                    {
                        int bit;
                        switch (property.Name)
                        {
                            case "phase":
                                bit = 1;
                                if (property.Value.ValueKind != JsonValueKind.String) return null;
                                record.phase = property.Value.GetString();
                                if (!PhaseName.IsMatch(record.phase)) return null;
                                break;
                            case "elapsed_us":
                                bit = 2;
                                long elapsed;
                                if (property.Value.ValueKind != JsonValueKind.Number ||
                                    !property.Value.TryGetInt64(out elapsed) || elapsed < 0) return null;
                                record.elapsed_us = elapsed;
                                break;
                            case "duration_us":
                                bit = 4;
                                long duration;
                                if (property.Value.ValueKind != JsonValueKind.Number ||
                                    !property.Value.TryGetInt64(out duration) || duration < 0) return null;
                                record.duration_us = duration;
                                break;
                            case "succeeded":
                                bit = 8;
                                if (property.Value.ValueKind != JsonValueKind.True &&
                                    property.Value.ValueKind != JsonValueKind.False) return null;
                                record.succeeded = property.Value.GetBoolean();
                                break;
                            default: return null;
                        }
                        if ((seen & bit) != 0) return null;
                        seen |= bit;
                    }
                    if ((seen & 3) != 3) return null;
                    if (record.phase == "application_launch" && (seen & 12) != 12) return null;
                    return record;
                }
            }
            catch (JsonException) { return null; }
        }

        private void RecordPhase(PhaseRecord record)
        {
            result.phase_event_count++;
            if (record.succeeded == false) result.failed_phase_count++;
            long count;
            if (result.phase_counts.TryGetValue(record.phase, out count))
                result.phase_counts[record.phase] = count + 1;
            else if (result.phase_counts.Count < RecordLimit) result.phase_counts.Add(record.phase, 1);
            else result.untracked_phase_event_count++;
            if (result.phases.Count < RecordLimit) result.phases.Add(record);
            else result.discarded_phase_record_count++;

            // Keep first-arrival summaries even after the record buffer fills.
            switch (record.phase)
            {
                case "dart_entry":
                    if (!result.process_to_dart_entry_ms.HasValue)
                        result.process_to_dart_entry_ms = record.arrival_ms;
                    break;
                case "first_frame_rasterized":
                    if (!result.process_to_first_raster_ms.HasValue)
                        result.process_to_first_raster_ms = record.arrival_ms;
                    captured.Add(record.phase);
                    break;
                case "workspace_shell_frame":
                    if (!result.process_to_workspace_shell_ms.HasValue)
                        result.process_to_workspace_shell_ms = record.arrival_ms;
                    captured.Add(record.phase);
                    break;
                case "page_host_frame":
                    if (!result.process_to_page_host_ms.HasValue)
                        result.process_to_page_host_ms = record.arrival_ms;
                    captured.Add(record.phase);
                    break;
                case "application_launch":
                    if (!result.process_to_application_launch_ms.HasValue)
                    {
                        result.process_to_application_launch_ms = record.arrival_ms;
                        result.application_launch_duration_ms = record.duration_us.Value / 1000.0;
                    }
                    captured.Add(record.phase);
                    break;
            }
            if (captured.Count == Milestones.Length) startupOrExit.Set();
        }

        private void StopCaptureAndDispose()
        {
            // In-flight callbacks must pass this lock before touching event handles.
            // Once frozen, the returned DTO cannot be changed by a background reader.
            lock (gate) { acceptEvents = false; }
            process.OutputDataReceived -= OnStdout;
            process.ErrorDataReceived -= OnStderr;
            process.Exited -= OnExited;
            try { if (stdoutStarted) process.CancelOutputRead(); }
            catch (InvalidOperationException) { }
            try { if (stderrStarted) process.CancelErrorRead(); }
            catch (InvalidOperationException) { }
            // Especially on failure, Dispose releases handles, NOT the application.
            process.Dispose();
            startupOrExit.Dispose();
            streamsEnded.Dispose();
            clock.Stop();
        }
    }
}
'@

$exitCode = 1
$reportWritable = $false
$stage = 'report_initialization_failed'
try {
  [IO.Directory]::CreateDirectory($reportDirectory) | Out-Null
  Save-StartupReport
  $reportWritable = $true

  $stage = 'unsupported_platform'
  if (-not $IsWindows) { throw 'unsupported_platform' }
  $stage = 'invalid_executable'
  $executablePath = [IO.Path]::GetFullPath($Executable, $appRoot)
  if ([IO.Path]::GetFileName($executablePath) -ine 'AppFlowy.exe' -or
      -not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw 'invalid_executable'
  }
  $stage = 'executable_identity_failed'
  $report.executable = Get-ExecutableIdentity $executablePath
    $stage = 'runtime_identity_failed'
    $bundleRoot = Split-Path -Parent $executablePath
    $payload = Join-Path $bundleRoot 'data/app.so'
    if (-not (Test-Path -LiteralPath $payload -PathType Leaf)) {
        $payload = Join-Path $bundleRoot 'data/flutter_assets/kernel_blob.bin'
    }
    # The native launcher can be identical across Dart/Rust rebuilds. Record the
    # actual runtime too, so a timing comparison cannot mistake an unchanged EXE
    # hash for unchanged application code.
    $report.runtime_artifacts = @(
        Get-ExecutableIdentity (Join-Path $bundleRoot 'dart_ffi.dll')
        Get-ExecutableIdentity $payload
    )
  $stage = 'helper_compilation_failed'
  if (-not ('AppFlowy.StartupProfiling.V1.MeasurementRunner' -as [type])) {
    Add-Type -TypeDefinition $measurementSource -ErrorAction Stop
  }
  $stage = 'report_write_failed'
  Save-StartupReport

  for ($run = 1; $run -le $Runs; $run++) {
    $stage = 'measurement_failed'
    $sample = [AppFlowy.StartupProfiling.V1.MeasurementRunner]::Measure(
      $executablePath, $run, $TimeoutSeconds
    )
    $report.runs.Add($sample)
    if ($null -ne $sample.pid -and $sample.process_state -ne 'exited') {
      $report.unconfirmed_exit_pids.Add($sample.pid)
    }
    if (-not $sample.succeeded) { $report.failure_codes.Add('sample_failed') }
    $stage = 'report_write_failed'
    Save-StartupReport
    if (-not $sample.succeeded) { break }
  }

  $stage = 'executable_identity_recheck_failed'
  $after = Get-ExecutableIdentity $executablePath
  $report.executable_unchanged = (
    $after.sha256 -eq $report.executable.sha256 -and
    $after.last_write_time_utc -eq $report.executable.last_write_time_utc -and
    $after.bytes -eq $report.executable.bytes
  )
  if (-not $report.executable_unchanged) { $report.failure_codes.Add('executable_changed') }
    $stage = 'runtime_identity_recheck_failed'
    $report.runtime_unchanged = $true
    foreach ($runtime in $report.runtime_artifacts) {
        $after = Get-ExecutableIdentity $runtime.path
        if ($after.sha256 -ne $runtime.sha256 -or
                $after.last_write_time_utc -ne $runtime.last_write_time_utc -or
                $after.bytes -ne $runtime.bytes) {
            $report.runtime_unchanged = $false
        }
    }
    if (-not $report.runtime_unchanged) { $report.failure_codes.Add('runtime_changed') }
  $report.succeeded = $report.failure_codes.Count -eq 0 -and $report.runs.Count -eq $Runs
  if ($report.succeeded) { $exitCode = 0 }
} catch {
  # Never persist $_, its message, InvocationInfo, or a native error's output.
  $report.failure_codes.Add($stage)
  $report.succeeded = $false
  $exitCode = 1
} finally {
  $report.finished_utc = [DateTime]::UtcNow.ToString('o')
  if ($reportWritable) {
    try { Save-StartupReport }
    catch {
            $report.failure_codes.Add('report_write_failed')
      $report.succeeded = $false
      $exitCode = 1
      Write-Warning 'Final report write failed; any existing report may be incomplete.'
    }
  }
}

if ($report.runs.Count -gt 0) {
  Write-Host 'Relaunch samples: arrival times include native loading and stdout delivery (ms).'
  $report.runs | Select-Object run,
    @{ Name = 'dart_entry'; Expression = { $_.process_to_dart_entry_ms } },
    @{ Name = 'first_raster'; Expression = { $_.process_to_first_raster_ms } },
    @{ Name = 'workspace_shell'; Expression = { $_.process_to_workspace_shell_ms } },
    @{ Name = 'page_host'; Expression = { $_.process_to_page_host_ms } },
    @{ Name = 'launch_duration'; Expression = { $_.application_launch_duration_ms } },
    succeeded | Format-Table -AutoSize
  foreach ($sample in $report.runs) {
    if (-not $sample.succeeded) {
      Write-Warning "Run $($sample.run): $($sample.failure_codes -join ', ')."
      if ($sample.blocking_pids.Count -gt 0) {
        Write-Warning "Existing AppFlowy PIDs were not touched: $($sample.blocking_pids -join ', ')."
      }
    }
  }
}
foreach ($ownedPid in $report.unconfirmed_exit_pids) {
  Write-Warning "Owned AppFlowy PID $ownedPid was not confirmed exited. Inspect it before rerunning; no forced termination was attempted."
}
if ($reportWritable) { Write-Host "Structured startup report: $reportPath" }
else { Write-Warning 'Could not create the startup report; no measurement was started.' }
if ($exitCode -eq 0) {
  Write-Host 'All measured processes exited. Calling owner: reopen the updated Release normally.'
} else {
  Write-Warning "Profiling failed; subsequent launches were stopped. Codes: $($report.failure_codes -join ', ')."
}
exit $exitCode