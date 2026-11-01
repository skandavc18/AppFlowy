# AppFlowy dev services

One script to start, stop and inspect the local services AppFlowy talks to
while developing: the self hosted AppFlowy Cloud backend, the ONLYOFFICE
document server behind Word/Excel/PowerPoint editing, and whatever integration
comes next.

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
.\dev-services.ps1 up appflowy-cloud
.\dev-services.ps1 up cloud               # tag
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

### `appflowy-cloud` — self hosted backend

Brings up `postgres`, `redis`, `minio`, `gotrue` and `onlyoffice` from the
AppFlowy-Cloud checkout (`docker-compose-dev.yml` + `deploy.env`), then runs the
API server container on port 8000. Point AppFlowy at `http://localhost:8000` in
*Settings > Cloud Settings > Self-hosted* and sign in with
`admin@example.com` / `password`.

The server image is built from the checkout, so `-Rebuild` is how a locally
patched backend gets picked up.

#### ONLYOFFICE Docs

On Windows, macOS and Linux, office files no longer need this server: they
open in the editor bundled with AppFlowy (see *Built-in office editor* below).
The document server remains behind `.docx`, `.xlsx` and `.pptx` editing for
files stored in AppFlowy Cloud and on mobile. It is a service in that same
compose file, so compose owns its lifecycle, health check and volumes.
It listens on `127.0.0.1:8080` and the API server reaches it as
`http://onlyoffice` over the compose network.

When AppFlowy is signed in to the local AppFlowy Cloud service, office files
in cloud storage connect through Cloud automatically and saves flow back
through it. Builds without the bundled editor can still enter these values by
hand:

| Field | Value |
| --- | --- |
| Server URL | `http://localhost:8080` |
| JWT secret | `appflowy-office-dev-secret` |
| Bridge host | `host.docker.internal` |

Local-only mode serves the file from a short-lived HTTP bridge, so if that mode
loads the editor but not the document, allow AppFlowy through Windows Firewall.
Cloud mode keeps the JWT secret and save callback inside the Docker network.

#### Built-in office editor

Desktop builds ship ONLYOFFICE's editors with the x2t converter compiled to
WebAssembly (the static build of
[ranuts/document](https://github.com/ranuts/document), AGPL-3.0), so Word,
Excel and PowerPoint files open, edit and save without any server. Fetch the
pinned, digest-verified build once per checkout:

```powershell
cd frontend\appflowy_flutter
dart run tool\office_editor\fetch_office_editor.dart
```

It unpacks into `frontend/appflowy_flutter/office_editor/` (gitignored, about
420 MB, most of it fonts). The Linux and Windows CMake files install it into
the bundle's `data/office_editor`, and the macOS Xcode project into
`AppFlowy.app/Contents/Resources/office_editor`; `tool/build_windows_bundles.ps1`
fetches it automatically. Set `APPFLOWY_OFFICE_EDITOR_DIR` to use another copy.

AppFlowy serves the editor from a loopback HTTP server and shows it inside the
document page: in a WebView on Windows and macOS, and on Linux, where Flutter
has no WebView, in an offscreen WebKitGTK view drawn into a Flutter texture
(`packages/appflowy_linux_webview`). That needs the `libwebkit2gtk-4.1-0`
package at runtime (nothing extra to build). With WebKitGTK 2.44 or newer the
view renders on the GPU and hands its frames over in shared memory
(`WEBKIT_DMABUF_RENDERER_FORCE_SHM`, which AppFlowy sets unless it is already
set; `0` keeps rendering on the CPU). On Windows and Linux, wheel and trackpad
scrolling over a document follow the app's own smooth scrolling and inertia
rather than ONLYOFFICE's row-by-row steps. Edits save straight back to the
file. Builds without the editor fall back to the document server settings
above.

## Machine specific settings

Copy `dev-services.local.example.json` to `dev-services.local.json` (gitignored)
and override any key from a service's `Defaults` block — a different checkout
path, a free port, another JWT secret:

```json
{
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
