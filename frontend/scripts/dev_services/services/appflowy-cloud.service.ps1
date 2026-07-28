# AppFlowy Cloud - the self hosted backend (gotrue, postgres, redis, minio and
# the appflowy_cloud API server).
#
# The infrastructure comes from the AppFlowy-Cloud checkout's docker compose
# file; the API server itself runs as a plain container built from that same
# checkout, so a locally patched server can be tested without touching compose.

@{
    Name        = 'appflowy-cloud'
    DisplayName = 'AppFlowy Cloud'
    Summary     = 'Self hosted sync, auth and storage backend'
    Enabled     = $true
    Order       = 20
    Tags        = @('cloud', 'backend', 'sync', 'auth')
    DependsOn   = @('onlyoffice')

    Defaults    = [ordered]@{
        RepoPath          = 'C:\AppFlowy-Cloud'
        ComposeFile       = 'docker-compose-dev.yml'
        EnvFile           = 'deploy.env'
        ComposeProject    = 'appflowy-cloud'
        InfraServices     = @('postgres', 'redis', 'minio', 'gotrue')
        Network           = 'appflowy-cloud_default'

        ServerImage       = 'appflowy-cloud-local:workspace-cover'
        ServerContainer   = 'appflowy-cloud-local'
        ServerPort        = 8000
        # Building the Rust server from source takes a long time; turn this off
        # to be told the build command instead of running it automatically.
        AutoBuildImage    = $true
        RestartPolicy     = 'unless-stopped'

        GotruePort        = 9999
        MinioPort         = 9000
        MinioConsolePort  = 9001
        PostgresPort      = 5432

        GotrueJwtSecret   = 'hello456'
        DatabaseUrl       = 'postgresql://postgres:password@postgres:5432/postgres'
        RedisUri          = 'redis://redis:6379'
        MinioUrl          = 'http://minio:9000'
        S3AccessKey       = 'minioadmin'
        S3SecretKey       = 'minioadmin'
        S3Bucket          = 'appflowy'
        WebUrl            = 'http://localhost:3000'
        RustLog           = 'info'
        DocumentServerContainer        = 'appflowy-onlyoffice'
        DocumentServerPublicUrl        = 'http://localhost:8080'
        DocumentServerInternalUrl      = 'http://appflowy-onlyoffice'
        DocumentServerJwtSecret        = 'appflowy-office-dev-secret'
        DocumentServerMaxFileSizeBytes = 104857600

        AdminEmail        = 'admin@example.com'
        AdminPassword     = 'password'
        StartupTimeoutSec = 180
    }

    Setup       = {
        param($ctx, $options)
        $config = $ctx.Config
        if (-not (Test-Path -LiteralPath $config.RepoPath)) {
            throw "AppFlowy-Cloud checkout not found at $($config.RepoPath). Clone it or set appflowy-cloud.RepoPath in dev-services.local.json."
        }
        $composePath = Join-Path $config.RepoPath $config.ComposeFile
        if (-not (Test-Path -LiteralPath $composePath)) {
            throw "Compose file not found: $composePath"
        }
        $envPath = Join-Path $config.RepoPath $config.EnvFile
        if (-not (Test-Path -LiteralPath $envPath)) {
            throw "Env file not found: $envPath"
        }

        $hasImage = Test-DevImageExists -Reference $config.ServerImage
        if ($hasImage -and -not $options.Rebuild) {
            Write-DevInfo "image $($config.ServerImage) is present"
            return
        }
        if (-not $config.AutoBuildImage -and -not $options.Rebuild) {
            throw "Image $($config.ServerImage) is missing. Build it with: docker build -t $($config.ServerImage) `"$($config.RepoPath)`""
        }
        Write-DevStep "building $($config.ServerImage) from $($config.RepoPath)"
        Write-DevWarn 'compiling the Rust server takes a while on a cold cache'
        Invoke-DevDocker -Arguments @('build', '-t', $config.ServerImage, '.') -WorkingDirectory $config.RepoPath
    }

    Up          = {
        param($ctx, $options)
        $config = $ctx.Config

        Write-DevStep "starting $($config.InfraServices -join ', ')"
        # This compose file gives postgres no volume, so recreating a container
        # throws its data away. Never do that unless the caller asked for it.
        $composeArgs = @('up', '-d')
        $composeArgs += if ($options.Recreate) { '--force-recreate' } else { '--no-recreate' }
        Invoke-DevCompose `
            -ProjectPath $config.RepoPath `
            -Project $config.ComposeProject `
            -ComposeFiles @($config.ComposeFile) `
            -EnvFile $config.EnvFile `
            -Arguments ($composeArgs + @($config.InfraServices))

        $gotrueReady = Wait-DevCondition `
            -Probe { param($c) Test-DevHttp -Url "http://localhost:$($c.Config.GotruePort)/health" } `
            -ArgumentList $ctx `
            -TimeoutSec $config.StartupTimeoutSec `
            -Activity 'waiting for gotrue'
        if (-not $gotrueReady) {
            throw 'gotrue did not become healthy; run "dev-services.ps1 logs appflowy-cloud" or check docker compose logs.'
        }

        $documentServerState = Get-DevContainerState -Name $config.DocumentServerContainer
        if ($documentServerState -ne 'running') {
            throw "document server container $($config.DocumentServerContainer) is not running"
        }
        $documentServerNetworks = (
            Invoke-DevDocker `
                -Arguments @('inspect', '--format', '{{json .NetworkSettings.Networks}}', $config.DocumentServerContainer) `
                -Capture
        ) -join ''
        if ($documentServerNetworks -notmatch [Regex]::Escape('"' + $config.Network + '"')) {
            Write-DevStep "connecting $($config.DocumentServerContainer) to $($config.Network)"
            Invoke-DevDocker -Arguments @('network', 'connect', $config.Network, $config.DocumentServerContainer)
        }

        $environment = [ordered]@{
            APP_ENVIRONMENT             = 'production'
            APPFLOWY_APPLICATION_PORT   = "$($config.ServerPort)"
            APPFLOWY_DATABASE_URL       = $config.DatabaseUrl
            APPFLOWY_GOTRUE_BASE_URL    = 'http://gotrue:9999'
            APPFLOWY_GOTRUE_JWT_SECRET  = $config.GotrueJwtSecret
            APPFLOWY_REDIS_URI          = $config.RedisUri
            APPFLOWY_S3_ACCESS_KEY      = $config.S3AccessKey
            APPFLOWY_S3_BUCKET          = $config.S3Bucket
            APPFLOWY_S3_CREATE_BUCKET   = 'true'
            APPFLOWY_S3_MINIO_URL       = $config.MinioUrl
            APPFLOWY_S3_SECRET_KEY      = $config.S3SecretKey
            APPFLOWY_S3_USE_MINIO       = 'true'
            APPFLOWY_WEB_URL            = $config.WebUrl
            APPFLOWY_DOCUMENT_SERVER_PUBLIC_URL        = $config.DocumentServerPublicUrl
            APPFLOWY_DOCUMENT_SERVER_INTERNAL_URL      = $config.DocumentServerInternalUrl
            APPFLOWY_DOCUMENT_SERVER_CALLBACK_URL      = "http://$($config.ServerContainer):$($config.ServerPort)"
            APPFLOWY_DOCUMENT_SERVER_JWT_SECRET        = $config.DocumentServerJwtSecret
            APPFLOWY_DOCUMENT_SERVER_MAX_FILE_SIZE_BYTES = "$($config.DocumentServerMaxFileSizeBytes)"
            PORT                        = "$($config.ServerPort)"
            RUST_BACKTRACE              = '1'
            RUST_LOG                    = $config.RustLog
        }

        Start-DevContainer `
            -Name $config.ServerContainer `
            -Image $config.ServerImage `
            -Ports @("$($config.ServerPort):$($config.ServerPort)") `
            -Environment $environment `
            -Network $config.Network `
            -RestartPolicy $config.RestartPolicy `
            -Command @('appflowy_cloud') `
            -Recreate:($options.Recreate -or $options.Rebuild) | Out-Null
    }

    Health      = @{
        TimeoutSec  = 180
        IntervalSec = 3
        Activity    = 'waiting for the cloud API'
        Probe       = {
            param($ctx)
            if (-not (Test-DevHttp -Url "http://localhost:$($ctx.Config.ServerPort)/health")) {
                return $false
            }
            $documentServerHealth = (
                Invoke-DevDocker `
                    -Arguments @(
                        'exec',
                        $ctx.Config.ServerContainer,
                        'curl',
                        '-fsS',
                        "$($ctx.Config.DocumentServerInternalUrl)/healthcheck"
                    ) `
                    -Capture `
                    -AllowFailure
            ) -join ''
            return $documentServerHealth.Trim().ToLowerInvariant() -eq 'true'
        }
    }

    Down        = {
        param($ctx, $options)
        $config = $ctx.Config
        Stop-DevContainer -Name $config.ServerContainer -Remove:$options.Destroy

        if ($options.Destroy) {
            Write-DevWarn 'this compose file keeps postgres data inside the container, so every workspace stored locally is lost'
            Invoke-DevCompose `
                -ProjectPath $config.RepoPath `
                -Project $config.ComposeProject `
                -ComposeFiles @($config.ComposeFile) `
                -EnvFile $config.EnvFile `
                -Arguments @('down', '-v') -AllowFailure
            return
        }

        Write-DevStep 'stopping the cloud infrastructure'
        Invoke-DevCompose `
            -ProjectPath $config.RepoPath `
            -Project $config.ComposeProject `
            -ComposeFiles @($config.ComposeFile) `
            -EnvFile $config.EnvFile `
            -Arguments @('stop') -AllowFailure
    }

    Status      = {
        param($ctx, $options)
        $config = $ctx.Config
        $parts = @()
        foreach ($name in @($config.InfraServices)) {
            $state = Get-DevContainerState -Name "$($config.ComposeProject)-$name-1"
            if ($state -ne 'running') { $parts += "$name=$state" }
        }
        $serverState = Get-DevContainerState -Name $config.ServerContainer
        $state = if ($parts.Count -gt 0) { "$serverState (" + ($parts -join ' ') + ')' } else { $serverState }
        $documentServerHealth = if ($serverState -eq 'running') {
            (
                Invoke-DevDocker `
                    -Arguments @(
                        'exec',
                        $config.ServerContainer,
                        'curl',
                        '-fsS',
                        "$($config.DocumentServerInternalUrl)/healthcheck"
                    ) `
                    -Capture `
                    -AllowFailure
            ) -join ''
        } else {
            ''
        }
        @{
            State   = $state
            Healthy = (
                (Test-DevHttp -Url "http://localhost:$($config.ServerPort)/health" -TimeoutSec 3) -and
                $documentServerHealth.Trim().ToLowerInvariant() -eq 'true'
            )
        }
    }

    Logs        = {
        param($ctx, $options)
        Show-DevContainerLogs -Name $ctx.Config.ServerContainer -Tail $options.Tail -Follow:$options.Follow
    }

    Doctor      = {
        param($ctx, $options)
        $config = $ctx.Config
        $messages = @()
        if (-not (Test-Path -LiteralPath $config.RepoPath)) {
            $messages += "checkout missing at $($config.RepoPath)"
        }
        if (-not (Test-DevImageExists -Reference $config.ServerImage)) {
            $messages += "server image $($config.ServerImage) has not been built yet"
        }
        if ((Get-DevContainerState -Name $config.ServerContainer) -eq 'missing' -and (Test-DevTcpPort -Port $config.ServerPort)) {
            $messages += "port $($config.ServerPort) is already taken by something else"
        }
        if (-not (Test-DevNetworkExists -Name $config.Network)) {
            $messages += "network $($config.Network) does not exist yet; it is created by the first compose up"
        }
        if ((Get-DevContainerState -Name $config.ServerContainer) -eq 'running') {
            $documentServerHealth = (
                Invoke-DevDocker `
                    -Arguments @(
                        'exec',
                        $config.ServerContainer,
                        'curl',
                        '-fsS',
                        "$($config.DocumentServerInternalUrl)/healthcheck"
                    ) `
                    -Capture `
                    -AllowFailure
            ) -join ''
            if ($documentServerHealth.Trim().ToLowerInvariant() -ne 'true') {
                $messages += "cloud cannot reach the document server directly at $($config.DocumentServerInternalUrl)"
            }
        }
        return $messages
    }

    Info        = {
        param($ctx, $options)
        $config = $ctx.Config
        @{
            Endpoints = [ordered]@{
                'Cloud API'     = "http://localhost:$($config.ServerPort)"
                'GoTrue (auth)' = "http://localhost:$($config.GotruePort)"
                'MinIO console' = "http://localhost:$($config.MinioConsolePort)"
                'Postgres'      = "localhost:$($config.PostgresPort)"
            }
            Notes     = @(
                'In AppFlowy: Settings > Cloud Settings > Self-hosted, then use',
                "  Server URL   http://localhost:$($config.ServerPort)",
                "Sign in with $($config.AdminEmail) / $($config.AdminPassword) (email confirmation is auto accepted).",
                'Rebuild the server after changing the AppFlowy-Cloud sources: dev-services.ps1 up appflowy-cloud -Rebuild'
                'Office files use the managed document server automatically after sign-in; no client server settings are needed.'
                "Cloud document traffic goes directly to $($config.DocumentServerInternalUrl) over the Docker network."
            )
        }
    }
}
