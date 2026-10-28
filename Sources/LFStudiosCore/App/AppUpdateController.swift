import AppKit
import Sparkle

@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    /// Where "Check for Updates" goes while Sparkle isn't set up.
    static let releasesURL = URL(string: "https://github.com/brightlifecreations-projects/LF-Studios-Releases/releases")!
    /// The one the app runs (Settings reads and sets automatic checks).
    private(set) static var shared: AppUpdateController?
    private var updater: SPUUpdater?
    private var userDriver: OneClickUserDriver?

    override init() {
        super.init()
        Self.shared = self

        guard AppUpdateConfiguration.current != nil else {
            print("[LF Studios] Sparkle updates are disabled because SUPublicEDKey is not configured.")
            return
        }

        let driver = OneClickUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
        } catch {
            print("[LF Studios] Sparkle couldn't start: \(error.localizedDescription)")
            return
        }
        // Never download or install in the background, whatever an older
        // build left in the defaults.
        updater.automaticallyDownloadsUpdates = false
        self.updater = updater
        userDriver = driver
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
        updater?.canCheckForUpdates ?? true
    }

    /// Settings → General ▸ Check for updates automatically: once a day.
    /// A check only shows the update window; nothing installs until the
    /// user clicks Install Update.
    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var isConfigured: Bool { updater != nil }

    func checkForUpdates(_ sender: Any?) {
        guard let updater else {
            NSWorkspace.shared.open(Self.releasesURL)
            return
        }
        updater.checkForUpdates()
    }
}

/// Sparkle's own update window, minus its second question: after Install
/// Update it would download and then ask again (Install and Relaunch). Once
/// the user has clicked Install Update, the update installs and LF Studios
/// relaunches. An update Sparkle prepared some other way still asks.
@MainActor
final class OneClickUserDriver: SPUStandardUserDriver {
    private var installChosen = false

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            self?.installChosen = choice == .install
            reply(choice)
        }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard installChosen else { return super.showReady(toInstallAndRelaunch: reply) }
        installChosen = false
        reply(.install)
    }

    override func dismissUpdateInstallation() {
        installChosen = false
        super.dismissUpdateInstallation()
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
