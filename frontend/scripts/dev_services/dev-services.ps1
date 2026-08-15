<#
.SYNOPSIS
    Starts, stops and inspects the local services AppFlowy integrates with.

.DESCRIPTION
    Every integration is described by one manifest in .\services\*.service.ps1.
    Dropping a new manifest in that folder is all it takes to add a service, so
    this runner never has to know what the service actually is.

.EXAMPLE
    .\dev-services.ps1 up
    Starts every service that is enabled by default and waits until it answers.

.EXAMPLE
    .\dev-services.ps1 up appflowy-cloud
    Starts only the AppFlowy Cloud stack (name, tag or wildcard).

.EXAMPLE
    .\dev-services.ps1 status
    Prints the container state and health of every service.

.EXAMPLE
    .\dev-services.ps1 down -Destroy -Force
    Removes the containers and their volumes instead of just stopping them.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'setup', 'up', 'down', 'restart', 'logs', 'doctor', 'info', 'help')]
    [string]$Command = 'status',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Service,

    # Include services that are not part of the default set.
    [switch]$All,
    # Pull or rebuild images before starting.
    [switch]$Rebuild,
    # Replace existing containers instead of resuming them.
    [switch]$Recreate,
    # down: remove containers and volumes instead of stopping them.
    [switch]$Destroy,
    # Skip the confirmation prompt of a destructive command.
    [switch]$Force,
    # Do not wait for the health probe after starting.
    [switch]$SkipHealth,
    # logs: keep streaming.
    [switch]$Follow,
    [int]$Tail = 120
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptRoot 'lib\common.ps1')

$WorkspaceRoot = (Resolve-Path (Join-Path $ScriptRoot '..\..\..')).Path
$ServicesPath = Join-Path $ScriptRoot 'services'
$OverridesPath = Join-Path $ScriptRoot 'dev-services.local.json'

# ---------------------------------------------------------------------------
# Manifest loading
# ---------------------------------------------------------------------------

function Get-DevServiceDefinitions {
    $overrides = Read-DevJsonFile -Path $OverridesPath
    $definitions = @()

    foreach ($file in Get-ChildItem -LiteralPath $ServicesPath -Filter '*.service.ps1' -File | Sort-Object Name) {
        if ($file.Name.StartsWith('_')) { continue }

        $manifest = & $file.FullName
        if ($manifest -isnot [System.Collections.IDictionary]) {
            Write-DevWarn "$($file.Name) did not return a manifest hashtable, skipped"
            continue
        }
        foreach ($required in @('Name', 'DisplayName')) {
            if (-not $manifest[$required]) { throw "$($file.Name) is missing the required '$required' key" }
        }

        $config = [ordered]@{}
        if ($manifest['Defaults']) {
            foreach ($key in $manifest['Defaults'].Keys) { $config[$key] = $manifest['Defaults'][$key] }
        }
        $serviceOverrides = $overrides[$manifest['Name']]
        if ($serviceOverrides -is [System.Collections.IDictionary]) {
            foreach ($key in $serviceOverrides.Keys) { $config[$key] = $serviceOverrides[$key] }
        }

        $manifest['Config'] = $config
        $manifest['SourceFile'] = $file.FullName
        if (-not $manifest.Contains('Enabled')) { $manifest['Enabled'] = $true }
        if (-not $manifest.Contains('Order')) { $manifest['Order'] = 100 }
        if (-not $manifest.Contains('Tags')) { $manifest['Tags'] = @() }
        if (-not $manifest.Contains('DependsOn')) { $manifest['DependsOn'] = @() }
        $definitions += , $manifest
    }

    if ($definitions.Count -eq 0) { throw "No service manifests found in $ServicesPath" }
    return $definitions
}

function New-DevContext {
    param([Parameter(Mandatory)]$Definition)

    return [pscustomobject]@{
        Name          = $Definition['Name']
        DisplayName   = $Definition['DisplayName']
        Config        = $Definition['Config']
        ScriptRoot    = $ScriptRoot
        WorkspaceRoot = $WorkspaceRoot
    }
}

function Invoke-DevMember {
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$Member,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Options
    )

    $block = $Definition[$Member]
    if (-not $block) { return $null }
    if ($block -isnot [scriptblock]) { throw "$($Definition['Name']).$Member must be a scriptblock" }
    return & $block $Context $Options
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

function Select-DevServices {
    param(
        [Parameter(Mandatory)]$Definitions,
        [string[]]$Patterns,
        [switch]$IncludeDisabled
    )

    if (-not $Patterns -or $Patterns.Count -eq 0) {
        $selected = @($Definitions | Where-Object { $IncludeDisabled -or $_['Enabled'] })
        if ($selected.Count -eq 0) { throw 'No service is enabled by default. Pass a name or use -All.' }
        return $selected
    }

    $selected = @()
    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $matched = @($Definitions | Where-Object {
                $_['Name'] -like $pattern -or
                $_['DisplayName'] -like $pattern -or
                (@($_['Tags']) -contains $pattern)
            })
        if ($matched.Count -eq 0) {
            throw "No service matches '$pattern'. Known services: $((($Definitions | ForEach-Object { $_['Name'] }) -join ', '))"
        }
        foreach ($match in $matched) {
            if ($selected -notcontains $match) { $selected += , $match }
        }
    }
    return $selected
}

function Get-DevStartOrder {
    param(
        [Parameter(Mandatory)]$Definitions,
        [Parameter(Mandatory)]$Selected
    )

    $byName = @{}
    foreach ($definition in $Definitions) { $byName[$definition['Name']] = $definition }

    # Pull in anything the selection depends on.
    $pending = @($Selected)
    $queue = @($Selected)
    while ($queue.Count -gt 0) {
        $current = $queue[0]
        $queue = @($queue | Select-Object -Skip 1)
        foreach ($dependency in @($current['DependsOn'])) {
            if (-not $dependency) { continue }
            $definition = $byName[$dependency]
            if (-not $definition) { throw "$($current['Name']) depends on unknown service '$dependency'" }
            if ($pending -notcontains $definition) {
                $pending += , $definition
                $queue += , $definition
            }
        }
    }

    $pending = @($pending | Sort-Object @{ Expression = { [int]$_['Order'] } }, @{ Expression = { $_['Name'] } })
    $ordered = @()
    while ($pending.Count -gt 0) {
        $pendingNames = @($pending | ForEach-Object { $_['Name'] })
        $ready = @($pending | Where-Object {
                $blocked = $false
                foreach ($dependency in @($_['DependsOn'])) {
                    if ($dependency -and ($pendingNames -contains $dependency)) { $blocked = $true }
                }
                -not $blocked
            })
        if ($ready.Count -eq 0) {
            Write-DevWarn 'circular DependsOn detected, falling back to the declared order'
            $ordered += $pending
            break
        }
        $next = $ready[0]
        $ordered += , $next
        $pending = @($pending | Where-Object { $_ -ne $next })
    }
    return $ordered
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Get-DevServiceStatus {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)]$Options)

    $context = New-DevContext -Definition $Definition
    $state = 'unknown'
    $healthy = $null
    try {
        $result = Invoke-DevMember -Definition $Definition -Member 'Status' -Context $context -Options $Options
        if ($result -is [System.Collections.IDictionary]) {
            if ($result['State']) { $state = $result['State'] }
            if ($result.Contains('Healthy')) { $healthy = $result['Healthy'] }
        }
    }
    catch {
        $state = "error: $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        Service = $Definition['Name']
        Name    = $Definition['DisplayName']
        State   = $state
        Health  = if ($null -eq $healthy) { '-' } elseif ($healthy) { 'ok' } else { 'down' }
    }
}

function Show-DevServiceInfo {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)]$Options)

    $context = New-DevContext -Definition $Definition
    $info = Invoke-DevMember -Definition $Definition -Member 'Info' -Context $context -Options $Options
    if ($info -isnot [System.Collections.IDictionary]) { return }

    if ($info['Endpoints'] -is [System.Collections.IDictionary]) {
        foreach ($key in $info['Endpoints'].Keys) {
            Write-Host ("    {0,-16} {1}" -f $key, $info['Endpoints'][$key]) -ForegroundColor Gray
        }
    }
    foreach ($note in @($info['Notes'])) {
        if ($note) { Write-DevInfo $note }
    }
}

function Invoke-DevUp {
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)]$Options)

    $failed = @()
    foreach ($definition in $Services) {
        Write-DevHeading $definition['DisplayName']
        $context = New-DevContext -Definition $definition
        try {
            # Nothing to do for a service that is already running and answering.
            # -Recreate, -Rebuild and -Force say "do the work anyway".
            if (-not ($Options.Recreate -or $Options.Rebuild -or $Options.Force)) {
                $current = Get-DevServiceStatus -Definition $definition -Options $Options
                if ($current.State -eq 'running' -and $current.Health -ne 'down') {
                    Write-DevOk "$($definition['Name']) is already running, nothing to do"
                    Show-DevServiceInfo -Definition $definition -Options $Options
                    continue
                }
            }

            Invoke-DevMember -Definition $definition -Member 'Setup' -Context $context -Options $Options | Out-Host
            Invoke-DevMember -Definition $definition -Member 'Up' -Context $context -Options $Options | Out-Host

            $health = $definition['Health']
            if ($health -and -not $Options.SkipHealth) {
                $probe = $health['Probe']
                if ($probe -isnot [scriptblock]) { throw "$($definition['Name']).Health.Probe must be a scriptblock" }
                $timeout = if ($health['TimeoutSec']) { [int]$health['TimeoutSec'] } else { 120 }
                $interval = if ($health['IntervalSec']) { [int]$health['IntervalSec'] } else { 3 }
                $activity = if ($health['Activity']) { $health['Activity'] } else { "waiting for $($definition['Name'])" }
                $ready = Wait-DevCondition -Probe $probe -ArgumentList $context -TimeoutSec $timeout -IntervalSec $interval -Activity $activity
                if (-not $ready) { throw 'the service did not report healthy in time' }
            }
            Write-DevOk "$($definition['Name']) is up"
            Show-DevServiceInfo -Definition $definition -Options $Options
        }
        catch {
            Write-DevFail $_.Exception.Message
            $failed += $definition['Name']
        }
    }

    Write-DevHeading 'Summary'
    $Services | ForEach-Object { Get-DevServiceStatus -Definition $_ -Options $Options } | Format-Table -AutoSize | Out-Host
    if ($failed.Count -gt 0) {
        Write-DevFail "failed: $($failed -join ', ')"
        exit 1
    }
}

function Invoke-DevDown {
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)]$Options)

    if ($Options.Destroy -and -not $Options.Force) {
        $names = ($Services | ForEach-Object { $_['Name'] }) -join ', '
        Write-DevWarn "-Destroy removes the containers AND their volumes for: $names"
        Write-DevWarn 'local workspaces, documents and uploads stored in those services are lost'
        $answer = Read-Host '    Type "destroy" to continue'
        if ($answer -ne 'destroy') {
            Write-DevInfo 'cancelled'
            return
        }
    }

    $reversed = @($Services)
    [array]::Reverse($reversed)
    foreach ($definition in $reversed) {
        Write-DevHeading $definition['DisplayName']
        $context = New-DevContext -Definition $definition
        try {
            Invoke-DevMember -Definition $definition -Member 'Down' -Context $context -Options $Options | Out-Host
            Write-DevOk "$($definition['Name']) is down"
        }
        catch {
            Write-DevFail $_.Exception.Message
        }
    }
}

function Invoke-DevSetup {
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)]$Options)

    foreach ($definition in $Services) {
        Write-DevHeading $definition['DisplayName']
        $context = New-DevContext -Definition $definition
        try {
            Invoke-DevMember -Definition $definition -Member 'Setup' -Context $context -Options $Options | Out-Host
            Write-DevOk "$($definition['Name']) is ready to start"
        }
        catch {
            Write-DevFail $_.Exception.Message
        }
    }
}

function Invoke-DevLogs {
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)]$Options)

    if ($Options.Follow -and $Services.Count -gt 1) {
        Write-DevWarn "-Follow streams a single service, using $($Services[0]['Name'])"
        $Services = @($Services[0])
    }
    foreach ($definition in $Services) {
        Write-DevHeading $definition['DisplayName']
        $context = New-DevContext -Definition $definition
        if (-not $definition['Logs']) {
            Write-DevInfo 'this service does not expose logs'
            continue
        }
        Invoke-DevMember -Definition $definition -Member 'Logs' -Context $context -Options $Options | Out-Host
    }
}

function Invoke-DevDoctor {
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)]$Options)

    Write-DevHeading 'Environment'
    if (Test-DevDockerAvailable) {
        Write-DevOk 'docker is running'
    }
    else {
        Write-DevFail 'docker is not available; start Docker Desktop first'
        return
    }
    Write-DevInfo "overrides: $(if (Test-Path -LiteralPath $OverridesPath) { $OverridesPath } else { 'none (dev-services.local.json)' })"

    foreach ($definition in $Services) {
        Write-DevHeading $definition['DisplayName']
        $context = New-DevContext -Definition $definition
        $messages = @()
        try {
            $messages = @(Invoke-DevMember -Definition $definition -Member 'Doctor' -Context $context -Options $Options)
        }
        catch {
            $messages = @("check failed: $($_.Exception.Message)")
        }
        $messages = @($messages | Where-Object { $_ })
        if ($messages.Count -eq 0) {
            Write-DevOk 'no problems found'
        }
        else {
            foreach ($message in $messages) { Write-DevWarn $message }
        }
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

$options = [pscustomobject]@{
    Rebuild    = [bool]$Rebuild
    Recreate   = [bool]$Recreate
    Destroy    = [bool]$Destroy
    Force      = [bool]$Force
    SkipHealth = [bool]$SkipHealth
    Follow     = [bool]$Follow
    Tail       = $Tail
    All        = [bool]$All
}

if ($Command -eq 'help') {
    Get-Help -Detailed (Join-Path $ScriptRoot 'dev-services.ps1') | Out-Host
    return
}

$definitions = Get-DevServiceDefinitions

if ($Command -eq 'list') {
    foreach ($definition in ($definitions | Sort-Object @{ Expression = { [int]$_['Order'] } }, @{ Expression = { $_['Name'] } })) {
        $flag = if ($definition['Enabled']) { 'default' } else { 'opt in ' }
        Write-Host ''
        Write-Host ("  {0,-16} [{1}] {2}" -f $definition['Name'], $flag, $definition['DisplayName']) -ForegroundColor White
        if ($definition['Summary']) { Write-DevInfo $definition['Summary'] }
        if (@($definition['Tags']).Count -gt 0) { Write-DevInfo "tags: $((@($definition['Tags']) -join ', '))" }
    }
    Write-Host ''
    return
}

if ($Command -ne 'doctor' -and -not (Test-DevDockerAvailable)) {
    Write-DevFail 'docker is not available; start Docker Desktop and try again'
    exit 1
}

try {
    $selected = Select-DevServices -Definitions $definitions -Patterns $Service -IncludeDisabled:$All
    $ordered = Get-DevStartOrder -Definitions $definitions -Selected $selected
}
catch {
    Write-DevFail $_.Exception.Message
    exit 1
}

switch ($Command) {
    'status' {
        $ordered | ForEach-Object { Get-DevServiceStatus -Definition $_ -Options $options } | Format-Table -AutoSize | Out-Host
    }
    'info' {
        foreach ($definition in $ordered) {
            Write-DevHeading $definition['DisplayName']
            Show-DevServiceInfo -Definition $definition -Options $options
        }
    }
    'setup' { Invoke-DevSetup -Services $ordered -Options $options }
    'up' { Invoke-DevUp -Services $ordered -Options $options }
    'down' { Invoke-DevDown -Services $ordered -Options $options }
    'restart' {
        Invoke-DevDown -Services $ordered -Options $options
        Invoke-DevUp -Services $ordered -Options $options
    }
    'logs' { Invoke-DevLogs -Services $ordered -Options $options }
    'doctor' { Invoke-DevDoctor -Services $ordered -Options $options }
}
