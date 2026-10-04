# Still Focus

A small native macOS focus timer built with SwiftUI and AppKit. Track focused time, label activities, add session notes, and review daily and weekly reports.

**Private project maintained by Manish Kumar.** This is a personal app, not an App Store release. Version 1.2 is an early build; see [known limitations](docs/DEVELOPMENT.md#known-limitations).

## Install without coding

Requires **macOS 14 or later**. The download contains both Apple silicon and Intel code.

1. Download [Still-Focus-1.2-macOS-universal.zip](downloads/Still-Focus-1.2-macOS-universal.zip) using GitHub's **Download raw file** button.
2. Double-click the ZIP to extract `Still Focus.app`.
3. Move the app to Applications, then open it.
4. Follow the [installation and troubleshooting guide](docs/INSTALL.md) if macOS blocks an unidentified developer.

This build is ad-hoc signed and **not Apple-notarized**. It may require manual approval to run. Intel code is compiled, but has not been tested on physical Intel hardware. App data is never included in the download.

## Features

- Custom sessions from 1–240 minutes, with 15/25/50-minute presets.
- Activity labels, session titles, notes, and editing after a session.
- Floating countdown bubble: drag to move, click for details, right-click for controls.
- Pause hides the timer; resume restores it. Hiding alone keeps the timer running.
- A menu bar countdown, Dock icon, and normal app window.
- Daily/weekly totals, time by activity, timestamped focus intervals, CSV export.
- Local history; no accounts, ads, analytics, or cloud sync.

See [the user guide](docs/USER-GUIDE.md) for controls and time-counting rules.

## Build it yourself

Install Apple's Command Line Tools with `xcode-select --install`. Download or clone this repository, then run:

```sh
chmod +x build.command package.command
./build.command
open "dist/Still Focus.app"
```

The scripts require macOS and compile using the installed Apple Swift toolchain. Xcode is optional. There are no third-party package dependencies. [Development guide](docs/DEVELOPMENT.md).

## Sharing with friends

You can send the app ZIP directly while keeping the repository private. A private GitHub link only works for people with repository access. See [sharing and releases](docs/SHARING.md). No friends have been invited automatically.

## Project map

| Path | Purpose |
|---|---|
| `Source/main.swift` | App models, timer, reports, interface and window controls |
| `Resources/` | Bundle metadata and original app icon |
| `build.command` | Build a fresh universal app in `dist/` |
| `package.command` | Build, package ZIP, and write a checksum |
| `downloads/` | Versioned installable ZIP and checksum |
| `docs/` | Installation, usage, development, privacy and sharing guides |

Personal history lives at `~/Library/Application Support/StillFocus/history.json`, outside the repository. Do not commit it or exported session CSVs.

[Privacy](docs/PRIVACY.md) · [Changelog](CHANGELOG.md) · [Permissions](LICENSE)
