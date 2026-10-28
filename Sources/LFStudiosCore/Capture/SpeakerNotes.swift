import AppKit
import SwiftUI

/// A window that never shows up in a recording, whatever is recorded
/// (RecordingCaptureFilter leaves these out even when LF Studios' own
/// windows are kept).
protocol RecordingNeverCaptured: NSWindow {}

/// Speaker notes: a floating teleprompter beside the recording bar. The
/// notes are remembered between recordings and go into the recording's
/// data (and so its project) when the panel was open while recording.
@MainActor
final class SpeakerNotes: ObservableObject {
    static let shared = SpeakerNotes()

    static let fontSizeRange: ClosedRange<Double> = 14...72
    static let speedRange: ClosedRange<Double> = 10...200

    var defaults: UserDefaults = .standard

    @Published var text: String {
        didSet { defaults.set(text, forKey: "speakerNotesText") }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "speakerNotesFontSize") }
    }
    /// Points a second.
    @Published var speed: Double {
        didSet { defaults.set(speed, forKey: "speakerNotesSpeed") }
    }
    /// Auto-scroll begins when a recording starts.
    @Published var startsWithRecording: Bool {
        didSet { defaults.set(startsWithRecording, forKey: "speakerNotesStartWithRecording") }
    }
    /// Reading (Space pauses) or writing (the text can be edited).
    @Published var isEditing = true
    @Published private(set) var isScrolling = false

    private(set) var panel: SpeakerNotesPanel?
    weak var textView: NSTextView?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Shown at some point while the current recording ran.
    private var shownWhileRecording = false
    private var recording = false

    private init() {
        let stored = UserDefaults.standard
        text = stored.string(forKey: "speakerNotesText") ?? ""
        fontSize = stored.object(forKey: "speakerNotesFontSize") as? Double ?? 30
        speed = stored.object(forKey: "speakerNotesSpeed") as? Double ?? 45
        startsWithRecording = stored.bool(forKey: "speakerNotesStartWithRecording")
        isEditing = text.isEmpty
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = self.panel ?? SpeakerNotesPanel(notes: self)
        self.panel = panel
        if !panel.isVisible { panel.placeNearTop() }
        panel.orderFrontRegardless()
        if recording { shownWhileRecording = true }
    }

    func hide() {
        stopScrolling()
        panel?.orderOut(nil)
    }

    // MARK: Scrolling

    func toggleScrolling() {
        isScrolling ? stopScrolling() : startScrolling()
    }

    func startScrolling() {
        guard !isScrolling, textView != nil else { return }
        isEditing = false
        isScrolling = true
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopScrolling() {
        timer?.invalidate()
        timer = nil
        isScrolling = false
    }

    /// Back to the beginning.
    func rewind() {
        guard let clip = textView?.enclosingScrollView?.contentView else { return }
        clip.scroll(to: .zero)
        textView?.enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// By hand, in points (positive: further down).
    func scroll(by points: CGFloat) {
        guard let scroll = textView?.enclosingScrollView, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let limit = max(document.frame.height - clip.bounds.height, 0)
        let y = min(max(clip.bounds.origin.y + points, 0), limit)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, 0.1)
        lastTick = now
        guard let scroll = textView?.enclosingScrollView, let document = scroll.documentView else { return stopScrolling() }
        let clip = scroll.contentView
        let limit = max(document.frame.height - clip.bounds.height, 0)
        let y = clip.bounds.origin.y + CGFloat(speed * elapsed)
        clip.scroll(to: NSPoint(x: 0, y: min(y, limit)))
        scroll.reflectScrolledClipView(clip)
        // The end: stop there.
        if y >= limit { stopScrolling() }
    }

    // MARK: Recording

    func recordingStarted() {
        recording = true
        shownWhileRecording = isShown
        if isShown, startsWithRecording, !text.isEmpty {
            rewind()
            startScrolling()
        }
    }

    /// The notes to keep with the take just recorded (nil: the panel
    /// wasn't used, or it's empty).
    func recordingFinished() -> String? {
        defer {
            recording = false
            shownWhileRecording = false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return shownWhileRecording && !trimmed.isEmpty ? text : nil
    }
}

// MARK: - The panel

final class SpeakerNotesPanel: NSPanel, RecordingNeverCaptured {
    init(notes: SpeakerNotes) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = L("Speaker Notes")
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Also out of screenshots and other apps' screen sharing.
        sharingType = .none
        appearance = AppAppearance.overlay
        minSize = NSSize(width: 360, height: 200)
        contentView = NSHostingView(rootView: SpeakerNotesView(notes: notes))
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        SpeakerNotes.shared.stopScrolling()
        super.close()
    }

    /// Top middle of the screen with the pointer, near the camera.
    func placeNearTop() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 24))
    }
}

/// Large text that scrolls, and the controls above it.
struct SpeakerNotesView: View {
    @ObservedObject var notes: SpeakerNotes

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 12)
                .padding(.top, 30)
                .padding(.bottom, 8)
            ZStack(alignment: .top) {
                SpeakerNotesText(notes: notes)
                if !notes.isEditing {
                    // Where to read: a soft band a third of the way down.
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: CGFloat(notes.fontSize) * 1.5)
                            .offset(y: geometry.size.height / 3)
                            .allowsHitTesting(false)
                    }
                }
                if notes.text.isEmpty {
                    Text(L("Paste or type your notes here. They stay out of every recording."))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 0.96)))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                notes.toggleScrolling()
            } label: {
                Image(systemName: notes.isScrolling ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .help(notes.isScrolling ? L("Pause scrolling (Space)") : L("Start scrolling (Space)"))
            .disabled(notes.text.isEmpty)
            Button {
                notes.rewind()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .help(L("Back to the start"))
            Image(systemName: "hare")
                .foregroundStyle(.secondary)
                .help(L("Scrolling speed"))
            Slider(value: $notes.speed, in: SpeakerNotes.speedRange)
                .frame(width: 90)
                .controlSize(.small)
            Image(systemName: "textformat.size")
                .foregroundStyle(.secondary)
                .help(L("Text size"))
            Slider(value: $notes.fontSize, in: SpeakerNotes.fontSizeRange)
                .frame(width: 80)
                .controlSize(.small)
            Spacer(minLength: 4)
            Toggle(L("Start with recording"), isOn: $notes.startsWithRecording)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(L("Begins scrolling when the recording starts"))
            Button(notes.isEditing ? L("Read") : L("Edit")) {
                if notes.isEditing { notes.isEditing = false } else {
                    notes.stopScrolling()
                    notes.isEditing = true
                }
            }
            .controlSize(.small)
            .help(notes.isEditing ? L("Read mode: Space starts and pauses scrolling") : L("Change the text"))
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
    }
}

/// The text itself: editable while writing; while reading, Space starts
/// and pauses, and the arrow keys scroll.
struct SpeakerNotesText: NSViewRepresentable {
    @ObservedObject var notes: SpeakerNotes

    final class TextView: NSTextView {
        weak var notes: SpeakerNotes?

        override func keyDown(with event: NSEvent) {
            guard let notes, !isEditable else { return super.keyDown(with: event) }
            switch event.keyCode {
            case 49: MainActor.assumeIsolated { notes.toggleScrolling() }
            case 125: MainActor.assumeIsolated { notes.scroll(by: CGFloat(notes.fontSize) * 1.4) }
            case 126: MainActor.assumeIsolated { notes.scroll(by: -CGFloat(notes.fontSize) * 1.4) }
            default: super.keyDown(with: event)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let notes: SpeakerNotes
        init(notes: SpeakerNotes) { self.notes = notes }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated { notes.text = view.string }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(notes: notes) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let view = TextView()
        view.notes = notes
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textColor = .white
        view.insertionPointColor = .white
        view.textContainerInset = NSSize(width: 18, height: 12)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.string = notes.text
        scroll.documentView = view
        notes.textView = view
        apply(to: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? TextView else { return }
        if view.string != notes.text { view.string = notes.text }
        apply(to: view)
    }

    private func apply(to view: NSTextView) {
        let font = NSFont.systemFont(ofSize: CGFloat(notes.fontSize), weight: .medium)
        if view.font != font {
            view.font = font
            let style = NSMutableParagraphStyle()
            style.lineSpacing = CGFloat(notes.fontSize) * 0.25
            view.defaultParagraphStyle = style
            view.textStorage?.addAttributes([.font: font, .paragraphStyle: style, .foregroundColor: NSColor.white], range: NSRange(location: 0, length: view.string.utf16.count))
        }
        view.isEditable = notes.isEditing
        view.isSelectable = true
    }
}
