# Sharing and release checklist

## Keep the repository private

A private repository and its files/releases are only accessible to people with access. Sending a GitHub URL alone does not grant access. You can send just the app ZIP and install guide to a friend without giving them repository access.

Only invite named friends when you intend to give repository access. Personal-repository collaborator access includes write capabilities; do not add collaborators merely to distribute a binary if you prefer to keep the source private.

References: [GitHub repository access](https://docs.github.com/en/repositories/creating-and-managing-repositories/access-to-repositories) and [releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

## Produce a shareable ZIP

1. Run the manual checks in DEVELOPMENT.md.
2. Update the version and build number in `Resources/Info.plist` and the changelog.
3. Run `./package.command`.
4. Check the generated ZIP and checksum under `downloads/`.
5. Update README download links for the new version.
6. Commit source, documentation and the versioned download together.
7. Optionally create a private GitHub Release, tag the matching commit, and attach the ZIP plus checksum. The source archive GitHub generates automatically is not the ready-to-install app.

Never package `~/Library/Application Support/StillFocus`, exported personal CSVs, signing keys, build caches, or the entire original development workspace. App source and the ZIP have been assembled separately from personal data.

## Before wider distribution

Obtain an Apple Developer ID signing identity and use Apple's notarization process for a smoother, verifiable installation experience. Store signing credentials outside the repository. Choose a distribution licence explicitly before making the project public. This private project currently reserves rights rather than granting a general open-source licence.
