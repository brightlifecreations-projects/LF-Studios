import AppKit

/// LF Studios was called ShotStyle (bundle ID com.shotstyle.app). On the
/// first launch, when LF Studios has no data of its own yet but ShotStyle's
/// is there, everything is copied over — never moved, so ShotStyle keeps
/// working until it's deleted:
///
/// - settings: the `com.shotstyle.app` UserDefaults domain (shortcuts,
///   appearance, recording options, save folder, file names, onboarding…)
/// - `~/Library/Application Support/ShotStyle/` → `…/LF Studios/`: capture
///   history, style presets, added fonts, recent projects, recordings' data
///   and drafts, camera footage, cleaned-up voice, copied pictures and music,
///   crash reports.
///
/// Paths inside the copied files that point into ShotStyle's folder are
/// rewritten to LF Studios', so nothing depends on the old folder.
enum ShotStyleMigration {
    static let legacyDomain = "com.shotstyle.app"
    static let legacyFolderName = "ShotStyle"
    static let folderName = "LF Studios"
    /// Set once the check has run (whatever it found).
    static let doneKey = "didCheckShotStyleData"
    /// Set when something came over, until the message has been shown.
    static let noticeKey = "showShotStyleMigrationNotice"

    /// Settings that belong to one run of the old app, not to the user.
    static let skippedKeys: Set<String> = ["crashReporterSession", doneKey, noticeKey]

    struct Result: Equatable {
        var settings: Int
        var copiedFolder: Bool
        var rewrittenFiles: Int
    }

    /// Runs the check once. Returns what was copied, or nil when nothing was
    /// (a fresh install, data already moved, or LF Studios already had its own).
    @discardableResult
    static func runIfNeeded(
        defaults: UserDefaults = Settings.defaults,
        legacySettings: [String: Any]? = UserDefaults.standard.persistentDomain(forName: legacyDomain),
        applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> Result? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        defer { defaults.set(true, forKey: doneKey) }

        let fileManager = FileManager.default
        let oldFolder = applicationSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
        let newFolder = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        let oldSettings = (legacySettings ?? [:]).filter { !skippedKeys.contains($0.key) }
        let hasOldFolder = fileManager.fileExists(atPath: oldFolder.path)
        guard hasOldFolder || !oldSettings.isEmpty else { return nil }

        // LF Studios already has data of its own: leave both alone.
        let newFolderHasData = ((try? fileManager.contentsOfDirectory(atPath: newFolder.path)) ?? []).contains { !$0.hasPrefix(".") }
        guard !newFolderHasData, !defaults.bool(forKey: "hasLaunchedBefore") else { return nil }

        var result = Result(settings: 0, copiedFolder: false, rewrittenFiles: 0)
        let rewrite = PathRewrite(from: oldFolder, to: newFolder)

        for (key, value) in oldSettings where defaults.object(forKey: key) == nil {
            defaults.set(rewrite.apply(to: value), forKey: key)
            result.settings += 1
        }

        if hasOldFolder {
            try? fileManager.removeItem(at: newFolder)
            do {
                // A clone on APFS: instant, and no extra space until changed.
                try fileManager.copyItem(at: oldFolder, to: newFolder)
                result.copiedFolder = true
                result.rewrittenFiles = rewrite.rewriteFiles(in: newFolder)
            } catch {
                NSLog("[LF Studios] Couldn't copy ShotStyle's data: \(error.localizedDescription)")
            }
        }

        guard result.settings > 0 || result.copiedFolder else { return nil }
        defaults.set(true, forKey: noticeKey)
        return result
    }

    /// The one-time message, once a window can show it.
    @MainActor
    static func showNoticeIfNeeded(defaults: UserDefaults = Settings.defaults) {
        guard defaults.bool(forKey: noticeKey) else { return }
        defaults.removeObject(forKey: noticeKey)
        let alert = NSAlert()
        alert.messageText = L("Your ShotStyle settings were moved to LF Studios")
        alert.informativeText = L("Your presets, fonts, capture history, and recording edits came along too. ShotStyle's own copy is untouched, so you can delete the old app whenever you're ready.")
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    /// Paths into ShotStyle's folder, pointed at LF Studios' instead — in
    /// settings values and in the copied files (JSON writes "/" as "\/").
    struct PathRewrite {
        let pairs: [(old: String, new: String)]

        init(from oldFolder: URL, to newFolder: URL) {
            let old = oldFolder.standardizedFileURL.path + "/"
            let new = newFolder.standardizedFileURL.path + "/"
            let escape = { (path: String) in path.replacingOccurrences(of: "/", with: "\\/") }
            pairs = [(old, new), (escape(old), escape(new))]
        }

        func apply(to value: Any) -> Any {
            switch value {
            case let text as String: return apply(to: text)
            case let list as [Any]: return list.map { apply(to: $0) }
            case let map as [String: Any]: return map.mapValues { apply(to: $0) }
            default: return value
            }
        }

        func apply(to text: String) -> String {
            pairs.reduce(text) { $0.replacingOccurrences(of: $1.old, with: $1.new) }
        }

        /// Rewrites the JSON files under `folder`; returns how many changed.
        func rewriteFiles(in folder: URL) -> Int {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
            var changed = 0
            for case let url as URL in walker where url.pathExtension.lowercased() == "json" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let updated = apply(to: text)
                if updated != text, (try? updated.write(to: url, atomically: true, encoding: .utf8)) != nil {
                    changed += 1
                }
            }
            return changed
        }
    }
}
