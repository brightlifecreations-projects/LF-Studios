import Darwin
import XCTest
@testable import LFStudiosCore

/// The fake recordings tests write must not leak: in Nov 2026 a retry loop
/// asked the pixel-buffer pool for 500 buffers a frame and leaked 499 of
/// them (5 MB each at 1440×900), which swapped the Mac into a WindowServer
/// panic.
final class TestMediaMemoryTests: XCTestCase {
    /// This process's footprint (what Activity Monitor shows), in MB.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    func testWritingAFakeRecordingDoesNotLeakFrames() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfstudios-leak-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let before = Self.footprintMB()
        // Small on purpose, so the old leak can't hurt the Mac: 10 frames at
        // 160×100 leaked ~320 MB (499 × 64 KB a frame); fixed, it's ~0.
        try await VideoTestSupport.writeFakeRecording(to: url, size: CGSize(width: 160, height: 100), seconds: 2, fps: 5)
        let grew = Self.footprintMB() - before
        XCTAssertLessThan(grew, 100, "writing 10 small frames grew the process by \(Int(grew)) MB")
    }
}
