# AppFlowy dev services

One script to start, stop and inspect the local services AppFlowy talks to
while developing: the ONLYOFFICE document server behind Word/Excel/PowerPoint
editing, the self hosted AppFlowy Cloud backend, and whatever integration comes
next.

Everything runs in Docker, so Docker Desktop has to be running.

```powershell
cd frontend\scripts\dev_services

.\dev-services.ps1 up          # start every default service and wait for it
.\dev-services.ps1 status      # container state + health of each service
.\dev-services.ps1 info        # URLs and the settings to paste into AppFlowy
.\dev-services.ps1 down        # stop them, keeping all data
```

## Commands

| Command | What it does |
| --- | --- |
| `list` | Every known service, whether it is in the default set, its tags |
| `status` | Container state and a live health probe per service |
| `setup` | Only the one time preparation (pull/build images, validate paths) |
| `up` | `setup`, start, wait for health, then print the connection details |
| `down` | Stop the containers; add `-Destroy` to remove them and their volumes |
| `restart` | `down` followed by `up` |
| `logs` | Container logs, `-Follow` to stream, `-Tail <n>` for the backlog |
| `doctor` | Checks Docker, ports, checkouts and images without changing anything |
| `info` | Endpoints and AppFlowy settings without starting anything |

Select services by name, tag or wildcard; with no argument the default set is
used.

```powershell
.\dev-services.ps1 up onlyoffice
.\dev-services.ps1 up office              # tag
.\dev-services.ps1 logs appflowy-cloud -Follow
.\dev-services.ps1 up appflowy-cloud -Rebuild   # rebuild the image first
.\dev-services.ps1 up -All                # include services that are off by default
```

Switches: `-All`, `-Rebuild`, `-Recreate`, `-Destroy`, `-Force`, `-SkipHealth`,
`-Follow`, `-Tail <n>`.

`up` skips any service that is already running and answering its health probe,
so it is safe to run at any time. Pass `-Recreate`, `-Rebuild` or `-Force` to
make it work on a running service anyway.

`down -Destroy` removes volumes and asks for confirmation first. The AppFlowy
Cloud dev compose file keeps Postgres data inside the container, so destroying
it wipes every workspace stored on that instance.

## Services

### `onlyoffice` — ONLYOFFICE Docs

Serves the editor AppFlowy embeds for `.docx`, `.xlsx`, `.pptx` and friends.
Started as `appflowy-onlyoffice` on port 8080 with JWT enabled.

After `up`, open any office file in AppFlowy and fill the server panel with the
values the script prints:

| Field | Value |
| --- | --- |
| Server URL | `http://localhost:8080` |
| JWT secret | `appflowy-office-dev-secret` |
| Bridge host | `host.docker.internal` |

AppFlowy serves the file to the container from a short lived local HTTP bridge,
so if the editor loads but the document never appears, allow AppFlowy through
the Windows firewall.

### `appflowy-cloud` — self hosted backend

Brings up `postgres`, `redis`, `minio` and `gotrue` from the AppFlowy-Cloud
checkout (`docker-compose-dev.yml` + `deploy.env`), then runs the API server
container on port 8000. Point AppFlowy at `http://localhost:8000` in
*Settings > Cloud Settings > Self-hosted* and sign in with
`admin@example.com` / `password`.

The server image is built from the checkout, so `-Rebuild` is how a locally
patched backend gets picked up.

## Machine specific settings

Copy `dev-services.local.example.json` to `dev-services.local.json` (gitignored)
and override any key from a service's `Defaults` block — a different checkout
path, a free port, another JWT secret:

```json
{
  "onlyoffice": { "Port": 8081 },
  "appflowy-cloud": { "RepoPath": "D:\\AppFlowy-Cloud" }
}
```

## Adding an integration

Copy `services\_template.service.ps1` to `services\<name>.service.ps1` and fill
it in. The runner discovers every `*.service.ps1` in that folder, so there is
nothing else to register.

A manifest is a hashtable with:

- `Name`, `DisplayName`, `Summary`, `Tags`, `Order`, `Enabled`, `DependsOn`
- `Defaults` — the settings that `dev-services.local.json` can override
- `Setup`, `Up`, `Down`, `Status`, `Logs`, `Doctor`, `Info` scriptblocks that
  take `($ctx, $options)`
- `Health` — `@{ TimeoutSec; IntervalSec; Activity; Probe = { param($ctx) ... } }`

`$ctx.Config` is the merged configuration, and every helper from
`lib\common.ps1` (`Start-DevContainer`, `Invoke-DevCompose`, `Invoke-DevDocker`,
`Test-DevHttp`, `Wait-DevCondition`, `Write-DevStep`, ...) is available inside
the scriptblocks. `Up` must be idempotent: it is also what resumes an existing
container.
