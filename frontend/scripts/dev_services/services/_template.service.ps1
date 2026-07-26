# Template for a new integration. Copy it to <name>.service.ps1 and edit.
#
# Files that start with an underscore are ignored by the runner, so this one
# never shows up in `dev-services.ps1 list`.
#
# Every key except Name, DisplayName and Up is optional. The lifecycle
# scriptblocks all take the same two arguments:
#
#   $ctx      Name, DisplayName, Config (Defaults merged with the overrides
#             from dev-services.local.json), ScriptRoot, WorkspaceRoot
#   $options  Rebuild, Recreate, Destroy, Force, SkipHealth, Follow, Tail, All
#
# The helpers from lib\common.ps1 (Start-DevContainer, Invoke-DevCompose,
# Invoke-DevDocker, Test-DevHttp, Write-DevStep, ...) are available inside them.

@{
    Name        = 'example'
    DisplayName = 'Example service'
    Summary     = 'One line shown by the list command'

    # $false keeps it out of a bare `dev-services.ps1 up`; start it by name or
    # with -All.
    Enabled     = $false
    # Lower numbers start first.
    Order       = 500
    # Selectable with `dev-services.ps1 up <tag>`.
    Tags        = @('example')
    # Other service names that must be up first.
    DependsOn   = @()

    Defaults    = [ordered]@{
        Image     = 'hello-world:latest'
        Container = 'appflowy-example'
        Port      = 9876
    }

    # One time preparation: pull or build images, create config files.
    Setup       = {
        param($ctx, $options)
        Initialize-DevImage -Reference $ctx.Config.Image -Pull:$options.Rebuild
    }

    # Must be idempotent: `up` is also used to resume an existing container.
    Up          = {
        param($ctx, $options)
        Start-DevContainer `
            -Name $ctx.Config.Container `
            -Image $ctx.Config.Image `
            -Ports @("$($ctx.Config.Port):80") `
            -Recreate:$options.Recreate | Out-Null
    }

    # Polled after Up until it returns $true or the timeout elapses.
    Health      = @{
        TimeoutSec  = 60
        IntervalSec = 3
        Activity    = 'waiting for the example service'
        Probe       = {
            param($ctx)
            Test-DevHttp -Url "http://localhost:$($ctx.Config.Port)/"
        }
    }

    # Stop by default; remove containers and volumes when $options.Destroy.
    Down        = {
        param($ctx, $options)
        Stop-DevContainer -Name $ctx.Config.Container -Remove:$options.Destroy
    }

    # Returns @{ State = '<container state>'; Healthy = $true/$false }.
    Status      = {
        param($ctx, $options)
        @{
            State   = Get-DevContainerState -Name $ctx.Config.Container
            Healthy = Test-DevHttp -Url "http://localhost:$($ctx.Config.Port)/" -TimeoutSec 3
        }
    }

    Logs        = {
        param($ctx, $options)
        Show-DevContainerLogs -Name $ctx.Config.Container -Tail $options.Tail -Follow:$options.Follow
    }

    # Returns a list of warnings; an empty list means everything looks fine.
    Doctor      = {
        param($ctx, $options)
        @()
    }

    # Printed after a successful `up` and by the info command.
    Info        = {
        param($ctx, $options)
        @{
            Endpoints = [ordered]@{
                'Example' = "http://localhost:$($ctx.Config.Port)"
            }
            Notes     = @('What to configure in AppFlowy to use this service.')
        }
    }
}
