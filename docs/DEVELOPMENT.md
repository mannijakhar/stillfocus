# Development guide

## Setup and build

Use macOS 14+ and Apple's Swift toolchain (Command Line Tools or Xcode). VS Code is sufficient as an editor.

```sh
xcode-select --install
chmod +x build.command package.command
./build.command
open "dist/Still Focus.app"
```

Do not rename `Source/main.swift`: it contains top-level startup code rather than an `@main` app. Do not add a second generated SwiftUI application entry point.

The builder produces arm64 and x86_64 executables, combines them, assembles the app from Resources, and applies an ad-hoc signature. `.build/` and `dist/` are generated and ignored. It does not modify the app installed in Applications or any saved history.

## Finding code

Search `Source/main.swift` for:

- `FocusSession`, `FocusSpan`, `FocusArchive`: persisted data.
- `FocusStore`: timer state, pause/resume, saving and reports.
- `FocusView`: main interface, presets and charts.
- `SessionEditor`: titles, labels and notes.
- `CompactFocusView`, `TimerMouseView`: floating bubble and drag interactions.
- `AppDelegate`: Dock/menu bar, native windows and application lifecycle.

The `FocusState` type alias distinguishes the State property wrapper from a newer toolchain macro with the same name. Keep it unless tested on your compiler.

## Safe editing workflow

Make one change, inspect the diff, build, quit the old app, and open `dist/Still Focus.app`. Keep source history in Git. Only replace the Applications copy after checking the result.

Avoid incompatible changes to Codable fields. Existing history uses the same application-support folder and bundle identifier across upgrades. Back up your own history before testing storage migrations; never commit the backup.

## Manual regression checklist

- Start a one-minute session; confirm the countdown and completion.
- Pause: bubble hides and elapsed time stops. Resume: bubble returns.
- Drag the bubble; open details; return to compact view.
- Hide without pausing; confirm time continues and it stays hidden across completion.
- Switch desktops/full-screen apps; bubble does not follow every Space.
- Amber button minimises; Dock restores. Red and Command-Q save and quit.
- Finish early; edit label/notes; quit and reopen; verify persistence.
- Check day/week charts and export timestamps. Test a midnight-spanning interval with disposable test data.
- Install the packaged app on another Mac, including Intel before claiming Intel runtime support.

## Known limitations

This is an early personal application, not a production-certified release. Prior timer/storage tests were run during development, but there is no checked-in automated test suite yet. Version 1.2 builds and passes signature checks; its latest native window button changes have not been visually regression-tested by the assistant. Universal packaging verifies both compiled slices, not successful runtime operation on both architectures.

The app is not notarized. It has no cloud sync, iOS target, automatic updater, or macOS Focus integration. Summary rollover depends on the app running. Records checkpoint about every five seconds. Do not market this as an objective measure of productivity.
