import AppKit
import AVFoundation
import SwiftUI

/// A marker: a moment flagged while recording (the bar's flag or its
/// shortcut) or in the editor. Kept in recorded time, so it stays on its
/// moment through cuts, speed changes and moves; a marker inside a cut
/// part hides. Markers become chapters (MP4, ProRes, YouTube) and show up
/// in Creative Handoff's timelines.
struct VideoMarker: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Source seconds.
    var time: Double
    /// nil: "Marker 3", by its place in time.
    var name: String?
}

/// A marker where it falls in the edit.
struct VideoPlacedMarker: Equatable, Identifiable {
    let marker: VideoMarker
    /// Timeline seconds.
    let time: Double
    /// Its name, or "Marker 3".
    let title: String

    var id: UUID { marker.id }
}

/// A chapter of the finished video.
struct VideoChapter: Equatable {
    let start: Double
    let title: String
}

extension VideoDemoProject {
    /// The markers in the edit, in time order (cut ones left out).
    func placedMarkers(segments: [VideoDemoTimelineSegment]) -> [VideoPlacedMarker] {
        markers.sorted { $0.time < $1.time }.enumerated().compactMap { index, marker in
            guard let time = VideoDemoProject.timelineTimeIfIncluded(sourceTime: marker.time, segments: segments) else { return nil }
            return VideoPlacedMarker(marker: marker, time: time, title: Self.title(of: marker, number: index + 1))
        }
    }

    static func title(of marker: VideoMarker, number: Int) -> String {
        let name = marker.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L("Marker \(number)") : name
    }

    /// Chapters for a video of `duration`: one per marker, and a first one
    /// ("Start") from 0:00 when no marker is right at the beginning.
    func chapters(segments: [VideoDemoTimelineSegment], duration: Double) -> [VideoChapter] {
        Self.chapters(from: placedMarkers(segments: segments), duration: duration)
    }

    static func chapters(from markers: [VideoPlacedMarker], duration: Double) -> [VideoChapter] {
        var chapters: [VideoChapter] = []
        for marker in markers where marker.time < duration - 0.05 {
            // Two markers at (nearly) the same moment make one chapter.
            if let last = chapters.last, marker.time - last.start < 0.1 { continue }
            let start = marker.time < 0.5 && chapters.isEmpty ? 0 : marker.time
            chapters.append(VideoChapter(start: start, title: marker.title))
        }
        guard !chapters.isEmpty else { return [] }
        if chapters[0].start > 0 {
            chapters.insert(VideoChapter(start: 0, title: L("Start")), at: 0)
        }
        return chapters
    }

    /// Splits the clips at every marker that isn't already at an edge.
    /// Returns how many splits it made.
    @discardableResult
    mutating func splitAtMarkers(totalDuration: Double) -> Int {
        var splits = 0
        for marker in markers.sorted(by: { $0.time < $1.time }) {
            if splitClip(atSourceTime: marker.time, totalDuration: totalDuration) != nil { splits += 1 }
        }
        return splits
    }
}

/// Chapters as text for a video description ("0:00 Start"): YouTube makes
/// chapters from it when there are 3 or more, the first at 0:00, each at
/// least 10 seconds long.
enum VideoChapterText {
    static let minimumCount = 3
    static let minimumLength = 10.0

    static func text(_ chapters: [VideoChapter], duration: Double) -> String {
        let hours = duration >= 3600
        return chapters.map { "\(timestamp($0.start, hours: hours)) \($0.title)" }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: Double, hours: Bool) -> String {
        let whole = Int(max(seconds, 0))
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        return hours ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m + h * 60, s)
    }

    /// What keeps YouTube from making chapters of it (nil: nothing).
    static func problem(_ chapters: [VideoChapter], duration: Double) -> String? {
        if chapters.count < minimumCount {
            return L("YouTube shows chapters from 3 on — add a marker or two more.")
        }
        let ends = chapters.dropFirst().map(\.start) + [duration]
        if zip(chapters, ends).contains(where: { $1 - $0.start < minimumLength }) {
            return L("YouTube needs every chapter to be at least 10 seconds long — move or remove markers that are closer together.")
        }
        return nil
    }
}

// MARK: - Editing

extension VideoEditorModel {
    var placedMarkers: [VideoPlacedMarker] { project.placedMarkers(segments: segments) }

    var chapters: [VideoChapter] { project.chapters(segments: segments, duration: timelineDuration) }

    /// A marker at the playhead.
    @discardableResult
    func addMarker() -> UUID? {
        let time = clock.time
        guard let segment = segment(atTimeline: time) else { return nil }
        let marker = VideoMarker(time: segment.sourceTime(forTimelineTime: time))
        mutate(label: "Add Marker") { $0.markers.append(marker) }
        return marker.id
    }

    func renameMarker(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = project.markers.firstIndex(where: { $0.id == id }), (project.markers[index].name ?? "") != trimmed else { return }
        mutate(label: "Rename Marker") { $0.markers[index].name = trimmed.isEmpty ? nil : trimmed }
    }

    func deleteMarker(_ id: UUID) {
        guard project.markers.contains(where: { $0.id == id }) else { return }
        mutate(label: "Delete Marker") { $0.markers.removeAll { $0.id == id } }
    }

    func jump(to marker: VideoPlacedMarker) {
        seek(to: marker.time)
    }

    /// Splits the clips at every marker, as one ⌘Z step.
    func splitAtMarkers() {
        guard !placedMarkers.isEmpty else { return }
        var splits = 0
        let total = sourceDuration
        mutate(label: "Split at Markers") { splits = $0.splitAtMarkers(totalDuration: total) }
        showNotice(splits == 0 ? L("The markers are already at clip edges") : L("Split at \(splits) markers"), symbol: "scissors")
    }

    /// The chapters as text for a YouTube description, on the clipboard.
    func copyChapters() {
        let chapters = self.chapters
        guard !chapters.isEmpty else {
            showNotice(L("Add markers first — each one starts a chapter"), symbol: "flag")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(VideoChapterText.text(chapters, duration: timelineDuration), forType: .string)
        showNotice(L("Chapters copied — paste them into the video's description"), symbol: "doc.on.clipboard")
    }
}

// MARK: - Timeline flags

/// The markers as flags along the ruler: click to jump there, double-click
/// to rename, right-click to rename or delete.
struct VideoMarkerFlags: View {
    @ObservedObject var model: VideoEditorModel
    let geometry: VideoTimelineGeometry
    let height: CGFloat

    @State private var renaming: UUID?
    @State private var draft = ""

    /// Dark text reads on it in both looks.
    static let color = Color(nsColor: .systemYellow)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.placedMarkers) { marker in
                flag(marker)
                    .offset(x: geometry.x(marker.time) - 1)
            }
        }
        .frame(width: geometry.width, height: height, alignment: .topLeading)
    }

    private func flag(_ marker: VideoPlacedMarker) -> some View {
        HStack(alignment: .top, spacing: 2) {
            Rectangle()
                .fill(Self.color)
                .frame(width: 2, height: height)
            Text(marker.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Self.color))
                .frame(maxWidth: 120, alignment: .leading)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded { startRenaming(marker) }
                .exclusively(before: TapGesture().onEnded { model.jump(to: marker) })
        )
        .help(L("\(marker.title) — click to jump here, double-click to rename"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Marker: \(marker.title)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.jump(to: marker) }
        .contextMenu {
            Button(L("Rename Marker…")) { startRenaming(marker) }
            Button(L("Delete Marker"), role: .destructive) { model.deleteMarker(marker.id) }
        }
        .popover(isPresented: Binding(get: { renaming == marker.id }, set: { if !$0 { renaming = nil } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Marker name"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VideoEditorTheme.textSecondary)
                TextField(L("Marker \(1)"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { finishRenaming(marker) }
                HStack {
                    Button(L("Delete"), role: .destructive) {
                        renaming = nil
                        model.deleteMarker(marker.id)
                    }
                    Spacer()
                    Button(L("Done")) { finishRenaming(marker) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }

    private func startRenaming(_ marker: VideoPlacedMarker) {
        draft = marker.marker.name ?? ""
        renaming = marker.id
    }

    private func finishRenaming(_ marker: VideoPlacedMarker) {
        model.renameMarker(marker.id, to: draft)
        renaming = nil
    }
}

// MARK: - Chapter track

/// Chapters in a movie file: a text track of chapter titles, linked to
/// the picture as its chapter list, which players (QuickTime Player, IINA,
/// VLC, Final Cut Pro…) show as chapters.
enum VideoChapterTrack {
    /// 3GPP timed text ('tx3g'), which both MP4 and QuickTime files carry.
    static func formatDescription() -> CMFormatDescription? {
        let color: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: 0, kCMTextFormatDescriptionColor_Green: 0,
            kCMTextFormatDescriptionColor_Blue: 0, kCMTextFormatDescriptionColor_Alpha: 255,
        ]
        let white: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: 255, kCMTextFormatDescriptionColor_Green: 255,
            kCMTextFormatDescriptionColor_Blue: 255, kCMTextFormatDescriptionColor_Alpha: 255,
        ]
        let extensions: [CFString: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags: 0,
            kCMTextFormatDescriptionExtension_BackgroundColor: color,
            kCMTextFormatDescriptionExtension_DefaultTextBox: [
                kCMTextFormatDescriptionRect_Top: 0, kCMTextFormatDescriptionRect_Left: 0,
                kCMTextFormatDescriptionRect_Bottom: 0, kCMTextFormatDescriptionRect_Right: 0,
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_DefaultStyle: [
                kCMTextFormatDescriptionStyle_StartChar: 0, kCMTextFormatDescriptionStyle_EndChar: 0,
                kCMTextFormatDescriptionStyle_Font: 1, kCMTextFormatDescriptionStyle_FontFace: 0,
                kCMTextFormatDescriptionStyle_ForegroundColor: white, kCMTextFormatDescriptionStyle_FontSize: 12,
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_HorizontalJustification: 0,
            kCMTextFormatDescriptionExtension_VerticalJustification: 0,
            kCMTextFormatDescriptionExtension_FontTable: ["1": "Sans-Serif"],
        ]
        var description: CMFormatDescription?
        CMFormatDescriptionCreate(allocator: nil, mediaType: kCMMediaType_Text, mediaSubType: kCMTextFormatType_3GText, extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        return description
    }

    /// A chapter track for `writer`, linked to its picture. Call before
    /// `startWriting`; nil when the file can't carry one.
    static func addInput(to writer: AVAssetWriter, linkedTo video: AVAssetWriterInput) -> AVAssetWriterInput? {
        guard let format = formatDescription() else { return nil }
        let input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        input.marksOutputTrackAsEnabled = false
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        let association = AVAssetTrack.AssociationType.chapterList.rawValue
        guard video.canAddTrackAssociation(withTrackOf: input, type: association) else { return nil }
        video.addTrackAssociation(withTrackOf: input, type: association)
        return input
    }

    /// Writes every chapter (each lasting until the next, the last until
    /// `end`) as the writer asks for them, then closes the track. The
    /// writer interleaves the tracks, so it takes them while the picture
    /// is written.
    static func write(_ chapters: [VideoChapter], end: Double, to input: AVAssetWriterInput) {
        let samples: [CMSampleBuffer] = formatDescription().map { format in
            let ends = chapters.dropFirst().map(\.start) + [end]
            return zip(chapters, ends).compactMap { chapter, chapterEnd in
                chapterEnd > chapter.start ? sample(chapter.title, start: chapter.start, duration: chapterEnd - chapter.start, format: format) : nil
            }
        } ?? []
        let queue = DispatchQueue(label: "com.lfstudios.export.chapters")
        var next = 0
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData, next < samples.count {
                input.append(samples[next])
                next += 1
            }
            if next >= samples.count { input.markAsFinished() }
        }
    }

    /// One title: its UTF-8 length (16-bit, big-endian), then the text.
    private static func sample(_ title: String, start: Double, duration: Double, format: CMFormatDescription) -> CMSampleBuffer? {
        let text = Array(title.utf8.prefix(Int(UInt16.max)))
        var bytes = [UInt8(text.count >> 8), UInt8(text.count & 0xFF)] + text
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block,
              CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count) == noErr else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var size = bytes.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        return sample
    }
}
