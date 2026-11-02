import AppKit
import SwiftUI
import XCTest
@testable import LFStudiosCore

/// The playhead (1.18.0): its whole handle shows at the top of the ruler,
/// with the line running into the tracks, at the smallest window and the
/// largest zoom, every track height, at the start, the middle and the end,
/// in both layouts and both looks (printed as PLAYHEAD: <path>).
@MainActor
final class VideoPlayheadSnapshotTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        VideoTestStorage.isolate()
    }

    private var directory: URL!
    private var window: NSWindow?

    override func setUp() async throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-playhead-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        VideoTimelineMetrics.rowScale = VideoTimelineTrackHeight.medium.scale
        VideoDemoDraftStore.delete(for: directory.appendingPathComponent("rec.mp4"))
        try? FileManager.default.removeItem(at: directory)
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-playhead", isDirectory: true)
    /// The timeline's toolbar and its line: where the ruler starts.
    private let rulerTop: CGFloat = 45

    private func render(_ model: VideoEditorModel, at time: Double, width: CGFloat, look: NSAppearance.Name, name: String) async throws -> NSBitmapImageRep {
        let size = CGSize(width: width, height: 300)
        let host = NSHostingView(rootView: VideoTimelineView(model: model).frame(width: size.width, height: size.height).environment(\.colorScheme, look == .darkAqua ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        window.orderFrontRegardless()
        self.window?.orderOut(nil)
        self.window = window
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        // The playhead goes there while the timeline shows (as when you
        // jump to a moment): it comes into view.
        model.seek(to: max(time - 0.5, 0))
        model.seek(to: time)
        try await Task.sleep(nanoseconds: 350_000_000)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let url = Self.folder.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("PLAYHEAD: \(url.path)")
        return rep
    }

    private func isPlayhead(_ color: NSColor?) -> Bool {
        guard let c = color?.usingColorSpace(.sRGB) else { return false }
        // Both layouts' reds (CapCut style's is pinker): clearly red.
        return c.redComponent > 0.72 && c.redComponent - c.greenComponent > 0.35 && c.redComponent - c.blueComponent > 0.28
    }

    /// Where the handle is (points), or nil: a column where the playhead's
    /// colour runs down the handle's whole height inside the ruler.
    private func handleColumn(_ rep: NSBitmapImageRep, width: CGFloat) -> CGFloat? {
        let k = CGFloat(rep.pixelsWide) / width
        let top = rulerTop + VideoPlayheadHandle.top
        for px in 0..<rep.pixelsWide {
            let x = CGFloat(px) / k
            let rows = stride(from: top + 1.5, through: top + VideoPlayheadHandle.size.height - 7, by: 1)
            if rows.allSatisfy({ isPlayhead(rep.colorAt(x: px, y: Int($0 * k))) }) {
                // The middle of the handle: a few points to the right.
                return x + VideoPlayheadHandle.size.width / 2 - 1.5
            }
        }
        return nil
    }

    func testTheWholeHandleShowsEverywhere() async throws {
        let url = directory.appendingPathComponent("rec.mp4")
        try await VideoInspection.writeColorVideo(to: url, size: CGSize(width: 320, height: 180), colors: [(.gray, 30)])
        VideoDemoDraftStore.delete(for: url)
        let model = VideoEditorModel(videoURL: url)
        await model.load()
        // The narrowest timeline: the smallest editor window.
        let widths: [(String, CGFloat)] = [("smallest", 1080), ("large", 1920)]
        try await forEachEditorStyle { style in
            for (lookName, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for (widthName, width) in widths {
                    for height in VideoTimelineTrackHeight.allCases {
                        VideoTimelineMetrics.rowScale = height.scale
                        for zoom in [1.0, model.maxTimelineZoom] {
                            model.timelineZoom = zoom
                            for time in [0.0, 15, model.timelineDuration] {
                                let name = "\(style.rawValue)-\(lookName)-\(widthName)-\(height.rawValue)-z\(Int(zoom))-t\(Int(time))"
                                let rep = try await render(model, at: time, width: width, look: look, name: name)
                                let column = try XCTUnwrap(handleColumn(rep, width: width), "\(name): the whole handle shows")
                                // The line runs on into the tracks under it.
                                let k = CGFloat(rep.pixelsWide) / width
                                let below = Int((rulerTop + VideoTimelineMetrics.rulerHeight + 12) * k)
                                let line = (-2...2).contains { dx in isPlayhead(rep.colorAt(x: Int((column + CGFloat(dx)) * k), y: below)) }
                                XCTAssertTrue(line, "\(name): the line goes on through the tracks")
                            }
                        }
                    }
                }
            }
        }
    }
}
