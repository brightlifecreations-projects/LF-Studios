# Contributing to LF Studios

Thanks for your interest in contributing! Here's how to get started.

## Process

1. **Open an issue first** to discuss what you'd like to change
2. Fork the repo and create a branch from `main`
3. Make your changes
4. Test manually (build and run the app)
5. Submit a pull request

## Development Setup

```bash
git clone https://github.com/brightlifecreations-projects/LF-Studios.git
cd LF Studios
bash scripts/setup-signing.sh   # once per Mac: a local signing certificate
swift build                     # Debug build
bash build-app.sh               # Full .app bundle (release + icon + codesign)
bash scripts/test-quick.sh      # Tests while working, in parallel (needs full Xcode)
bash scripts/test-full.sh       # Every test, screenshots included: once before a release
```

**Requirements:** macOS 13+, Swift 5.9+. Full Xcode to run the tests.

**Run `scripts/setup-signing.sh` once on each Mac.** It creates a self-signed "ShotStyle Local Signing" certificate in your login keychain, and `build-app.sh` signs with it, so macOS keeps the Screen Recording and Accessibility permissions across rebuilds. Without it, every rebuild is signed ad-hoc, macOS treats it as a new app, and recording is blocked until you grant the permissions again. If LF Studios keeps asking, run `tccutil reset ScreenCapture com.lfstudios.app` and `tccutil reset Accessibility com.lfstudios.app`, then grant them once more. Never commit or share the certificate: everyone makes their own.

No Xcode project — everything builds from the terminal via Swift Package Manager.

## Code Style

- All UI code is `@MainActor`
- AppKit for capture/editor surfaces; SwiftUI is used for preferences panels
- No force unwraps (`!`) without a documented reason
- No `// TODO` or `// HACK` — fix it or file an issue
- Match existing patterns in the file you're editing

## What We're Looking For

Check the [Roadmap](ROADMAP.md) for planned features. Bug fixes, performance improvements, and accessibility enhancements are always welcome.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
