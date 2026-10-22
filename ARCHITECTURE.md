# SparkClean.app — Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ UI (SwiftUI, AppKit where SwiftUI needs help)                │
│   ContentView + TopNavigationBar → section views             │
│   MenuBarScene → MenuBarPanel (independent of main window)   │
│   Sheets: Clean confirm · Uninstall confirm · Trash confirm  │
│           History · Settings · Welcome                       │
├──────────────────────────────────────────────────────────────┤
│ ViewModels (@MainActor ObservableObject state machines)      │
│   Clean · Apps · Optimize · Analyze · Status · MenuBar       │
├──────────────────────────────────────────────────────────────┤
│ SparkClean Engine Bridge                                    │
│   SparkCleanLocator   → find `mo` (override/Homebrew/PATH)    │
│   SparkCleanClient    → typed API: cleanDryRun/clean,          │
│                      appInventory/uninstallPlan/uninstall,   │
│                      optimizeDryRun/optimize, analyze,       │
│                      statusSnapshot/statusWatch, history     │
│   ProcessRunner    → the ONLY code that spawns processes:    │
│                      async run, stdin, streaming NDJSON,     │
│                      timeouts, cancellation, LC_ALL=C env    │
├──────────────────────────────────────────────────────────────┤
│ Parsers                                                      │
│   Codable models (SparkCleanModels) for status/analyze/history/│
│   uninstall --list JSON                                      │
│   Text parsers for clean / uninstall plan / optimize output  │
│   (shapes verified against CLI 1.53 + real captured output)  │
├──────────────────────────────────────────────────────────────┤
│ Support: preferences, error model, operation log access      │
└──────────────────────────────────────────────────────────────┘
```

## Data flow

1. **View** → ViewModel method (e.g. `startScan()`).
2. ViewModel → `SparkCleanClient` async call on a `Task`.
3. `SparkCleanClient` locates `mo`, runs it via `ProcessRunner` (never as root,
   `LC_ALL=C` for stable parsing, 8 MB output cap, hard timeouts).
4. Output is decoded/parsed into typed models.
5. ViewModel publishes state; SwiftUI re-renders. All UI work stays on the
   main actor; all subprocess I/O happens off it.

## Status streaming

`mo status --watch --interval Ns` emits NDJSON from a single warm collector
inside the CLI (accurate rate metrics across ticks). The app:

- primes the UI with one `mo status --json` snapshot,
- then consumes the watch stream line-by-line,
- applies each snapshot with a 0.3 s animation (throttled by the CLI interval),
- keeps bounded 60-point rolling series for sparklines,
- reconnects with backoff if the CLI exits,
- treats `process_stale: true` as "reused sample" and shows a badge; missing
  process fields are shown as absent, never fabricated.

Cancellation: pausing (scene phase) or restarting tears down the stream via
`onTermination`, which SIGTERMs the child collector.

## Cleanup flow (Clean)

```
idle ──Scan──▶ scanning (mo clean --dry-run) ──▶ results
                 │ pseudo-progress (CLI has no progress API;
                 │ deccelerating curve, never reaches 100%
                 │ before the real result)
results ──Clean──▶ confirmation sheet (total size, items,
                   categories, skipped count, file list)
        ──confirm──▶ cleaning (mo clean) ──▶ complete summary
                     (CLI's own accounting: size, items,
                      categories, skipped, free-space delta)
```

- Category selection maps onto what the CLI reports; "Select All / Deselect"
  operate on selectable (non-skipped) rows. Mole's engine revalidates every
  path at execution time — the app presents, it does not delete.
- Skipped rows display the CLI's own reason ("pnpm busy", whitelisted, …).

## Uninstall flow (Apps)

1. `mo uninstall --list` (piped → JSON) renders the inventory.
2. Selecting an app and pressing Remove fetches the REAL plan via
   `mo uninstall <name> --dry-run` (stdin-confirmed because the CLI asks; the
   plan is Mole's, not invented).
3. The confirmation sheet lists exact paths + sizes + Trash routing.
4. `mo uninstall <name>` runs only after explicit user confirmation; files go
   to the Trash (recoverable) by default, matching CLI behavior.

## Optimize flow

`mo optimize --dry-run` first (expands the real 21-task catalog with outcomes),
then the preview screen, then `mo optimize`. Tasks render as applied /
unchanged / skipped / unavailable / attention / failed — the six outcome
classes `lib/optimize/outcomes.sh` defines. Sudo-required tasks that the CLI
skips when admin access is unavailable surface as skips with reasons.

## Analyze data model

- `mo analyze --json [path]` → `AnalyzeReport` (`overview` distinguishes the
  machine-wide overview from a scoped directory scan; external volumes are
  only scanned when explicitly requested — same rule as the CLI).
- Entries become `AnalyzeNode`s; a pure-geometry **squarified treemap**
  (Bruls/Huizing/van Wijk) lays tiles by area share, unit-tested for bounds
  containment and area proportionality.
- Drill-down re-runs the analyzer on the child path; breadcrumbs are derived
  from the reported absolute path.
- Destructive action = "Move to Trash" through `NSWorkspace.recycle` with a
  confirmation sheet (recoverable — matches the CLI's Trash semantics). The
  app never performs its own recursive deletion.

## Permissions & privilege model

- The app process is unprivileged and never invokes sudo itself.
- Administrator authorization happens inside the CLI, exactly as in a
  terminal; the app honors the CLI's skip-with-reason outcomes when access is
  declined.
- Non-sandboxed (documented entitlement choice) so the CLI's helper processes
  behave as they do under a terminal. Credentials are never requested,
  transmitted, or stored by the GUI.

## Safety model

| Layer | Guarantee |
|---|---|
| CLI (`mo`) | path validation, shared/system protection, whitelists, Trash routing, operation log (`~/Library/Logs/mole/operations.log`) |
| App | dry-run before every destructive command, explicit confirmation sheets with full file lists, no arbitrary shell strings (only fixed argv per command), skip reasons surfaced verbatim |
| Tests | read-only commands only; no destructive CLI invocation in the suite |

## Error model

`SparkCleanUserError` carries title + what happened + recovery suggestion for: CLI
missing, CLI outdated, permission denied, scan failed, partial scan, invalid
path, volume disconnected, cancelled, partially completed, feature
unavailable, stale monitoring data. Errors render as banners, sheets, or
inline states depending on scope.
