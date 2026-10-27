import Foundation

// MARK: - README.txt

enum VideoHandoffReadme {
    /// "1:02.40" (or "1:02:03.40" past an hour).
    static func clock(_ seconds: Double) -> String {
        let hundredths = Int((max(seconds, 0) * 100).rounded())
        let h = hundredths / 360_000, m = (hundredths / 6000) % 60, s = (hundredths / 100) % 60, f = hundredths % 100
        return h > 0 ? String(format: "%d:%02d:%02d.%02d", h, m, s, f) : String(format: "%d:%02d.%02d", m, s, f)
    }

    static func rate(_ fps: Double) -> String {
        abs(fps - fps.rounded()) < 0.01 ? "\(Int(fps.rounded())) fps" : String(format: "%.2f fps", fps) // l10n-ignore: a number and a unit
    }

    /// The README, in English like the file names: it travels to other
    /// people and editing apps. `durations` are measured from the written
    /// files (planned ones otherwise).
    static func text(plan: VideoHandoffPlan, name: String, date: Date = Date(), appVersion: String?, durations: [String: Double] = [:], written: Set<String>? = nil, markers: [VideoPlacedMarker] = [], timelineDuration: Double = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let options = plan.options
        var lines: [String] = []
        lines.append("\(name) — Creative Handoff")
        lines.append("Made with LF Studios\(appVersion.map { " \($0)" } ?? "") on \(formatter.string(from: date)).")
        lines.append("")
        lines.append(options.clips == .trimmed
            ? "Clips: trimmed to the edit (cuts, clip order, and speed changes are in the files)."
            : "Clips: the full original recordings, uncut.")
        if options.lineUp {
            lines.append("Lined up: every video and sound file starts at 0:00 and is \(clock(plan.clockDuration)) long. Put them all at the start of a timeline and they play in sync, the camera included.")
        } else {
            lines.append("Not lined up: each file is only as long as its content; \"starts at\" says where it belongs.")
        }
        lines.append(options.clips == .trimmed ? "Times are on the edit's clock." : "Times are on the recordings' clock (the first recording starts at 0:00).")
        lines.append("")
        lines.append("FILES")
        let items = plan.items.filter { written?.contains($0.relativePath) ?? true }
        for folder in VideoHandoffItem.Folder.allCases {
            for item in items where item.folder == folder {
                lines.append("")
                lines.append(item.relativePath)
                lines.append("  \(item.description)")
                var facts: [String] = []
                if let duration = durations[item.relativePath] ?? item.duration { facts.append("length \(clock(duration))") }
                if let fps = item.frameRate, item.folder == .screen || item.folder == .camera || item.folder == .final { facts.append(rate(fps)) }
                if let start = item.startOffset { facts.append("starts at \(clock(start))") }
                facts.append(item.treatment.readme)
                lines.append("  " + facts.joined(separator: " · "))
            }
        }
        if items.contains(where: { $0.treatment == .originalWithEditList }) {
            lines.append("")
            lines.append("About \"original frames, not re-encoded\": those files hold the recording exactly as it was, and a QuickTime edit list places it on the clock (empty at the start, a silent track to the end). QuickTime Player, Final Cut Pro, and DaVinci Resolve follow it. If an app shows such a file starting at its first frame, use the timeline file instead, which places it on its own.")
        }
        lines.append("")
        lines.append("RE-ENCODED OR UNTOUCHED")
        let reencoded = items.filter { if case .proRes = $0.treatment { return true } else { return false } }
        let untouched = items.filter { $0.treatment == .original || $0.treatment == .originalWithEditList }
        lines.append("  Re-encoded to ProRes: " + (reencoded.isEmpty ? "none" : reencoded.map(\.relativePath).joined(separator: ", ")))
        lines.append("  Untouched originals: " + (untouched.isEmpty ? "none" : untouched.map(\.relativePath).joined(separator: ", ")))
        if plan.options.includeTimeline {
            lines.append("")
            lines.append("TIMELINE")
            lines.append("  Timeline.fcpxml opens in Final Cut Pro (File ▸ Import ▸ XML) and DaVinci Resolve (File ▸ Import ▸ Timeline).")
            lines.append("  Timeline (Premiere).xml opens in Adobe Premiere Pro (File ▸ Import).")
            lines.append("  They carry: every clip in its place, cuts and trims, clip order, speed changes, the camera at its offset, and the microphone, Mac sound, and music on their own tracks. 03 Audio/Full Mix.wav isn't on them: it's those tracks already mixed, so it would play everything twice. Use it on its own, or as a reference for the mix.")
            lines.append("  They can't carry LF Studios' effects: zooms and pans that follow the pointer, the drawn pointer and click effects, keys on screen, the background, padding, corners and shadow, the camera's shape, crop, border and background removal, annotations, title cards, transitions, and caption styling. Those are in the finished video (06 Final). Captions come as .srt files (05 Captions): import them in the editing app.")
            if !markers.isEmpty {
                let list = markers.map { "\(VideoChapterText.timestamp($0.time, hours: timelineDuration >= 3600)) \($0.title)" }.joined(separator: ", ")
                lines.append("  Markers (\(markers.count)) are on the timelines at their places: \(list).")
            }
            lines.append("  The timeline files point at this folder where it is now: if you move it, relink the media in the editing app.")
        }
        if !plan.skipped.isEmpty {
            lines.append("")
            lines.append("NOT INCLUDED")
            for reason in plan.skipped { lines.append("  • \(reason)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Timelines

/// A frame-exact clock for the timeline files.
struct VideoHandoffTimebase {
    let fps: Double
    /// Frame duration as a fraction: 1/30, 1001/30000…
    let numerator: Int
    let denominator: Int

    init(fps: Double) {
        let ntsc = [23.976: 24000, 29.97: 30000, 59.94: 60000].first { abs($0.key - fps) < 0.02 }
        if let ntsc {
            numerator = 1001
            denominator = ntsc.value
            self.fps = Double(ntsc.value) / 1001
        } else {
            let whole = max(Int(fps.rounded()), 1)
            numerator = 1
            denominator = whole
            self.fps = Double(whole)
        }
    }

    var isNTSC: Bool { numerator == 1001 }
    /// The whole-number rate Premiere's XML writes.
    var timebase: Int { Int((Double(denominator) / Double(numerator)).rounded()) }

    func frames(_ seconds: Double) -> Int { Int((seconds * fps).rounded()) }

    /// FCPXML time: a whole number of frames.
    func fcp(_ seconds: Double) -> String {
        let count = frames(seconds)
        return count == 0 ? "0s" : "\(count * numerator)/\(denominator)s"
    }

    var frameDuration: String { "\(numerator)/\(denominator)s" }
}

/// What goes on the timeline: each media file and where it plays.
struct VideoHandoffTimelineClip: Equatable {
    enum Kind: Equatable { case screen, camera, audio }
    var kind: Kind
    var file: String
    /// Lane: 1 = screen, 2… = cameras, −1… = sound.
    var lane: Int
    /// Where it plays on the timeline.
    var offset: Double
    /// Where in the file it starts.
    var start: Double
    var duration: Double
    var speed: Double = 1
}

enum VideoHandoffTimeline {
    /// The clips the timeline files place: the written files at their spots.
    /// Trimmed handoffs already hold the edit, so each file plays from its
    /// own position; uncut ones are cut and sped up here like the edit.
    static func clips(plan: VideoHandoffPlan, input: VideoHandoffInput) -> [VideoHandoffTimelineClip] {
        var clips: [VideoHandoffTimelineClip] = []
        let lineUp = plan.options.lineUp
        let media = plan.items.filter { [.screen, .camera, .audio].contains($0.folder) }
        var audioLane = -1
        var cameraLane = 2
        if plan.options.clips == .trimmed {
            for item in media {
                let duration = item.duration ?? plan.clockDuration
                switch item.work {
                case .reencode(let pieces, _, _, _, _, _), .passthrough(let pieces, _), .audio(let pieces, _, _, _):
                    let kind: VideoHandoffTimelineClip.Kind = item.folder == .screen ? .screen : (item.folder == .camera ? .camera : .audio)
                    let lane: Int
                    switch kind {
                    case .screen: lane = 1
                    case .camera: lane = cameraLane; cameraLane += 1
                    case .audio: lane = audioLane; audioLane -= 1
                    }
                    if kind == .screen {
                        // The clip's own stretch of the lined-up file.
                        for piece in pieces {
                            let at = lineUp ? piece.at : (item.startOffset ?? 0)
                            clips.append(.init(kind: kind, file: item.relativePath, lane: lane, offset: at, start: lineUp ? piece.at : 0, duration: piece.outputDuration))
                        }
                    } else {
                        clips.append(.init(kind: kind, file: item.relativePath, lane: lane, offset: lineUp ? 0 : (item.startOffset ?? 0), start: 0, duration: duration))
                    }
                default:
                    continue
                }
            }
            return clips
        }
        // Uncut files: the edit, cut by cut.
        let segments = input.segments
        func fileTime(_ item: VideoHandoffItem, local: Double, axisStart: Double) -> Double {
            // Lined-up files keep the recording at its place on the axis.
            if lineUp, item.treatment == .originalWithEditList { return local + axisStart }
            return local
        }
        for recording in input.recordings {
            guard let url = recording.url else { continue }
            let screen = media.first { $0.folder == .screen && $0.recording == recording.id }
            for segment in segments {
                for piece in VideoHandoffPlanner.screenPieces(segment, recordings: [recording]) where piece.url == url {
                    if let screen {
                        clips.append(.init(kind: .screen, file: screen.relativePath, lane: 1, offset: piece.at, start: fileTime(screen, local: piece.sourceStart, axisStart: recording.offset), duration: piece.outputDuration, speed: piece.speed))
                    }
                }
            }
            if let camera = recording.camera, let cameraURL = camera.url,
               let item = media.first(where: { $0.folder == .camera && $0.recording == recording.id }) {
                for piece in VideoHandoffPlanner.cameraPieces(recording, camera: camera, url: cameraURL, segments: segments) {
                    let local = piece.sourceStart
                    let start = lineUp && item.treatment == .originalWithEditList ? local + recording.offset + camera.offset : local
                    clips.append(.init(kind: .camera, file: item.relativePath, lane: 2, offset: piece.at, start: start, duration: piece.outputDuration, speed: piece.speed))
                }
            }
        }
        // Sound files are on the recordings' axis: cut them like the screen.
        // The full mix stays out of the timelines: the separate tracks are there.
        for (index, item) in media.filter({ $0.folder == .audio && !$0.fileName.hasPrefix("Music.") && $0.fileName != "Full Mix.wav" }).enumerated() {
            for segment in segments where !segment.clip.muted {
                let clip = segment.clip
                let start = lineUp ? clip.sourceStart : clip.sourceStart - (item.startOffset ?? 0)
                clips.append(.init(kind: .audio, file: item.relativePath, lane: -1 - index, offset: segment.timelineStart, start: max(start, 0), duration: segment.duration, speed: clip.normalizedSpeed))
            }
        }
        if let music = media.first(where: { $0.folder == .audio && $0.fileName.hasPrefix("Music.") }) {
            clips.append(.init(kind: .audio, file: music.relativePath, lane: -10, offset: 0, start: 0, duration: min(music.duration ?? input.timelineDuration, input.timelineDuration)))
        }
        return clips
    }

    static func fileURL(_ folder: URL, _ relative: String) -> String {
        folder.appendingPathComponent(relative).absoluteURL.absoluteString
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// FCPXML 1.10 for Final Cut Pro and DaVinci Resolve: an empty primary
    /// storyline as long as the video, every clip connected to it in its lane.
    static func fcpxml(plan: VideoHandoffPlan, input: VideoHandoffInput, folder: URL, durations: [String: Double]) -> String {
        let base = VideoHandoffTimebase(fps: input.frameRate)
        let size = input.recordings.first?.size ?? CGSize(width: 1920, height: 1080)
        let clips = clips(plan: plan, input: input)
        let total = input.timelineDuration
        let files = Array(Set(clips.map(\.file))).sorted()
        var ids: [String: String] = [:]
        var resources = ["    <format id=\"r1\" frameDuration=\"\(base.frameDuration)\" width=\"\(Int(size.width))\" height=\"\(Int(size.height))\"/>"]
        for (index, file) in files.enumerated() {
            let id = "r\(index + 2)"
            ids[file] = id
            let item = plan.items.first { $0.relativePath == file }
            let isVideo = item?.folder == .screen || item?.folder == .camera
            let length = durations[file] ?? item?.duration ?? total
            resources.append("    <asset id=\"\(id)\" name=\"\(escape((file as NSString).lastPathComponent))\" start=\"0s\" duration=\"\(base.fcp(length))\" hasVideo=\"\(isVideo ? 1 : 0)\" hasAudio=\"\(isVideo ? 0 : 1)\"\(isVideo ? " format=\"r1\"" : " audioSources=\"1\" audioChannels=\"2\" audioRate=\"48000\"")>")
            resources.append("      <media-rep kind=\"original-media\" src=\"\(escape(fileURL(folder, file)))\"/>")
            resources.append("    </asset>")
        }
        var connected: [String] = []
        for clip in clips.sorted(by: { ($0.lane, $0.offset) > ($1.lane, $1.offset) }) {
            guard let ref = ids[clip.file] else { continue }
            let name = escape((clip.file as NSString).lastPathComponent)
            var element = "          <asset-clip ref=\"\(ref)\" lane=\"\(clip.lane)\" offset=\"\(base.fcp(clip.offset))\" name=\"\(name)\" start=\"\(base.fcp(clip.start))\" duration=\"\(base.fcp(clip.duration))\""
            if abs(clip.speed - 1) > 0.001 {
                // Media time runs `speed` times faster than the clip's own.
                element += ">\n            <timeMap>\n              <timept time=\"\(base.fcp(clip.start))\" value=\"\(base.fcp(clip.start))\" interp=\"linear\"/>\n              <timept time=\"\(base.fcp(clip.start + clip.duration))\" value=\"\(base.fcp(clip.start + clip.duration * clip.speed))\" interp=\"linear\"/>\n            </timeMap>\n          </asset-clip>"
            } else {
                element += "/>"
            }
            connected.append(element)
        }
        // Markers on the storyline (after its clips, as FCPXML wants).
        for marker in input.project.placedMarkers(segments: input.segments) where marker.time <= total {
            connected.append("          <marker start=\"\(base.fcp(marker.time))\" duration=\"\(base.frameDuration)\" value=\"\(escape(marker.title))\"/>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
          <resources>
        \(resources.joined(separator: "\n"))
          </resources>
          <library>
            <event name="\(escape(input.name)) – Handoff">
              <project name="\(escape(input.name))">
                <sequence format="r1" duration="\(base.fcp(total))" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
                  <spine>
                    <gap name="Gap" offset="0s" start="0s" duration="\(base.fcp(total))">
        \(connected.joined(separator: "\n"))
                    </gap>
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>

        """
    }

    /// Final Cut Pro 7 XML (xmeml 4), which Adobe Premiere Pro imports.
    static func premiereXML(plan: VideoHandoffPlan, input: VideoHandoffInput, folder: URL, durations: [String: Double]) -> String {
        let base = VideoHandoffTimebase(fps: input.frameRate)
        let size = input.recordings.first?.size ?? CGSize(width: 1920, height: 1080)
        let clips = clips(plan: plan, input: input)
        let total = base.frames(input.timelineDuration)
        let rate = "<rate><timebase>\(base.timebase)</timebase><ntsc>\(base.isNTSC ? "TRUE" : "FALSE")</ntsc></rate>"
        var fileIDs: [String: String] = [:]
        var clipNumber = 0

        func clipitem(_ clip: VideoHandoffTimelineClip, video: Bool) -> String {
            clipNumber += 1
            let item = plan.items.first { $0.relativePath == clip.file }
            let fileFrames = base.frames(durations[clip.file] ?? item?.duration ?? input.timelineDuration)
            let name = escape((clip.file as NSString).lastPathComponent)
            var file: String
            if let id = fileIDs[clip.file] {
                file = "<file id=\"\(id)\"/>"
            } else {
                let id = "file-\(fileIDs.count + 1)"
                fileIDs[clip.file] = id
                let media = video
                    ? "<video><samplecharacteristics>\(rate)<width>\(Int(size.width))</width><height>\(Int(size.height))</height></samplecharacteristics></video>"
                    : "<audio><samplecharacteristics><depth>24</depth><samplerate>48000</samplerate></samplecharacteristics><channelcount>2</channelcount></audio>"
                file = "<file id=\"\(id)\"><name>\(name)</name><pathurl>\(escape(fileURL(folder, clip.file)))</pathurl>\(rate)<duration>\(fileFrames)</duration><media>\(media)</media></file>"
            }
            let start = base.frames(clip.offset)
            let end = start + base.frames(clip.duration)
            let inPoint = base.frames(clip.start)
            let outPoint = inPoint + Int((Double(base.frames(clip.duration)) * clip.speed).rounded())
            var speed = ""
            if abs(clip.speed - 1) > 0.001 {
                speed = "<filter><effect><name>Time Remap</name><effectid>timeremap</effectid><effectcategory>motion</effectcategory><effecttype>motion</effecttype><mediatype>video</mediatype><parameter><parameterid>speed</parameterid><name>speed</name><value>\(String(format: "%.2f", clip.speed * 100))</value></parameter><parameter><parameterid>variablespeed</parameterid><name>variablespeed</name><value>0</value></parameter></effect></filter>"
            }
            return "          <clipitem id=\"clipitem-\(clipNumber)\"><name>\(name)</name><enabled>TRUE</enabled><duration>\(fileFrames)</duration>\(rate)<start>\(start)</start><end>\(end)</end><in>\(inPoint)</in><out>\(outPoint)</out>\(file)\(speed)</clipitem>"
        }

        let videoLanes = Array(Set(clips.filter { $0.lane > 0 }.map(\.lane))).sorted()
        let audioLanes = Array(Set(clips.filter { $0.lane < 0 }.map(\.lane))).sorted(by: >)
        let videoTracks = videoLanes.map { lane in
            "        <track>\n" + clips.filter { $0.lane == lane }.sorted { $0.offset < $1.offset }.map { clipitem($0, video: true) }.joined(separator: "\n") + "\n        </track>"
        }
        let audioTracks = audioLanes.map { lane in
            "        <track>\n" + clips.filter { $0.lane == lane }.sorted { $0.offset < $1.offset }.map { clipitem($0, video: false) }.joined(separator: "\n") + "\n        </track>"
        }
        let sequenceMarkers = input.project.placedMarkers(segments: input.segments).map { marker in
            "    <marker><name>\(escape(marker.title))</name><comment></comment><in>\(base.frames(marker.time))</in><out>-1</out></marker>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
          <sequence id="sequence-1">
            <name>\(escape(input.name)) – Handoff</name>
            <duration>\(total)</duration>
            \(rate)
            <media>
              <video>
                <format><samplecharacteristics>\(rate)<width>\(Int(size.width))</width><height>\(Int(size.height))</height></samplecharacteristics></format>
        \(videoTracks.joined(separator: "\n"))
              </video>
              <audio>
        \(audioTracks.joined(separator: "\n"))
              </audio>
            </media>
        \(sequenceMarkers.joined(separator: "\n"))
          </sequence>
        </xmeml>

        """
    }
}
