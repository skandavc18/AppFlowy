# Shared helpers for the AppFlowy dev services runner.
#
# This file is dot sourced by dev-services.ps1, so every helper below is also
# available inside a service manifest (services/*.service.ps1). Keep it free of
# PowerShell 7 only syntax: the script has to run on Windows PowerShell 5.1 too.

# ---------------------------------------------------------------------------
# Console output
# ---------------------------------------------------------------------------

function Write-DevHeading {
    param([Parameter(Mandatory)][string]$Text)
    $line = '-' * [Math]::Max(4, 74 - $Text.Length)
    Write-Host ''
    Write-Host "== $Text $line" -ForegroundColor White
}

function Write-DevStep {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "  > $Text" -ForegroundColor Cyan
}

function Write-DevInfo {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    Write-Host "    $Text" -ForegroundColor DarkGray
}

function Write-DevOk {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "  + $Text" -ForegroundColor Green
}

function Write-DevWarn {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "  ! $Text" -ForegroundColor Yellow
}

function Write-DevFail {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "  x $Text" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

# ConvertFrom-Json -AsHashtable is PowerShell 6+, so convert by hand.
function ConvertTo-DevHashtable {
    param($InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $InputObject.Keys) { $copy[$key] = ConvertTo-DevHashtable $InputObject[$key] }
        return $copy
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        return @($InputObject | ForEach-Object { ConvertTo-DevHashtable $_ })
    }
    if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Name.Count -gt 0) {
        $copy = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $copy[$property.Name] = ConvertTo-DevHashtable $property.Value
        }
        return $copy
    }
    return $InputObject
}

function Read-DevJsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    return ConvertTo-DevHashtable (ConvertFrom-Json $raw)
}

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

function Test-DevDockerAvailable {
    $command = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $command) { return $false }
    docker info --format '{{.ServerVersion}}' 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

<#
.SYNOPSIS
Runs the docker CLI.
.DESCRIPTION
Without -Capture the output is streamed straight to the console, which is what
long running commands such as build, pull and logs need. With -Capture the
output is returned as an array of lines instead.
#>
function Invoke-DevDocker {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$WorkingDirectory,
        [switch]$Capture,
        [switch]$AllowFailure
    )

    $pushed = $false
    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
        $pushed = $true
    }
    try {
        if ($Capture) {
            $output = & docker @Arguments 2>&1
        }
        else {
            & docker @Arguments
            $output = @()
        }
        $exitCode = $LASTEXITCODE
        $script:DevDockerExitCode = $exitCode
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            $detail = if ($output) { ": " + (($output | ForEach-Object { "$_" }) -join [Environment]::NewLine) } else { '' }
            throw "docker $($Arguments -join ' ') exited with code $exitCode$detail"
        }
        if ($Capture) { return , @($output | ForEach-Object { "$_" }) }
    }
    finally {
        if ($pushed) { Pop-Location }
    }
}

function Invoke-DevCompose {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string[]]$ComposeFiles,
        [string]$EnvFile,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Capture,
        [switch]$AllowFailure
    )

    $composeArgs = @('compose', '-p', $Project)
    foreach ($file in $ComposeFiles) { $composeArgs += @('-f', $file) }
    if ($EnvFile) { $composeArgs += @('--env-file', $EnvFile) }
    $composeArgs += $Arguments

    return Invoke-DevDocker -Arguments $composeArgs -WorkingDirectory $ProjectPath -Capture:$Capture -AllowFailure:$AllowFailure
}

# 'running', 'exited', 'created', 'paused' ... or 'missing' when there is no
# container with that name at all.
function Get-DevContainerState {
    param([Parameter(Mandatory)][string]$Name)

    $filter = "name=^/$([regex]::Escape($Name))$"
    $lines = Invoke-DevDocker -Arguments @('ps', '-a', '--filter', $filter, '--format', '{{.State}}') -Capture -AllowFailure
    $state = @($lines | Where-Object { $_ -and $_.Trim() }) | Select-Object -First 1
    if (-not $state) { return 'missing' }
    return $state.Trim().ToLowerInvariant()
}

function Test-DevImageExists {
    param([Parameter(Mandatory)][string]$Reference)

    Invoke-DevDocker -Arguments @('image', 'inspect', $Reference) -Capture -AllowFailure | Out-Null
    return $script:DevDockerExitCode -eq 0
}

function Test-DevNetworkExists {
    param([Parameter(Mandatory)][string]$Name)

    $lines = Invoke-DevDocker -Arguments @('network', 'ls', '--filter', "name=^$([regex]::Escape($Name))$", '--format', '{{.Name}}') -Capture -AllowFailure
    return @($lines | Where-Object { $_ -and $_.Trim() -eq $Name }).Count -gt 0
}

function Initialize-DevImage {
    param(
        [Parameter(Mandatory)][string]$Reference,
        [switch]$Pull
    )

    if ((Test-DevImageExists -Reference $Reference) -and -not $Pull) {
        Write-DevInfo "image $Reference is present"
        return
    }
    Write-DevStep "pulling $Reference (this can take a while the first time)"
    Invoke-DevDocker -Arguments @('pull', $Reference)
}

<#
.SYNOPSIS
Creates, starts or reuses a container, whichever is needed.
#>
function Start-DevContainer {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Image,
        [string[]]$Ports = @(),
        [System.Collections.IDictionary]$Environment,
        [string[]]$Volumes = @(),
        [string]$Network,
        [string]$RestartPolicy = 'unless-stopped',
        [string[]]$ExtraArgs = @(),
        [string[]]$Command = @(),
        [switch]$Recreate
    )

    $state = Get-DevContainerState -Name $Name
    if ($state -ne 'missing' -and $Recreate) {
        Write-DevStep "recreating $Name"
        Invoke-DevDocker -Arguments @('rm', '-f', $Name) -Capture -AllowFailure | Out-Null
        $state = 'missing'
    }

    switch ($state) {
        'running' {
            Write-DevInfo "$Name is already running"
            return 'running'
        }
        'missing' {
            $runArgs = @('run', '-d', '--name', $Name)
            if ($RestartPolicy) { $runArgs += @('--restart', $RestartPolicy) }
            if ($Network) { $runArgs += @('--network', $Network) }
            foreach ($port in $Ports) { $runArgs += @('-p', $port) }
            foreach ($volume in $Volumes) { $runArgs += @('-v', $volume) }
            if ($Environment) {
                foreach ($key in $Environment.Keys) { $runArgs += @('-e', "$key=$($Environment[$key])") }
            }
            $runArgs += $ExtraArgs
            $runArgs += $Image
            $runArgs += $Command

            Write-DevStep "starting $Name from $Image"
            Invoke-DevDocker -Arguments $runArgs -Capture | Out-Null
            return 'started'
        }
        default {
            Write-DevStep "resuming $Name (was $state)"
            Invoke-DevDocker -Arguments @('start', $Name) -Capture | Out-Null
            return 'started'
        }
    }
}

function Stop-DevContainer {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Remove
    )

    $state = Get-DevContainerState -Name $Name
    if ($state -eq 'missing') {
        Write-DevInfo "$Name does not exist"
        return
    }
    if ($state -eq 'running') {
        Write-DevStep "stopping $Name"
        Invoke-DevDocker -Arguments @('stop', $Name) -Capture -AllowFailure | Out-Null
    }
    if ($Remove) {
        Write-DevStep "removing $Name"
        Invoke-DevDocker -Arguments @('rm', '-f', $Name) -Capture -AllowFailure | Out-Null
    }
}

function Remove-DevVolume {
    param([Parameter(Mandatory)][string[]]$Name)

    foreach ($volume in $Name) {
        if (-not $volume) { continue }
        Write-DevStep "removing volume $volume"
        Invoke-DevDocker -Arguments @('volume', 'rm', '-f', $volume) -Capture -AllowFailure | Out-Null
    }
}

function Show-DevContainerLogs {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$Tail = 120,
        [switch]$Follow
    )

    if ((Get-DevContainerState -Name $Name) -eq 'missing') {
        Write-DevWarn "$Name does not exist yet"
        return
    }
    $logArgs = @('logs', '--tail', "$Tail")
    if ($Follow) { $logArgs += '-f' }
    $logArgs += $Name
    Invoke-DevDocker -Arguments $logArgs -AllowFailure
}

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

function Test-DevHttp {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$BodyContains,
        [int]$TimeoutSec = 5,
        [int[]]$StatusCodes = @(200)
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch {
        return $false
    }
    if ($StatusCodes -and ($StatusCodes -notcontains [int]$response.StatusCode)) { return $false }
    if ($BodyContains) {
        return ("$($response.Content)").ToLowerInvariant().Contains($BodyContains.ToLowerInvariant())
    }
    return $true
}

function Test-DevTcpPort {
    param(
        [Parameter(Mandatory)][int]$Port,
        [string]$HostName = '127.0.0.1',
        [int]$TimeoutMs = 700
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

<#
.SYNOPSIS
Polls a probe scriptblock until it returns true or the timeout elapses.
#>
function Wait-DevCondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Probe,
        $ArgumentList,
        [int]$TimeoutSec = 120,
        [int]$IntervalSec = 3,
        [string]$Activity = 'waiting'
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    Write-Host "    $Activity" -ForegroundColor DarkGray -NoNewline
    while ($true) {
        $ok = $false
        try { $ok = [bool](& $Probe $ArgumentList) } catch { $ok = $false }
        if ($ok) {
            Write-Host ' ok' -ForegroundColor Green
            return $true
        }
        if ((Get-Date) -ge $deadline) {
            Write-Host ' timed out' -ForegroundColor Red
            return $false
        }
        Write-Host '.' -ForegroundColor DarkGray -NoNewline
        Start-Sleep -Seconds $IntervalSec
    }
}
