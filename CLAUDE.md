# LF Studios (fork of Shotnix)

Native macOS app (Swift Package, macOS 13+) for screenshots, screen recording
and video editing, with a Home window and a menu-bar icon. Forked from https://github.com/OMARVII/Shotnix and
renamed to LF Studios (bundle ID `com.lfstudios.app`). It was called ShotStyle
(`com.shotstyle.app`) until 1.1.0; App/ShotStyleMigration.swift copies a
ShotStyle user's settings and data over on first launch, and old `.shotstyle`
projects and `.shotstylepresets` files still open. Keep those, the
`com.shotstyle.recording-id` file attribute, and the "ShotStyle " recording
name prefix: existing users' files depend on them.

## Git
- Repo: https://github.com/brightlifecreations-projects/LF-Studios (private).
- We work on `main`, the default branch (it used to be called `shotstyle`).
  Commit small changes straight to `main`; bigger ones go on a branch with a
  PR into `main`. Pull `main` before starting.
- GitHub CLI: `~/.local/bin/gh` (logged in as Prateek-BLC).

## Build and run
- Build + install: `bash build-app.sh` (release build, ad-hoc signed by default,
  copies the app to /Applications/LF Studios.app).
- Run: `pkill LFStudios; open "/Applications/LF Studios.app"`
- See launch errors: `"/Applications/LF Studios.app/Contents/MacOS/LFStudios"`
- Universal (Apple Silicon + Intel): `bash build-app.sh --universal`;
  `--no-install` leaves the app in .build/app.noindex.
- Tests (need full Xcode):
  - While working: `bash scripts/test-quick.sh`, every test except the slow
    screenshot tests, in parallel (a couple of minutes). For one area,
    `swift test --filter <Class>`.
  - Before publishing a release, once: `bash scripts/test-full.sh`, every
    test, screenshot tests included.
  - Screenshot tests live in Tests/LFStudiosCoreTests/Snapshots/, and each
    class there ends in `SnapshotTests`. Tests that can't share the Mac
    (screen recording, clipboard, shared settings, speed limits) run one
    after another; the list and the reasons are in scripts/test-groups.sh.
    A new test that needs either belongs there.
- The owner's Mac has full Xcode. With only the Command Line Tools,
  build-app.sh falls back to an installed macOS 26 SDK when the newest one
  needs Xcode's macro plugins, and otherwise says to install Xcode.

## Cloud sessions and Macs without Xcode
claude.ai/code sessions, and Macs without full Xcode, must not try to build
or test LF Studios (`build-app.sh`, `swift build`, `swift test`): it can't work
there. Edit carefully instead, matching the surrounding code, then push a
branch and open a pull request into `main` describing what changed and what
to check. The owner builds, tests, merges, and publishes it.

## Publishing a new version
Always publish from the owner's Mac. Only it has the "ShotStyle Local
Signing" certificate (the same signature on every version is what keeps
users' Screen Recording and Accessibility permissions across updates) and
the Sparkle update key (installed apps accept only updates signed with it).
Never publish from a cloud session, CI, or another Mac without restoring
both first.

First run `bash scripts/test-full.sh` once; it must pass. Then run
`bash scripts/publish-release.sh <version>` on main with everything
committed and pushed. CHANGELOG.md must have a `## [<version>]` section first.
The script sets the version in Info.plist, dates the CHANGELOG section,
commits and pushes, builds the universal app, zips it, signs the zip with
the update key, writes the update feed (appcast.xml, via generate-appcast.sh;
the update window shows that CHANGELOG section), and creates the GitHub
Releases. It builds on this Mac, so it uses no GitHub Actions minutes.

Updates (Sparkle):
- The source repo is private, so downloads and the feed live in the public
  https://github.com/brightlifecreations-projects/LF-Studios-Releases (releases
  only, no code). SUFeedURL reads appcast.xml from its latest release. The
  same release also goes on this repo, for the record.
- The update key: the public half is `LFSTUDIOS_SPARKLE_PUBLIC_ED_KEY` in
  .env.local (not committed; build-app.sh puts it in Info.plist); the
  private half is in this Mac's login Keychain (service
  "https://sparkle-project.org", account ed25519) and never goes in the repo.
  publish-release.sh refuses to publish if either is missing or they don't
  match.
- Restore on another Mac: import the backup the owner keeps in their
  password manager with
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys -f <file>` (run
  `swift build` once first so the tool exists), delete the file, check that
  `generate_keys -p` prints the same public key, and put that key in
  .env.local. Also move the signing certificate over (Keychain Access →
  export "ShotStyle Local Signing" with its private key as .p12, import it
  on the new Mac). A new certificate would make every user grant the
  permissions again; a new update key would mean every user has to
  reinstall by hand.
- Updates never install on their own: the app checks once a day (Settings →
  General ▸ Check for updates automatically) or on LF Studios → Check for
  Updates…, and installs only when the user clicks Install Update. Keep
  SUAutomaticallyUpdate and SUAllowsAutomaticUpdates off in Info.plist.
- 1.4.1 is the first version that updates itself; older ones must be
  installed by hand once.

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
  with `tccutil reset ScreenCapture com.lfstudios.app` (and Accessibility).

## Still to check (not for the CHANGELOG or release notes)
- Keep face centered (1.4.0) has been tested with made-up face positions only.
  The real check, `ReleaseChecksCameraAudioTests.testFaceTrackingOnARealCameraVideo`,
  runs once the owner has saved a 10–15 s video of themselves moving their
  head as ~/Desktop/face-test.mov (it skips until then). It works on a copy
  and deletes the copy afterwards.

## Conventions
- Manual only: every creative effect starts OFF and is turned on by the user
  with its own button or switch. Nothing is applied to a video automatically.
  Exceptions that stay automatic because they protect the user's work: crash
  recovery, saving edits as you go (drafts), moving settings after a rename,
  replacing a microphone that drops out mid-recording, and permission checks.
  New recordings open with `VideoDemoProject.fresh` (Video/VideoManualOnly.swift);
  don't change the settings types' built-in values, which older drafts and
  project files fall back on.
- User-visible strings go through `L("…")`; English strings are the keys.
  Translations: Localization/ and Sources/LFStudiosCore/Resources/*.lproj
  (see scripts/localize.py). Update all 7 languages when adding text.
- Never use `Bundle.module`; use `LFStudiosResources`.
- Every new or changed user-facing feature must add or update its Guide
  entry in the same commit. The Guide (Home ▸ Guide, Help ▸ LF Studios
  Guide ⌘?) is written for brand-new users: plain words, short steps, the
  app's exact button names. All of its content is in
  App/GuideContent.swift: a feature page needs a name, what it does, where
  to find it, and, where it helps, steps, keys, tips, "Show me" (only
  navigates, never turns anything on), and `since:` its version. When
  publishing, put the new version first in `GuideContent.newVersions` so
  its pages get the New badge and fill What's new. A new global shortcut,
  menu shortcut, or editor key also goes on the Keyboard shortcuts page
  (GuideTests checks).
- LF Studios' home is https://github.com/brightlifecreations-projects/LF-Studios (About, issues,
  crash reports); downloads and the update feed are on LF-Studios-Releases. Don't link shotnix.com. The only upstream
  references kept are the MIT attribution: "Based on Shotnix (MIT License)"
  linking to https://github.com/OMARVII/Shotnix, the "© Shotnix Contributors"
  notice in About, and the copyright line in LICENSE.
- LF Studios is a regular windowed app (Dock icon, ⌘-Tab, Home window in
  App/HomeWindowController.swift). Don't bring back LSUIElement or the
  .accessory/.prohibited activation policies. Capture overlays call
  `NSApp.ensureForegroundCapable(forCapture: true)` so Home steps aside.
- App icon: Branding/LFStudios_Icon.png (1024×1024, macOS-style padding).
  build-app.sh turns it into Branding/LFStudios.icns (gitignored).
- scripts/localize.py needs Xcode's xcstringstool to compile the catalog.
  Without it, update Localizable.xcstrings and the compiled
  Resources/*.lproj/Localizable.strings plists directly.
- Commit each change with a clear message (see Git above).
