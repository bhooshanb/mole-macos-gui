# SparkClean for Mac — native SwiftUI utility for macOS

A native macOS application that turns the `mo` command-line utility
into a premium Mac utility, branded **SparkClean**: **Clean**, **Apps**, **Optimize**, **Analyze**, and
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
  from the CLI's own output shapes (clean, uninstall plans, optimize outcomes).
- **Safety-first**: every destructive action starts as a dry run, shows the CLI's
  plan (paths, sizes, skip reasons), and requires explicit confirmation.
  Uninstalls route through the Trash; protected locations stay in the CLI's own
  whitelist files (`~/.config/mole/whitelist*`).
- **Live monitoring**: one warm `mo status --watch` collector per app session,
  throttled UI updates, bounded rolling series, honest staleness handling
  (`process_stale`, `zombie_parents_complete` are surfaced as-is, never faked).
- **VoiceOver-ready**: labeled controls, logical reading order, keyboard
  navigation (⌘1–⌘5 sections, ⌘Y history, ⌘, settings), reduced-motion support,
  and no color-only information.
- **Menu bar mini monitor**: independent of the main window; health score, core
  metrics, top processes, Clean Watch summary, and On/Off · Wipe · Open.

## Requirements

- macOS 14 (Sonoma) or newer
- Swift 6 toolchain (Xcode 16+, or CommandLineTools with `swift build`)
- The compatible command-line utility installed via Homebrew:
  `brew install mole` (or the official install script). The app does **not**
  bundle the CLI; it relies on the installed one and discovers `mo` at:
  1. Settings → Advanced → CLI path override
  2. `/usr/local/bin/mo`, `/opt/homebrew/bin/mo`, `~/.local/bin/mo`
  3. Repository checkouts (dev convenience)
  4. `PATH`

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
./Scripts/make-app.sh               # → build/SparkClean.app (arm64, ad-hoc signed)
./Scripts/make-app.sh --universal   # → arm64 + x86_64 universal binary
```

The script generates `Resources/AppIcon.icns` from the vector SparkClean
sparkle mark, assembles the bundle from `Resources/Info.plist`, and ad-hoc
signs it with `Resources/SparkClean.entitlements` (non-sandboxed, like the CLI
it drives — App Sandbox would break the CLI's own helper processes).

### DMG

```bash
hdiutil create -volname SparkClean -srcfolder build/SparkClean.app -ov -format UDZO SparkClean.dmg
```

### Signing for distribution

Replace the ad-hoc identity with your Developer ID:

```bash
codesign --force --options runtime \
  --entitlements Resources/SparkClean.entitlements \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  build/SparkClean.app
```

Notarize with `notarytool submit`, then staple:

```bash
xcrun notarytool submit SparkClean.dmg --keychain-profile mole --wait
xcrun stapler staple SparkClean.dmg
```

## Permissions

- The app runs **never as root**, matching the CLI's own model.
- Administrator actions (some optimize tasks, system-owned cache cleaning) are
  requested by the CLI itself through its own sudo session; the app surfaces
  the resulting "skipped (admin access not granted)" outcomes instead of
  prompting for passwords itself. No credentials are ever requested, captured,
  or stored by the GUI.
- For Full-Disk-Access-protected paths, grant SparkClean (the app) Full Disk
  Access in System Settings → Privacy & Security.

## Project layout

```
Package.swift                     SwiftPM package (app + tests)
Sources/SparkCleanApp/
  SparkCleanApp.swift              Entry point, menus, window scene
  SparkCleanEngine/
    SparkCleanLocator.swift        Executable discovery
    SparkCleanClient.swift         Typed CLI API + whitelist access
    ProcessRunner.swift            Single process-execution layer
  Models/
    SparkCleanModels.swift         Codable mirrors of CLI JSON outputs
    SparkCleanJSONDecoder.swift    Tolerant decoder (Go time formats)
  Parsers/
    SparkCleanOutputParsers.swift  clean / uninstall / optimize text parsers
  ViewModels/                      @MainActor state machines per section
  UI/                              SwiftUI views, design system, menu bar
  Configuration/SparkCleanPreferences.swift
  Support/SparkCleanErrors.swift   What/why/next-step error model + logging
Resources/                         Info.plist, entitlements, generated icon
Scripts/                           build-app.sh, make-icon.swift, make-app.sh
Tests/SparkCleanTests/             Unit + live integration tests
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design document.

## License notes

SparkClean is distributed under GNU GPL-3.0. The complete license is in `LICENSE`; copyright and third-party notices are in `COPYRIGHT` and `Resources/THIRD_PARTY_NOTICES.txt`. The build copies these notices into `SparkClean.app/Contents/Resources/`. The app settings also link to the license and corresponding source repository. Keep the published source in sync with every distributed build. Clean and Optimize operations do not require purchase or activation; paid activation remains optional and does not restrict GPL-covered use.

The app is a presentation layer for a separately installed GPL-3.0 command-line utility. Its source, license, and trademark notices are available in the [upstream source repository](https://github.com/tw93/Mole) and its [trademark policy](https://github.com/tw93/Mole/blob/main/TRADEMARK.md). SparkClean uses its own name and original sparkle artwork.
