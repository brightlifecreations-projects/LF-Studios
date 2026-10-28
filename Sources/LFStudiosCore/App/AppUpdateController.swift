import AppKit
import Sparkle

@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    /// Where "Check for Updates" goes while Sparkle isn't set up.
    static let releasesURL = URL(string: "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases")!
    /// The one the app runs (Settings reads and sets automatic checks).
    private(set) static var shared: AppUpdateController?
    private var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
        Self.shared = self

        guard AppUpdateConfiguration.current != nil else {
            print("[LF Studios] Sparkle updates are disabled because SUPublicEDKey is not configured.")
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // Never download or install in the background, whatever an older
        // build left in the defaults.
        updaterController?.updater.automaticallyDownloadsUpdates = false
    }

    /// An update never relaunches the app in the middle of a recording or an
    /// export: it installs once they have ended.
    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard AppTermination.isBusy else { return false }
            AppTermination.whenIdle { installHandler() }
            return true
        }
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? true
    }

    /// Settings → General ▸ Check for updates automatically: once a day.
    /// A check only shows the update window; nothing installs until the
    /// user clicks Install Update.
    var automaticallyChecks: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    var isConfigured: Bool { updaterController != nil }

    func checkForUpdates(_ sender: Any?) {
        guard let updaterController else {
            NSWorkspace.shared.open(Self.releasesURL)
            return
        }
        updaterController.checkForUpdates(sender)
    }
}

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    static var current: AppUpdateConfiguration? {
        AppUpdateConfiguration(
            feedURLString: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicEDKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
    }

    init?(feedURLString: String?, publicEDKey: String?) {
        guard let feedURLString,
              let feedURL = URL(string: feedURLString),
              let publicEDKey,
              !publicEDKey.isEmpty,
              !publicEDKey.contains("SET_SPARKLE_PUBLIC_ED_KEY") else {
            return nil
        }

        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }
}
