# ShotStyle (fork of Shotnix)

Native macOS app (Swift Package, macOS 13+) for screenshots, screen recording
and video editing, with a Home window and a menu-bar icon. Forked from https://github.com/OMARVII/Shotnix and
renamed to ShotStyle (bundle ID `com.shotstyle.app`).

## Git
- Repo: https://github.com/brightlifecreations-projects/ShotStyle (private).
- We work on `main`, the default branch (it used to be called `shotstyle`).
  Commit small changes straight to `main`; bigger ones go on a branch with a
  PR into `main`. Pull `main` before starting.
- GitHub CLI: `~/.local/bin/gh` (logged in as Prateek-BLC).

## Build and run
- Build + install: `bash build-app.sh` (release build, ad-hoc signed by default,
  copies the app to /Applications/ShotStyle.app).
- Run: `pkill ShotStyle; open /Applications/ShotStyle.app`
- See launch errors: `/Applications/ShotStyle.app/Contents/MacOS/ShotStyle`
- Universal (Apple Silicon + Intel): `bash build-app.sh --universal`;
  `--no-install` leaves the app in .build/app.noindex.
- Tests: `swift test` (about 20 minutes; needs full Xcode).
- The owner's Mac has full Xcode. With only the Command Line Tools,
  build-app.sh falls back to an installed macOS 26 SDK when the newest one
  needs Xcode's macro plugins, and otherwise says to install Xcode.

## Cloud sessions and Macs without Xcode
claude.ai/code sessions, and Macs without full Xcode, must not try to build
or test ShotStyle (`build-app.sh`, `swift build`, `swift test`): it can't work
there. Edit carefully instead, matching the surrounding code, then push a
branch and open a pull request into `main` describing what changed and what
to check. The owner builds, tests, merges, and publishes it.

## Publishing a new version
Run `bash scripts/publish-release.sh <version>` on main with everything
committed and pushed. CHANGELOG.md must have a `## [<version>]` section first.
The script sets the version in Info.plist, dates the CHANGELOG section,
commits and pushes, builds the universal app, zips it, and creates the
GitHub Release with ShotStyle.zip, the install steps, and that CHANGELOG
section. It builds on this Mac, so it uses no GitHub Actions minutes.

## GitHub Actions
macOS runners cost Mac minutes. CI (`trusty-1-0.yml`) runs only on pull
requests and by hand; the Release app workflow runs only by hand. Don't add
push or tag triggers back.

## Local-build gotchas (already fixed, keep them fixed)
- `#Preview` macros don't compile without full Xcode. The three `#Preview` blocks
  in Vendor/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift were removed.
  Never add `#Preview` blocks.
- Ad-hoc signing + hardened runtime makes the app crash at launch ("different
  Team IDs" loading Sparkle). build-app.sh re-signs Sparkle ad-hoc and skips
  `--options runtime` when the identity is "-". Don't undo this.
- Builds are signed with the self-signed "ShotStyle Local Signing" certificate
  in the login keychain (build-app.sh picks it up automatically), so Screen
  Recording/Accessibility permissions survive rebuilds. Without it the build is
  ad-hoc and macOS forgets the permissions on every rebuild; fix stale entries
  with `tccutil reset ScreenCapture com.shotstyle.app` (and Accessibility).

## Conventions
- User-visible strings go through `L("…")`; English strings are the keys.
  Translations: Localization/ and Sources/ShotStyleCore/Resources/*.lproj
  (see scripts/localize.py). Update all 7 languages when adding text.
- Never use `Bundle.module`; use `ShotStyleResources`.
- ShotStyle's home is https://github.com/brightlifecreations-projects/ShotStyle (About, issues,
  crash reports, update feed). Don't link shotnix.com. The only upstream
  references kept are the MIT attribution: "Based on Shotnix (MIT License)"
  linking to https://github.com/OMARVII/Shotnix, the "© Shotnix Contributors"
  notice in About, and the copyright line in LICENSE.
- ShotStyle is a regular windowed app (Dock icon, ⌘-Tab, Home window in
  App/HomeWindowController.swift). Don't bring back LSUIElement or the
  .accessory/.prohibited activation policies. Capture overlays call
  `NSApp.ensureForegroundCapable(forCapture: true)` so Home steps aside.
- App icon: Branding/ShotStyle_Icon.png (1024×1024, macOS-style padding).
  build-app.sh turns it into Branding/ShotStyle.icns (gitignored).
- scripts/localize.py needs Xcode's xcstringstool to compile the catalog.
  Without it, update Localizable.xcstrings and the compiled
  Resources/*.lproj/Localizable.strings plists directly.
- Commit each change with a clear message (see Git above).
