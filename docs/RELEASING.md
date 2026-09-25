# Releasing Depflush

This is for the maintainer who publishes official releases. You do not need any of it to use Depflush or to build it from source.

Every build uses the Hardened Runtime. Without a Developer ID certificate, `build.sh` signs ad-hoc, which is what the current releases are. Once an [Apple Developer Program](https://developer.apple.com/programs/) membership is active:

1. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com) so it is in your login keychain.
2. Store notarization credentials once, using an [app-specific password](https://account.apple.com):
   ```sh
   xcrun notarytool store-credentials depflush-notary \
     --apple-id you@example.com --team-id TEAMID1234 --password abcd-efgh-ijkl-mnop
   ```
3. `cp .signing.env.example .signing.env` and fill in the certificate name and profile (the file is git-ignored).
4. `./build.sh --release` signs with Developer ID, submits to Apple, staples the ticket and writes `dist/Depflush.zip`, ready to attach to a GitHub release.

## Publishing a release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` and add the changes to `CHANGELOG.md`.
2. Commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. `./build.sh --release` (or `./build.sh` while releases are still ad-hoc signed).
4. `gh release create vX.Y.Z dist/Depflush.zip -R cypriennkeneng/depflush --title "Depflush X.Y.Z" --notes "…"`

The website's download button points to `releases/latest/download/Depflush.zip`, so it serves the new version as soon as the release exists.

Forks: sign with your own Developer ID and use your own name, icon and bundle identifier (see "Name and logo" in the README).
