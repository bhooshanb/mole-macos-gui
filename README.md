# Mole for Mac — native SwiftUI app for the Mole CLI

A native macOS application that turns the [Mole CLI](https://github.com/tw93/Mole) (`mo`)
into a premium Mac utility: **Clean**, **Apps**, **Optimize**, **Analyze**, and
**Status**, plus a live menu-bar mini monitor.

> The app is a presentation and control layer over the real `mo` binary.
> It never re-implements Mole's cleanup, uninstall, or maintenance logic — every
> destructive capability maps 1:1 to a Mole command (`mo clean`, `mo uninstall`,
> `mo optimize`, `mo analyze`, `mo status`, `mo history`).

## Highlights

- **Native**: Swift + SwiftUI on macOS 14+, AppKit integration where SwiftUI
  stops short (NSWorkspace, NSOpenPanel, menu bar extra). No Electron, no webviews.
- **Real CLI integration**: structured JSON/NDJSON surfaces are decoded with
  Codable (`mo status --json`, `mo status --watch`, `mo analyze --json`,
  `mo history --json`, `mo uninstall --list`); text-first commands are parsed
  from Mole's own output shapes (clean, uninstall plans, optimize outcomes).
- **Safety-first**: every destructive action starts as a dry run, shows Mole's
  own plan (paths, sizes, skip reasons), and requires explicit confirmation.
  Uninstalls route through the Trash; protected locations stay in Mole's own
  whitelist files (`~/.config/mole/whitelist*`).
- **Live monitoring**: one warm `mo status --watch` collector per app session,
  throttled UI updates, bounded rolling series, honest staleness handling
  (`process_stale`, `zombie_parents_complete` are surfaced as-is, never faked).
- **VoiceOver-ready**: labeled controls, logical reading order, keyboard
  navigation (⌘1–⌘5 sections, ⌘Y history, ⌘, settings), reduced-motion support,
  and no color-only information.
- **Menu bar mini monitor**: independent of the main window; health score, core
  metrics, top processes, Clean Watch summary, and On/Off · Wipe · Open Mole.

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6 toolchain (Xcode 16+, or CommandLineTools with `swift build`)
- The [Mole CLI](https://github.com/tw93/Mole) installed:
  `brew install mole` (or the install script). The app discovers `mo` at:
  1. Settings → Advanced → CLI path override
  2. `Mole.app/Contents/Resources/mole-cli/mole` (bundled copy, optional)
  3. `/usr/local/bin/mo`, `/opt/homebrew/bin/mo`, `~/.local/bin/mo`
  4. Repository checkouts (dev convenience)
  5. `PATH`

## Development

```bash
git clone <this-repo> && cd molemac
swift build                 # debug build
swift run &                 # run the app from the build dir
swift test                  # 25 unit tests + 6 live CLI integration tests
```

The integration tests call the real installed `mo` with **read-only** commands
only (`--version`, `uninstall --list`, `status --json`, `status --watch`,
`history --json`, `analyze --json` on a temp directory). No destructive command
is ever executed by the test suite.

## Build & package

```bash
./Scripts/make-app.sh               # → build/Mole.app (arm64, ad-hoc signed)
./Scripts/make-app.sh --universal   # → arm64 + x86_64 universal binary
```

The script generates `Resources/AppIcon.icns` from the vector Mole silhouette,
assembles the bundle from `Resources/Info.plist`, and ad-hoc signs it with
`Resources/Mole.entitlements` (non-sandboxed, like the CLI it drives — App
Sandbox would break the CLI's own helper processes).

### DMG

```bash
hdiutil create -volname Mole -srcfolder build/Mole.app -ov -format UDZO Mole.dmg
```

### Signing for distribution

Replace the ad-hoc identity with your Developer ID:

```bash
codesign --force --options runtime \
  --entitlements Resources/Mole.entitlements \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  build/Mole.app
```

Notarize with `notarytool submit`, then staple:

```bash
xcrun notarytool submit Mole.dmg --keychain-profile mole --wait
xcrun stapler staple Mole.dmg
```

### Bundling the CLI (optional)

To make the app self-contained, copy a full Mole CLI tree (the `mole`
entrypoint plus its `bin/` and `lib/` directories) to:

```
Mole.app/Contents/Resources/mole-cli/
```

The locator picks this up automatically. Note that `mo update` would update the
system install, not the bundle — prefer the system CLI for most users.

## Permissions

- The app runs **never as root**, matching Mole's own model.
- Administrator actions (some optimize tasks, system-owned cache cleaning) are
  requested by the CLI itself through its own sudo session; the app surfaces
  the resulting "skipped (admin access not granted)" outcomes instead of
  prompting for passwords itself. No credentials are ever requested, captured,
  or stored by the GUI.
- For Full-Disk-Access-protected paths, grant Mole (the app) Full Disk Access
  in System Settings → Privacy & Security.

## Project layout

```
Package.swift                     SwiftPM package (app + tests)
Sources/MoleApp/
  MoleApp.swift                   Entry point, menus, window scene
  MoleEngine/
    MoleLocator.swift              Executable discovery
    MoleClient.swift               Typed CLI API + whitelist access
    ProcessRunner.swift            Single process-execution layer
  Models/
    MoleModels.swift               Codable mirrors of Mole JSON outputs
    MoleJSONDecoder.swift          Tolerant decoder (Go time formats)
  Parsers/
    MoleOutputParsers.swift        clean / uninstall / optimize text parsers
  ViewModels/                      @MainActor state machines per section
  UI/                              SwiftUI views, design system, menu bar
  Configuration/MolePreferences.swift
  Support/MoleErrors.swift         What/why/next-step error model + logging
Resources/                         Info.plist, entitlements, generated icon
Scripts/                           build-app.sh, make-icon.swift, make-app.sh
Tests/MoleTests/                   Unit + live integration tests
mole-cli/                          upstream Mole clone (reference; not built here)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design document.

## License notes

This GUI is a presentation layer for the GPL-3.0 [Mole CLI](https://github.com/tw93/Mole).
Mole's name and branding belong to its author — see the upstream
[TRADEMARK.md](mole-cli/TRADEMARK.md). The vector mole artwork in this app is
original. If you fork this into another product, rename it and credit Mole,
per upstream guidance.
