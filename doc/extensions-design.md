# AppFlowy Extensions — Design

Status: **v1 (Actions) + v2 (JS script steps) + v3 (Islands) + v4 (Dart host) built** ·
Last revised 2026-08-20

How AppFlowy is extended: new blocks, new page types, new themes, background jobs,
custom interactive surfaces, and tools the AI agent can call.

Built so far — `lib/extensions/application/`:
`extension_manifest.dart` · `action_definition.dart` · `action_schedule.dart` ·
`action_template.dart` · `action_run.dart` · `extension_data_store.dart` ·
`extension_store.dart` · `action_runner.dart` · `action_scheduler.dart` ·
`extension_run_log.dart` · `extension_tool_server.dart` · `extension_manager.dart` ·
`script_host.dart` · `extension_library_cache.dart` · `island_server.dart`;
UI in `lib/extensions/presentation/` (`extensions_page.dart` reached from the sidebar above
Trash, `settings_extensions_view.dart`, shared `extension_views.dart`,
`island_block_component.dart`, `island_slash_items.dart`); tests in
`test/unit_test/extensions/extensions_test.dart`.

⚠️ v2 note: libraries are handed to the worker as **source text**, not fetched by the page and
not served over a loopback origin. A glue script needs no origin at all, and keeping the page
with zero outbound reach is the whole sandbox.

⚠️ **The undo question in §6 rule 1 is SETTLED.** `EditorState.apply(isRemote: true)` routes to
`_applyTransactionFromRemote` and returns *before* `_recordRedoOrUndo`, so a backend change can
never enter the undo stack. But the design was WRONG about liveness:
`DocumentBloc._onDocumentStateUpdate` returns early unless the event is `isRemote` **and**
document sync is on, so an open editor would have shown stale content. Every `af.document` write
now calls `DocumentBloc.forceReloadDocumentState()` → `syncV3()`, which re-reads, **diffs** and
applies only what changed as a remote transaction. Live and undo-safe.

---

## 1. Goals, non-goals, and the three tiers

### Goals

- Add a **background job** — a periodic sync, a trigger-driven action — **without recompiling**.
- Add a **custom interactive surface** (a candlestick chart with buy/sell, a live dashboard)
  without recompiling.
- Add **deep capability** — a new block type, a `/` menu entry, a whole theme, a new page
  kind — with no ceiling on what it can draw or reach.
- Every capability an extension declares is **simultaneously available to the AI agent**,
  with one declaration.

### Non-goals

- **Distributing extensions to other people.** Single user, single machine, local folders.
  No signing, no marketplace, no untrusted-code threat model.
- **API stability.** Registries may be refactored freely.
- **Running when the app is closed.** See §7.

### The three tiers

| Tier | Language | Rebuild? | Use for |
|---|---|---|---|
| **1. Actions** | JSON recipes, JS steps, MCP tools | **No** | Background jobs, triggers, computation, agent tools |
| **2. Islands** | HTML/JS in a webview | **No** | Custom interactive rendering — charts, canvases |
| **3. Dart extensions** | Dart, compiled in | Yes | Blocks, slash items, themes, view kinds, painters |

Tiers 1 and 2 are the no-rebuild path and cover the long tail. Tier 3 is where the ceiling
is removed. **All three register into the same registries** — an action is an `AITool`, an
island is a block type whose renderer is a webview, and a Dart extension can register both.

---

## 2. Why not runtime Dart

Recorded so it is not relitigated.

**Flutter cannot load Dart code at runtime.**

- AOT builds (release/profile) have no `dlopen` for Dart. `dart:mirrors` is unsupported.
- Flutter does not support `Isolate.spawnUri` — the kernel compiler lives in `flutter_tools`,
  not in the app — so it does not work in Debug either.
- `dart_eval` / `flutter_eval` interpret a *subset* of Dart in pure Dart, need hand-written
  bindings for every host type, and have thin Flutter widget support. Not a foundation to
  bet the design on.

Therefore a Dart extension is **compiled in**: its source lives in the repo, `flutter build`
picks it up, hot reload covers authoring, and the rebuild is the publish step.

⚠️ This is why tiers 1 and 2 exist at all. Without them every change to a stock poller would
be a five-minute Windows rebuild.

---

## 3. Extension folder, manifest, permissions

### Layout

```
<appDataPath>/extensions/<id>/
  manifest.json          identity, permissions, secrets, library declarations
  libraries.lock.json    resolved name → version → sha384 → cached path  (generated)
  actions/*.json         triggers + steps; each is also an AITool
  scripts/*.js           JS steps
  web/<name>/            island assets (index.html + cached libraries)
  data/                  the extension's own jailed storage
```

`<appDataPath>` is `ApplicationDataStorage`, beside `page_versions/` and
`bookmark_snapshots/`. A **dev path override** points the loader at a working folder outside
the workspace so the extension can be edited in place.

Dart extensions live in the repo, not here (§10), but register into the same registries and
may own a folder here for their data.

### Manifest

```jsonc
{
  "id": "finance",
  "name": "Finance",
  "version": "1.0.0",
  "apiVersion": 1,
  "permissions": [
    "data",                                  // af.data read/write
    "document:write",                        // af.document mutation
    "net:query1.finance.yahoo.com",          // one host per entry, no wildcards at root
    "notify"
  ],
  "secrets": ["alphavantage_key"],
  "libraries": [
    { "name": "lightweight-charts", "version": "4.1.3",
      "url": "https://cdn.jsdelivr.net/npm/lightweight-charts@4.1.3/dist/…",
      "integrity": "sha384-…" }
  ]
}
```

### Permissions

Reuse the existing machinery rather than inventing a second one:
`AIToolRisk {read, write, destructive}` and `AIToolPermission {ask, allow, deny}` from
[`lib/ai/tools/`](../frontend/appflowy_flutter/lib/ai/tools/), including the approval dialog
that shows arguments in full.

- Reads never ask.
- Writes and destructive operations ask once and remember the answer.
- An explicit `deny` outranks any broader grant.
- **Network is allowlisted per host**, enforced by the host, not the extension. The island
  and the JS worker have no outbound channel at all (§8), so this is a real boundary and
  not a policy.

Secrets live in `ProviderSecretStore` (DPAPI on Windows) and are **injected host-side at
call time**. They never enter the JS worker, the island, or a recipe's rendered template.

### Comments in JSON

Recipes are hand-written, so the loader strips `//` line comments before `jsonDecode`.
Everything else is plain JSON — no new dependency, and the action schema is JSON Schema
already.

---

## 4. Actions

An action is **a trigger plus steps**, declared in JSON. It is also, by construction, an
`AITool` (§5).

```jsonc
{
  "id": "finance.quote",
  "description": "Latest price for a ticker.",
  "risk": "read",
  "schema": {                                  // JSON Schema for arguments
    "type": "object",
    "properties": { "symbol": { "type": "string" } },
    "required": ["symbol"]
  },
  "trigger": { "every": "15m", "forEach": { "data": "finance.watchlist" } },
  "steps": [
    { "id": "fetch", "http": { "get": "https://…/{{ symbol }}" } },
    { "when": "{{ fetch.status }} == 200",
      "set": { "key": "finance.quote.{{ symbol }}",
               "value": "{{ fetch.body.chart.result.0.meta.regularMarketPrice }}" } }
  ]
}
```

### Trigger catalog

Every one of these has existing plumbing.

| Trigger | Fires on | Plumbing |
|---|---|---|
| `every`, `at`, `cron` | a schedule | new scheduler (§7) |
| `onStart`, `onResume` | app lifecycle | `AppLifecycleState` |
| `onDocumentOpen/Change/Close` | a page (debounced) | `ViewListener`, `editorState.transactionStream` |
| `onRowAdded/Changed`, `onCellChanged` | a database | `RowCache.onRowsChanged` |
| `onReminderFired` | a reminder, by tag | `ReminderStore` + notification scheduler |
| `onBlockVisible`, `onBlockAction` | a block | block registry |
| `onCommand` | slash / palette / button | command registry |
| `onMessage` | an island posting to the host | bridge (§8) |
| *(none)* | called by the agent, or by another action | `AIToolRegistry` |

`onReminderFired` is the "custom reminder that does something" case: a reminder carries a
tag in `ReminderPB.meta`, and an action subscribes to it.

### Step types

| Step | Does |
|---|---|
| `http` | request against an allowlisted host; secrets injected host-side |
| `mcp` | call a configured MCP tool |
| `script` | run a JS function from `scripts/` (§8) |
| `set` / `delete` | write `af.data` |
| `document` | mutate a page (§6) |
| `file` | write a workspace file |
| `notify` | toast / system notification |
| `reminder` | create, complete or snooze a reminder |
| `action` | call another action |

### ⚠️ The recipe format is not a programming language

Steps, `{{ }}` templating over prior step results, and a `when:` condition with a **flat
comparison** — that is the whole language. **No loops, no functions, no expression DSL, no
arithmetic beyond comparison.**

The moment a recipe wants more, it uses a `script` step or an MCP tool. Every configuration
format that ignored this rule became a bad programming language. `forEach` over a data key
is the single concession, because fanning one action across a watchlist is the common case.

### Reloading

The extensions folder is **watched**. Editing an action's JSON reloads it without restarting
the app. That is the entire tier-1 development loop.

---

## 5. Unification with MCP

An action and an MCP tool are the same object: a name, a description, a JSON Schema, a risk
level. `McpClient` already `implements AIToolServer`.

Each extension therefore contributes **one `AIToolServer`** exposing its actions, registered
alongside the built-in workspace server and the user's MCP servers. Tool names are already
namespaced (`AITool.qualifiedName` = `<serverId>__<tool>`), so nothing collides.

**One declaration, four invocation paths:**

```
                 ┌── the AI agent            (AIToolRegistry.run, existing)
   action  ──────┼── a trigger               (scheduler / event)
   (= AITool)    ├── a UI affordance         (slash, palette, block button)
                 └── an island               (postMessage → bridge)
```

Consequence worth stating: writing a `finance.quote` action means the chat agent can answer
"what's AAPL at" with no extra work, under the same consent it would need for any other tool.

### MCP servers are configured separately

MCP servers stay in **Settings ▸ AI**, not bundled inside extension folders. An extension
that needs one documents it; the user configures it once and every extension can reach it.

Transports:

| | stdio | http |
|---|---|---|
| Windows / macOS / Linux | ✅ | ✅ |
| Android / iOS | ❌ (§11) | ✅ |

A remote MCP server means workspace data leaves the device; remote servers are marked as
such in the settings list.

---

## 6. Data model — `af.data` and `af.document`

### `af.data` is the default

A reactive, keyed, per-extension store that is **not part of any document**.

- Actions write it; blocks, islands and dashboard widgets subscribe and rebuild.
- The document stores *which ticker*; `af.data` holds *what price*.
- No undo entries, no collab sync rounds, no page-version churn.

⚠️ **This is the single decision that makes periodic updates viable.** A 15-minute action
writing into block attributes would add an undo entry, a sync round and a version snapshot
every 15 minutes, forever.

Values are cached to disk so a restart shows the last known value rather than a blank card,
with a `staleAfter` so a card can say it is showing something old.

### `af.document` is full-scope, with three rules

Insert, update, delete, move — the whole surface, as
[`DocumentToolkit`](../frontend/appflowy_flutter/lib/ai/tools/document_toolkit.dart) already
provides it to the agent.

1. **⚠️ Writes go through `applyAction`, never through a local `EditorState` transaction.**
   A backend collab change reaches an open editor as a *remote* change, so it stays out of
   the user's undo stack. Otherwise Ctrl+Z after a refresh undoes the robot instead of your
   last paragraph. *(To be verified empirically before it is relied on.)*

2. **⚠️ The document must be opened first.** `DocumentEventOpenDocument`, not
   `GetDocumentData` — the latter builds a throwaway, sync-disabled instance and every write
   is silently dropped with "Call open document first". `DocumentToolkit.open()` handles this,
   including creating a row page that does not exist yet via `createOrphanView`.

3. **⚠️ Never write into a page the user is actively editing.** If an editor is open for that
   view and has had a transaction inside the quiet period, defer. Prefer writing *attributes*
   over *text* — rewriting a block's delta under a live caret moves it.

Machine edits carry a flag the **page-version recorder ignores**. It already dedupes on
`contentHash`, but a changing price changes the hash every time, so an explicit suppression
is required.

### `af.files`

Writing a workspace file is a separate path from writing blocks. It needs a cache
invalidation signal so open viewers re-read — the `RowPageText.forget` pattern.

---

## 7. The scheduler

**One token-bucket runner for every action in every extension.** Twenty extensions each with
their own `Timer.periodic` will stutter the UI.

- Concurrency cap; foreground work preempts.
- Hard deadline per run (the `AIToolRegistry.runTimeout` precedent — 90 s).
- Jittered backoff honouring `429`/`503` and `Retry-After`.
- Paused when the window is hidden; on mobile, paused when backgrounded.
- **Catch-up on launch**: a schedule missed while the app was closed runs once at startup,
  coalesced — not once per missed interval.

### ⚠️ Nothing runs while the app is closed

There is no background worker in AppFlowy. The mail sync feature already had to say this out
loud rather than promise mail that never arrives; actions must do the same. The API names it
(`runsWhileOpen`) and the run log shows it.

### Run log

**Not optional.** A periodic action that silently stops is the worst failure mode there is,
and this codebase has repeatedly lost days to silent failures — a toast API that returned
`-1` forever, a connection list that erased itself, a settings store that latched "loaded"
after reading nothing.

Per extension: last run, duration, outcome, error, next scheduled run, and a **Run now**
button. Reachable from Settings ▸ Extensions and from any block an extension owns.

---

## 8. The JS tier

Two hosts, one bridge, one library cache.

### Headless worker — for `script` steps

A single long-lived `HeadlessInAppWebView` (already used by
[`bookmark_browser_reader.dart`](../frontend/appflowy_flutter/lib/workspace/application/collections/bookmark/bookmark_browser_reader.dart)),
each extension a `Web Worker` inside it, under the CSP already proven by
[`sandboxed_code_runner.dart`](../frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart):

```
default-src 'none'; script-src 'self' blob:; worker-src blob:; connect-src 'none'
```

⚠️ `connect-src 'none'` is the point. **A worker under this CSP has no network, no
filesystem and no DOM.** Every effect must travel through `postMessage` to Dart, where the
permission check lives. That is capability security by construction, not by policy.

### Island — for custom rendering

A block type whose renderer is a visible `InAppWebView` serving the extension's `web/<name>/`
folder over an ephemeral loopback `HttpServer` behind a random path token — the recipe
already used twice, by
[`excalidraw_host.dart`](../frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/drawing/excalidraw_host.dart)
and
[`office_document_bridge.dart`](../frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/file/office/office_document_bridge.dart).

- One origin (port) per extension, so `localStorage` cannot leak across extensions.
- Same CSP; `script-src 'self'` only. No CDN reachable from the page.
- Theme tokens injected as CSS custom properties, plus `prefers-color-scheme` through
  `Emulation.setEmulatedMedia` (as `BookmarkWebPage` already does).
- Sized with `ResizableMedia`, like every other embed.

### Bridge

```js
await af.call('finance.quote', { symbol: 'AAPL' });   // any action or MCP tool
af.on('data:finance.quote.AAPL', v => chart.update(v));
const LWC = await af.require('lightweight-charts@4.1.3');
```

`af.call` resolves against the same registry the agent uses, so an island gets consent
prompts and risk levels for free.

### Library cache

**Never let the page reach a CDN.** A `<script src="https://…">` re-opens the exfiltration
channel that `connect-src 'none'` closes, and the fetched script then runs with full page
privileges.

Instead: the **host** fetches, verifies the `sha384`, writes into the extension's `web/`
folder and serves it from the loopback origin. `af.require()` resolves
**cache → manifest → fetch once (with consent) → verify → cache → pin**, and pins the
resolved version and hash into `libraries.lock.json`.

This gives CDN convenience with none of the risk, works offline after the first fetch,
survives a CDN outage, and makes the folder reproducible. "Pre-bundled" is then just
"pre-seeded into the cache" — one mechanism. Seed a small set (`lightweight-charts`, `dayjs`,
`d3`); everything else arrives on demand.

---

## 9. ⚠️ Windows platform-view rules for islands

Every one of these has already cost this repo a crash or a renderer fault. They are not
optional.

- **Never put a changing `key` on the `InAppWebView`.** It destroys and recreates the
  composition surface; `dcomp.dll` `0xe0464645`. Call `reload()` instead.
- **Do not build the view below 64 px** in either dimension — a degenerate composition
  surface faults.
- **Defer creation until the route animation is `completed`**, with a timer backstop (a
  listener attached while the route is already settling never fires).
- **Tear down on `AnimationStatus.reverse`**, before the closing fade, not during it.
- Guard every platform callback with a `_closing` flag and null the controller in `dispose`.
- Scrolling: an island is a **local, non-navigating** document, so the Dart-driven kinetic
  engine (`file_preview.dart::_HtmlPreview`) is the proven path — *not* the "let the renderer
  scroll natively" answer that remote pages needed. Wrap in `PremiumScrollExclusion`.

---

## 10. The Dart tier

### Shape

```dart
abstract class AppFlowyExtension {
  ExtensionManifest get manifest;
  Future<void> activate(ExtensionContext ctx);
  Future<void> deactivate();
}
```

`ExtensionContext` is the API, namespaced by facade:

| Facade | Registers | Today |
|---|---|---|
| `ctx.blocks` | block type: builder, settings schema, markdown parser, `::` actions | builder map exists, no registry |
| `ctx.slash` | `/` entries | `SlashMenuSection` exists, hardcoded |
| `ctx.dashboard` | dashboard widgets | **`DashboardWidgetRegistry.register` works today** |
| `ctx.views` | whole page types | pattern done 6× (chart, map, slide, dashboard, canvas, collection) — needs extracting |
| `ctx.tableViews` | table readings | **6 hardcoded edits per kind — needs a registry** |
| `ctx.collections` | collection views | `CollectionRegistry.registerView` exists |
| `ctx.theme` | a theme | new |
| `ctx.document` / `ctx.database` / `ctx.workspace` | read + write | `DocumentToolkit` + workspace tools cover most |
| `ctx.data` / `ctx.storage` | reactive store, jailed files | new |
| `ctx.net` | http + secrets | `ProviderTransport`, `ProviderSecretStore` |
| `ctx.jobs` | triggers | shares the tier-1 scheduler |
| `ctx.ui` | toasts, dialogs, menus, panels, a settings page | mostly exists, no registry |
| `ctx.ai` | expose a tool | `AITool` exists |

### Registration

One `extension_registry.dart` lists the built-in extensions. That is the one file edited to
add one. Enable/disable state and settings live in KV, so an extension is conceptually
*installed* even though it is compiled in.

Extensions live in a **separate package** (`packages/appflowy_extensions/`) rather than in
`lib/`, so "what is public API" is answered by the compiler instead of by discipline.

### Four things that need real work

1. **Lift `DashboardConfigField` into `lib/shared/settings_schema/`.** ✅ **Done.** The generic
   rows (text, number, toggle, choice, group, button, note) are now `SettingsField` under
   dashboard-facing typedefs, and only the rows that genuinely need dashboard concepts —
   accent, source, view, place, options, action, binding — are still declared in
   `dashboard_config_field.dart`, extending the shared base.

   ⚠️ `SettingsField` is deliberately **not sealed**: a sealed class can only be extended
   inside its own library, which would have made the dashboard's own rows impossible. Every
   renderer therefore needs a fallback arm, and both have one. `SettingsChoiceField` and
   `SettingsGroupField` took the dashboard's richer shapes (a list of `SettingsChoice` with
   icons and descriptions; nested `fields`), since those were the proven ones.

2. **Teardown.** No registry has `unregister`. If an extension can be disabled without a
   restart, every registry needs removal and every extension needs a disposable scope owning
   its timers, listeners and blocs.

3. **Registries for view kinds and table view kinds.** Adding a table reading is currently six
   edits across exhaustive switches. That has to become data.

4. **Error boundaries.** A compiled-in extension that throws in `build` takes the frame down.
   Extension-provided builders are wrapped in a catching widget that names the extension;
   async work runs in a guarded zone and reports to the run log.

### Themes get their ceiling raised

Because a Dart theme is compiled, it can be code — a real `PremiumThemeExtension` +
`PaperThemeExtension` plus its own `BackdropFilter` surface recipes and shaders.
`BookReaderPalette.themeFor` already proves a whole theme can be projected by rewriting the
theme extensions. **A "glass theme engine" is achievable here and would not have been in JS**,
where per-frame callbacks at 120 Hz are impossible.

A JSON theme recipe (tokens only, no code) is also read from the extensions folder, so the
common case needs no rebuild.

---

## 11. `ProcessHost` and embedded runtimes

### The observation

Five features shell out to a local program, all through one seam
(`resolveExecutable` → `Process.start`), and **all five are dead on mobile**:

| Consumer | |
|---|---|
| stdio MCP servers | `ai/tools/mcp_client.dart` |
| Code block runner (py/c/cpp/java/kt/rs) | `editor_plugins/file/local_code_runner.dart` |
| Jupyter notebook kernel | `editor_plugins/file/notebook/notebook_kernel.dart` |
| OCR (powershell / tesseract) | `editor_plugins/image/ocr/ocr_service.dart` |
| git (source-control views) | `workspace/application/providers/git/git_repository.dart` |

So an embedded runtime is a **platform capability with five existing consumers**, not an
extension-system feature.

### The seam

```dart
abstract class ProcessHost {
  bool provides(String program);
  Future<HostedProcess> spawn(String program, List<String> args, {env, cwd});
}
```

- `NativeProcessHost` — today's `Process.start`
- `EmbeddedPythonHost` — in-process CPython, answers `provides('python')`
- later: `WasmHost`

Everything above is already line-oriented stdio, so **nothing downstream changes**: the
notebook's `{"op":"run"}` driver, MCP's JSON-RPC and the code runner's streaming stdin all
work verbatim. `McpTransport.embedded` is "stdio, but in-process".

### Why in-process, on both mobile platforms

- **Android** (PEP 738, CPython 3.13 Tier 3): since API 29, an app cannot execute a file from
  its writable data directory. A `python` binary would have to ship inside the APK as a
  `lib*.so`. In-process embedding sidesteps this entirely. Native wheels come from Chaquopy's
  curated repository or are pre-bundled.
- **iOS** (PEP 730, CPython 3.13 Tier 3): no `fork`/`exec` at all, ever — in-process is the
  *only* route. Binary extension modules must ship as individually code-signed frameworks in
  the app bundle. Pure-Python packages are fine; runtime installation of native wheels is out.
  No JIT.

Both converge on the same design. Routes to evaluate: `serious_python` (pub.dev, Flet) as the
fast path, versus wiring BeeWare's `Python-Apple-support` and the Android AAR by hand. Risks
are bundle size (~10–20 MB per ABI before packages) and the wheel story. **Prototype before
committing.**

### C/C++ on mobile

The blocker is not the compiler — bundling a toolchain works. **Executing the output is what
fails**: the produced binary lands in writable storage, which Android 10+ refuses to exec, and
iOS forbids codegen-and-run outright. Two routes that do work: compile to WebAssembly and run
it in the island sandbox, or compile and run remotely through an MCP server. **Parked.**

### Staging

**The extension system does not depend on any of this.** v1 ships on `stdio` (desktop) and
`http` (everywhere); mobile gets actions, recipes, islands and remote/LAN Python. The embedded
runtime is justified independently by its five consumers and is adopted as a third transport
when it lands.

---

## 12. Platform matrix

| | Windows / macOS / Linux | Android | iOS |
|---|---|---|---|
| JSON action recipes | ✅ | ✅ | ✅ |
| Scheduler + triggers | ✅ | ✅ (foreground only) | ✅ (foreground only) |
| `af.data` / `af.document` / `af.files` | ✅ | ✅ | ✅ |
| JS `script` steps (headless worker) | ✅ | ✅ | ✅ |
| Islands (webview blocks) | ✅ | ✅ | ✅ |
| Library cache / `af.require` | ✅ | ✅ | ✅ |
| Dart extensions | ✅ | ✅ | ✅ |
| MCP over http | ✅ | ✅ | ✅ |
| MCP over stdio | ✅ | ❌ → embedded | ❌ → embedded |
| Runs while app is closed | ❌ | ❌ | ❌ |

---

## 13. Phasing

### v1 — Actions

Manifest, folder loading and watching, JSON recipes, the trigger catalog, the shared
token-bucket scheduler, `af.data`, `af.document` with the three rules, per-extension
`AIToolServer` registration, permissions on the existing machinery, and the run log.

*Ends with: the stock sync working, on desktop and mobile, with no rebuild, callable by the
agent.*

**Explicitly excluded from v1:** JS of any kind, islands, Dart extensions, embedded runtimes,
theme extensions, enable/disable-at-runtime for Dart extensions.

### v2 — JS steps

Headless worker, bridge protocol, library cache and `libraries.lock.json`, `af.require`.

### v3 — Islands

Visible webview block type, loopback asset server, theme token injection, `ResizableMedia`
sizing, and every rule in §9.

*Ends with: the candlestick chart with buy/sell.*

### v4 — Dart extension host

`ExtensionContext`, lifecycle and teardown, the shared settings schema lifted out of
`DashboardConfigField`, registries for blocks / slash / themes / view kinds, error boundaries.

**Built** — `lib/extensions/dart/`: `appflowy_extension.dart` (`ExtensionScope`) ·
`extension_registries.dart` · `extension_context.dart` · `extension_boundary.dart` ·
`dart_extension_host.dart` · `built_in/data_block_extension.dart`, plus
`lib/shared/settings_schema/`.

A registered block reaches the editor (`editor_configuration.dart` spreads
`ExtensionBlockRegistry.builders` last), the slash menu (`island_slash_items.dart`) and
markdown export (`markdown_to_document.dart` spreads `ExtensionBlockRegistry.parsers`).
The host is started and stopped by `ExtensionManager`, and both the Extensions page and
Settings ▸ Extensions list built-in extensions with a switch each.

⚠️ **Registries without a consumer yet.** `ExtensionCommandRegistry` and
`ExtensionThemeRegistry` are complete and are unwound correctly on deactivate, and both now
have readers:

- **Commands** — `buildPaletteCommands` appends `ExtensionCommandRegistry.all()` under a new
  `PaletteCommandGroup.extensions`. The list is read as the palette opens, so turning an
  extension off removes its commands with no restart. An extension command dismisses the
  palette *first* and then runs against the root navigator, because it may open a route of its
  own and popping afterwards would close that instead.
- **Themes** — `MaterialApp.router` is wrapped in a `ListenableBuilder` on
  `ExtensionThemeRegistry.changes`, and both `theme:` and `darkTheme:` pass through
  `ExtensionThemeRegistry.apply(...)`. The choice lives in
  `ExtensionThemeRegistry.selected` (`<extensionId>/<themeId>`), persisted by
  `DartExtensionHost` under `appflowy_extension_theme`.

  `apply` returns the base theme unchanged when nothing is chosen, when the chosen theme's
  extension has been turned off, when the theme is for the other brightness, **and when the
  theme's own `build` throws** — a theme that could take the app down would leave no UI to
  turn the extension off with.

`GlassThemeExtension` is the worked example: it rewrites `PremiumThemeExtension`, which every
surface in the app already reads, so one object re-skins menus, dialogs, the sidebar and the
editor at once. That is precisely what a scripting tier could not have done.

**Table views** — `ExtensionTableViewRegistry` lets an extension add a new way of reading a
table. `TallyTableViewExtension` is the worked example.

⚠️ **A new *page type* is impossible from Dart, and always will be.** `ViewLayoutPB` is a
protobuf enum owned by the Rust backend; a layout code it does not know is rejected on the
wire. What *is* extensible is a table view: it rides on an existing Grid and lives in the
view's `extra` JSON, which the backend never interprets. Timeline, feed, form, gallery and
mailbox are all built with exactly that trick — the only difference is that they are compiled
into `TableViewKind` and an extension's is not.

So `TableViewMark` is now keyed by **envelope key** rather than by the enum
(`TableViewMark.forKey`, `fromExtraKey`, `envelopeKeyOf`), the built-in enum and its
exhaustive switches are untouched, and the six sites that used to need editing per kind —
tab bar content, sidebar icon, the tab-bar add menu, the explorer add menu, creation, and
settings persistence — each fall back to the registry. `DatabaseTabKind` became a value class
for the same reason: the add menu has to be able to offer a kind it has never heard of.

Two honest limits: the sidebar draws named SVGs rather than the Material glyph an extension
supplies, so every extension view shares one mark there; and a view whose extension is
switched off falls back to being an ordinary grid rather than rendering nothing.

### Later

`ProcessHost` + embedded Python; C/C++ via wasm.

---

## 14. Worked example — the finance extension

**A Dart version of this is built**: `built_in/stock_extension.dart`, switchable from
Settings ▸ Extensions like any other. It is the smallest thing that exercises every rule at
once:

- the **document** stores `{symbol, label}` only — never the price, because a block that
  stored the number would add an undo entry, a collab round and a page version on every tick;
- the **price** lives in `af.data` under `stock.quote.<SYMBOL>` with a 20-minute
  `staleAfter`, so the card redraws the moment a fetch lands and says so when it has gone off;
- a **job** (`ctx.jobs.every`) refreshes the watchlist every 5 minutes, and the watchlist is
  built by the blocks themselves — a card registers its ticker when it is first drawn;
- a **command** refreshes on demand from the palette;
- `ExtensionScope` unwinds the timer, the block, the command and the feed itself when the
  extension is switched off. `StockFeed.active` is nulled on dispose, so a card that somehow
  outlives the extension cannot keep fetching.

⚠️ **A disabled extension leaves its blocks in place, not deleted.** The editor falls back to
`errorBlockComponentBuilderKey`, so a `/Stock` card in a document becomes an error block that
still holds its JSON, and comes back untouched when the extension is switched on again. That
is the honest behaviour to expect from every tier-3 block.

The fuller JSON-tier version, still worth building for the parts Dart should not own:

```
extensions/finance/
  manifest.json          net:query1.finance.yahoo.com · secrets:[alphavantage_key]
                         libraries:[lightweight-charts@4.1.3]
  actions/quote.json     every 15m, forEach data 'finance.watchlist'
                         → http GET → set finance.quote.{{symbol}}
  actions/levels.json    risk:read · schema:{symbol,window}
                         → mcp 'ta.support_resistance'   (Python server, desktop)
  actions/order.json     risk:destructive · schema:{symbol,side,qty}
                         → mcp 'broker.place_order'
  scripts/shape.js       candles → the chart library's row shape
  web/chart/index.html   lightweight-charts, subscribes to af.data
```

- The block stores `{ "symbol": "AAPL" }` — configuration only, never the price.
- The island subscribes to `finance.quote.AAPL` and redraws when the action writes.
- *Buy* posts `af.call('finance.order', …)` → bridge → **destructive**, so consent is asked
  with the arguments shown → the broker MCP server.
- The agent can ask `finance.quote` and `finance.levels` directly; `finance.order` asks first.
- Nothing here required a rebuild.

The astrology example maps the same way: `swisseph` behind an MCP server for the ephemeris,
an island for the chart wheel, `af.data` for the computed positions — with the dasha table as
a **Tier A declarative view**, since it is a table and does not need a canvas.

---

## 15. Open questions

- **Does `applyAction` really stay out of the local undo stack** when the page is open?
  §6 rule 1 depends on it. Verify empirically before building on it.
- **`af.data` persistence policy** — how much history, what eviction, and does a value survive
  a workspace switch?
- **Island theming fidelity** — CSS custom properties get close, but a chart library's own
  defaults will fight the app's palette. How far is worth going?
- **Enable/disable at runtime for Dart extensions** — makes teardown mandatory and roughly
  doubles the registry work. Deferred to v4; decide before starting it.
