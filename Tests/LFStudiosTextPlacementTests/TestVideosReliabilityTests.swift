import AVFoundation
import Foundation
import Testing
@testable import LFStudiosCore

/// The test-video writer survives the failures that used to stop a test
/// at "Expectation failed: buffer".
@Suite("Test videos are written reliably", .serialized)
struct TestVideosReliabilityTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-testvideos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func frames(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]).load(.duration).seconds
    }

    @Test(arguments: [[TestVideos.InjectedFailure.pool], [.append], [.start], [.start, .append]])
    func aFailedWriteIsRetriedAndTheVideoIsComplete(failures: [TestVideos.InjectedFailure]) async throws {
        let url = try folder().appendingPathComponent("bars.mp4")
        TestVideos.inject(failures, into: url)
        try await TestVideos.writeBars(to: url, size: CGSize(width: 320, height: 180), seconds: 1)
        #expect(abs(try await frames(url) - 1) < 0.05, "a whole second of video after \(failures)")
    }

    @Test func aPoolThatCantGiveAFrameFallsBackWithoutARetry() async throws {
        // `.pool` on the only try: every frame is made directly.
        let url = try folder().appendingPathComponent("direct.mp4")
        TestVideos.inject([.pool], into: url)
        try await TestVideos.writeQuadrants(to: url, size: CGSize(width: 160, height: 120), seconds: 1)
        let frame = try await TestVideos.frame(ofMovie: url, at: 0.5)
        #expect(TestVideos.close(TestVideos.averageColor(of: frame, x: 0.1, y: 0.1), TestVideos.quadrantColors[0]), "the frames are drawn")
    }
}
