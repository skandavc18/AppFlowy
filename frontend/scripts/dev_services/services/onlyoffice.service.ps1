# ONLYOFFICE Docs (DocumentServer) - Word, Excel and PowerPoint editing.
#
# Cloud users edit through AppFlowy Cloud. Local users save through the
# short-lived bridge in lib/plugins/document/presentation/editor_plugins/file/office/.

@{
    Name        = 'onlyoffice'
    DisplayName = 'ONLYOFFICE Docs'
    Summary     = 'Word / Excel / PowerPoint editing for office attachments'
    Enabled     = $true
    Order       = 10
    Tags        = @('office', 'documents', 'word', 'excel', 'powerpoint')

    # Every value here can be overridden per machine in dev-services.local.json.
    Defaults    = [ordered]@{
        Image             = 'onlyoffice/documentserver:latest'
        Container         = 'appflowy-onlyoffice'
        Port              = 8080
        JwtEnabled        = $true
        JwtSecret         = 'appflowy-office-dev-secret'
        # A container cannot resolve the host's localhost, so this is the host
        # name ONLYOFFICE uses to call the AppFlowy bridge back.
        BridgeHost        = 'host.docker.internal'
        RestartPolicy     = 'unless-stopped'
        DataVolume        = 'appflowy_onlyoffice_data'
        LogVolume         = 'appflowy_onlyoffice_log'
        LibVolume         = 'appflowy_onlyoffice_lib'
        DatabaseVolume    = 'appflowy_onlyoffice_db'
        StartupTimeoutSec = 300
    }

    Setup       = {
        param($ctx, $options)
        Initialize-DevImage -Reference $ctx.Config.Image -Pull:$options.Rebuild
    }

    Up          = {
        param($ctx, $options)
        $config = $ctx.Config
        $environment = [ordered]@{
            JWT_ENABLED = "$([bool]$config.JwtEnabled)".ToLowerInvariant()
            JWT_HEADER  = 'Authorization'
            JWT_SECRET  = $config.JwtSecret
        }
        Start-DevContainer `
            -Name $config.Container `
            -Image $config.Image `
            -Ports @("$($config.Port):80") `
            -Environment $environment `
            -Volumes @(
                "$($config.DataVolume):/var/www/onlyoffice/Data",
                "$($config.LogVolume):/var/log/onlyoffice",
                "$($config.LibVolume):/var/lib/onlyoffice",
                "$($config.DatabaseVolume):/var/lib/postgresql"
            ) `
            -RestartPolicy $config.RestartPolicy `
            -Recreate:$options.Recreate | Out-Null
    }

    Health      = @{
        TimeoutSec  = 300
        IntervalSec = 5
        Activity    = 'waiting for the document server'
        Probe       = {
            param($ctx)
            Test-DevHttp -Url "http://localhost:$($ctx.Config.Port)/healthcheck" -BodyContains 'true'
        }
    }

    Down        = {
        param($ctx, $options)
        Stop-DevContainer -Name $ctx.Config.Container -Remove:$options.Destroy
        if ($options.Destroy) {
            Remove-DevVolume -Name @(
                $ctx.Config.DataVolume,
                $ctx.Config.LogVolume,
                $ctx.Config.LibVolume,
                $ctx.Config.DatabaseVolume
            )
        }
    }

    Status      = {
        param($ctx, $options)
        @{
            State   = Get-DevContainerState -Name $ctx.Config.Container
            Healthy = Test-DevHttp -Url "http://localhost:$($ctx.Config.Port)/healthcheck" -BodyContains 'true' -TimeoutSec 3
        }
    }

    Logs        = {
        param($ctx, $options)
        Show-DevContainerLogs -Name $ctx.Config.Container -Tail $options.Tail -Follow:$options.Follow
    }

    Doctor      = {
        param($ctx, $options)
        $messages = @()
        $state = Get-DevContainerState -Name $ctx.Config.Container
        if ($state -eq 'missing' -and (Test-DevTcpPort -Port $ctx.Config.Port)) {
            $messages += "port $($ctx.Config.Port) is already taken by something else; set onlyoffice.Port in dev-services.local.json"
        }
        if (-not $ctx.Config.JwtEnabled) {
            $messages += 'JWT is disabled, so anyone who can reach the server can open documents'
        }
        return $messages
    }

    Info        = {
        param($ctx, $options)
        $url = "http://localhost:$($ctx.Config.Port)"
        @{
            Endpoints = [ordered]@{
                'Document server' = $url
                'Health check'    = "$url/healthcheck"
                'Welcome page'    = "$url/welcome/"
            }
            Notes     = @(
                'When signed in to AppFlowy Cloud, office editing connects automatically.',
                'In local-only mode, open a .docx / .xlsx / .pptx file and use:',
                "  Server URL   $url",
                "  JWT secret   $(if ($ctx.Config.JwtEnabled) { $ctx.Config.JwtSecret } else { '(leave empty)' })",
                "  Bridge host  $($ctx.Config.BridgeHost)",
                'The bridge serves the file from AppFlowy itself, so allow the app through the',
                'Windows firewall if the editor loads but the document never appears.'
            )
        }
    }
}
