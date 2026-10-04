# Install Still Focus on a Mac

## Requirements

- macOS 14 or later.
- An Apple silicon or Intel Mac. The ZIP is universal; physical Intel testing is still pending.
- No Python, Xcode, or developer account is needed to use the downloaded app.

## Install

1. Download the versioned ZIP from the repository's `downloads` folder using **Download raw file**, or receive it directly from the owner. GitHub's **Code → Download ZIP** downloads the source project instead.
2. Double-click the ZIP in Finder.
3. Move **Still Focus.app** to **Applications**. Your personal `~/Applications` folder also works.
4. Open the application. It should show a Dock icon, menu bar timer icon, and main window.
5. Spotlight should discover the installed app after indexing. Until then, open it in Finder.

## If macOS cannot verify the developer

This personal build is ad-hoc signed, not notarized by Apple. Only proceed if you trust the source and intended to install this exact app. After attempting to open it, macOS may offer **System Settings → Privacy & Security → Open Anyway**. Review the alert before choosing to continue.

Follow [Apple's current guidance](https://support.apple.com/en-ie/102445). Do not disable Gatekeeper globally or remove security protections using terminal commands. A malware or damaged-app alert should be investigated, not bypassed.

## Update

Quit the running app with **Command-Q** before replacing it. Extract the new ZIP and replace the old `.app` in Applications. Replacing the app does not remove your history. Open the installed copy after updating; copies in Downloads or a source folder can be different versions.

## Optional integrity check

Download `SHA256SUMS.txt` into the same folder as the ZIP, open Terminal there, and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

This checks that the ZIP matches the supplied checksum; it does not prove publisher identity or replace Apple's security checks.

## Troubleshooting

- **No window:** click the menu bar timer → Show Still Focus, or click its Dock icon.
- **Bubble hidden after Pause:** select Start / Pause in the menu bar to resume.
- **Old behaviour after an update:** quit all old copies and open the app in Applications.
- **Red/amber buttons:** red is intended to save and quit; amber minimises the main window. Version 1.2 replaced the changing-window design with separate native windows. A final on-device regression check is still pending.
- **App will not open:** record the exact macOS message, version, and Mac chip type. Share these with the owner; do not include private session history by default.

## Uninstall

Quit and move Still Focus.app to the Trash. History remains at `~/Library/Application Support/StillFocus/`. Back it up before deleting it if you also want to remove your personal data.
