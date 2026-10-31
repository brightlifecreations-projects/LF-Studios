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
        _ = AppBundleStamp.atLaunch

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

    /// No check while LF Studios' files have been replaced since it opened:
    /// Sparkle couldn't start its installer. A daily check waits for the
    /// next launch; Check for Updates… asks to reopen (`checkForUpdates`).
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard AppBundleStamp.wasReplacedSinceLaunch else { return }
        throw NSError(domain: "com.lfstudios.app.update", code: 1, userInfo: [NSLocalizedDescriptionKey: AppBundleStamp.replacedMessage])
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
        if AppBundleStamp.wasReplacedSinceLaunch {
            let alert = NSAlert()
            alert.messageText = L("Reopen LF Studios to check for updates")
            alert.informativeText = AppBundleStamp.replacedMessage
            alert.addButton(withTitle: L("Reopen LF Studios"))
            alert.addButton(withTitle: L("Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { AppRelaunch.restart() }
            return
        }
        updater.checkForUpdates()
    }
}

/// LF Studios' program file as it was when it opened. Replaced since (a new
/// copy dragged over the running one, or a build installed over it), the
/// running app can't start Sparkle's installer ("An error occurred while
/// launching the installer") until it's reopened.
struct AppBundleStamp: Equatable {
    let fileNumber: UInt64
    let modified: Date?

    /// Read fresh from the disk each time (no cached file values).
    static func of(_ file: URL?) -> AppBundleStamp? {
        guard let path = file?.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let number = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return AppBundleStamp(fileNumber: number.uint64Value, modified: attributes[.modificationDate] as? Date)
    }

    static let atLaunch = of(Bundle.main.executableURL)

    static var wasReplacedSinceLaunch: Bool {
        guard let atLaunch else { return false }
        return of(Bundle.main.executableURL) != atLaunch
    }

    static var replacedMessage: String {
        L("LF Studios was replaced by another copy while it was open. Reopen it, then check again.")
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
