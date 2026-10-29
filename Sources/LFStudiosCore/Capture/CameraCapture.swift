import AppKit
import AVFoundation

/// The camera while recording: a live bubble on screen (kept out of the
/// screen capture) and a separate movie file that the editor places over
/// the recording — so its size, shape, and position stay editable.
@MainActor
final class CameraCapture {
    static let shared = CameraCapture()

    enum StartResult: Equatable {
        case started
        case denied
        case noCamera
        case failed

        /// What to tell the user when the camera can't be used.
        var message: String? {
            switch self {
            case .started: nil
            case .denied: L("Camera access is off — allow LF Studios in System Settings → Privacy & Security → Camera.")
            case .noCamera: L("No camera found.")
            case .failed: L("The camera couldn't start.")
            }
        }
    }

    enum Interruption: Equatable {
        case disconnected
        case failed
    }

    private var session: AVCaptureSession?
    private var pipeline: CameraPipeline?
    private var bubble: CameraBubbleWindow?
    private var isRecording = false
    private var observers: [NSObjectProtocol] = []
    /// Told when the camera drops out mid-session (unplugged, taken by
    /// another app, a capture error).
    var interruptionHandler: ((Interruption) -> Void)?

    var isActive: Bool { session != nil }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    static var devices: [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.builtInWideAngleCamera, .external, .continuityCamera]
        } else {
            types = [.builtInWideAngleCamera, .externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    static func device(for id: String) -> AVCaptureDevice? {
        if !id.isEmpty, let device = AVCaptureDevice(uniqueID: id), device.isConnected { return device }
        return AVCaptureDevice.default(for: .video) ?? devices.first
    }

    /// Where camera movies live (next to the other editor data, not in the
    /// user's recordings folder).
    static func movieURL(for screenRecording: URL) -> URL {
        VideoStorageLocation.root
            .appendingPathComponent("LF Studios", isDirectory: true)
            .appendingPathComponent("VideoCameras", isDirectory: true)
            .appendingPathComponent("\(screenRecording.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).mov")
    }

    /// Starts the camera and shows the preview where the camera goes in
    /// `rect`'s video (screen coordinates), in the shape last chosen.
    @discardableResult
    func start(deviceID: String, around rect: CGRect, on screen: NSScreen) async -> StartResult {
        if session != nil {
            // A spot the user dragged the preview to stays put.
            bubble?.update(frame: rect, on: screen)
            return .started
        }
        guard await Self.requestAccess() else { return .denied }
        guard session == nil else { return .started }
        guard let device = Self.device(for: deviceID) else { return .noCamera }

        let pipeline = CameraPipeline()
        let session = AVCaptureSession()
        do {
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            } else {
                session.sessionPreset = .high
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraCaptureError.unavailable }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(pipeline, queue: pipeline.queue)
            guard session.canAddOutput(output) else { throw CameraCaptureError.unavailable }
            session.addOutput(output)
            session.commitConfiguration()
        } catch {
            print("[LF Studios] Camera setup failed: \(error)")
            return .failed
        }

        self.session = session
        self.pipeline = pipeline
        let bubble = CameraBubbleWindow(session: session, setup: Settings.recordingCameraSetup)
        bubble.changed = { preview in
            // Remembered for the next recording.
            Settings.recordingCameraSetup = preview.currentSetup(frame: preview.frameRect)
        }
        bubble.place(around: rect, on: screen)
        bubble.orderFrontRegardless()
        self.bubble = bubble
        observe(session: session, device: device)

        nonisolated(unsafe) let running = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                running.startRunning()
                continuation.resume()
            }
        }
        return .started
    }

    /// Hides the bubble and releases the camera (no-op while recording).
    func stop() {
        guard !isRecording else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        bubble?.close()
        bubble = nil
        pipeline = nil
        guard let session else { return }
        self.session = nil
        nonisolated(unsafe) let stopping = session
        DispatchQueue.global(qos: .userInitiated).async { stopping.stopRunning() }
    }

    // MARK: The preview's shape and place (the recording bar)

    /// The recording frame moved or changed size.
    func updateFrame(_ rect: CGRect, on screen: NSScreen) {
        bubble?.update(frame: rect, on: screen)
    }

    /// Camera shape or Roundness changed in the recording bar.
    func apply(_ setup: VideoRecordingCameraSetup) {
        bubble?.apply(setup)
    }

    /// Select size: handles on the preview.
    var showsSizeHandles: Bool {
        get { bubble?.showsHandles ?? false }
        set { bubble?.showsHandles = newValue }
    }

    /// The camera's shape and place for a recording of `frame`, as the
    /// preview shows it now (nil: no preview).
    func setup(forRecording frame: CGRect) -> VideoRecordingCameraSetup? {
        guard let bubble else { return nil }
        return bubble.currentSetup(frame: frame)
    }

    /// Recording started: the preview stays, its label and handles go.
    func hidePreviewControls() {
        bubble?.showsHandles = false
        bubble?.showsLabel = false
    }

    /// `onFirstFrame` gets the first written frame's host time.
    func beginRecording(to url: URL, onFirstFrame: @escaping @Sendable (Double) -> Void = { _ in }) {
        guard let pipeline else { return }
        isRecording = true
        pipeline.begin(url: url, onFirstFrame: onFirstFrame)
    }

    /// Same host clock as the screen recording's pause, so both stay aligned.
    func pauseRecording(at host: Double) {
        guard isRecording else { return }
        pipeline?.pause(at: host)
    }

    func resumeRecording(at host: Double) {
        guard isRecording else { return }
        pipeline?.resume(at: host)
    }

    /// Finishes the camera movie. `firstFrameTime` is host-clock seconds —
    /// the same clock as the screen frames — so the editor can line them up.
    func finishRecording() async -> CameraPipeline.Result? {
        guard isRecording, let pipeline else {
            isRecording = false
            return nil
        }
        let result = await pipeline.finish()
        isRecording = false
        return result
    }

    /// Recording failed or was abandoned: drop the camera file.
    func cancelRecording() {
        guard isRecording, let pipeline else { return }
        isRecording = false
        pipeline.cancel()
    }

    private func observe(session: AVCaptureSession, device: AVCaptureDevice) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [
            NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                MainActor.assumeIsolated {
                    print("[LF Studios] Camera session error: \(error.map { "\($0)" } ?? "unknown")")
                    self?.interruptionHandler?(.failed)
                }
            },
            NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interruptionHandler?(.disconnected) }
            },
        ]
    }
}

enum CameraCaptureError: Error {
    case unavailable
}

/// Receives camera frames and writes them to a movie while armed.
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Result: Sendable {
        let url: URL
        /// Host-clock seconds of the first written frame.
        let firstFrameTime: Double
        let size: CGSize
    }

    let queue = DispatchQueue(label: "com.lfstudios.camera", qos: .userInitiated)

    // Touched only on `queue`.
    private var armed = false
    private var url: URL?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var timeline = RecordingTimeline()
    private var lastTime: Double?
    private var size: CGSize = .zero
    private var onFirstFrame: (@Sendable (Double) -> Void)?

    func begin(url: URL, onFirstFrame: @escaping @Sendable (Double) -> Void = { _ in }) {
        queue.async {
            self.url = url
            self.writer = nil
            self.input = nil
            self.timeline = RecordingTimeline()
            self.lastTime = nil
            self.onFirstFrame = onFirstFrame
            self.armed = true
        }
    }

    func pause(at host: Double) {
        queue.async { self.timeline.pause(at: host) }
    }

    func resume(at host: Double) {
        queue.async { self.timeline.resume(at: host) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        append(sampleBuffer)
    }

    /// Writes one camera frame (call on `queue`).
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard armed, let url else { return }
        let host = sampleBuffer.presentationTimeStamp.seconds
        if writer == nil {
            guard !timeline.isPaused,
                  let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            guard dimensions.width > 0, dimensions.height > 0 else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: url)
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                // Fragments keep the camera movie readable after a crash,
                // like the screen recording beside it.
                writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
                let pixels = Double(dimensions.width) * Double(dimensions.height)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height),
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: Int(pixels * 30 * 0.12),
                        AVVideoMaxKeyFrameIntervalKey: 60,
                    ],
                    // Tag (and color-match into) HD video colors, so every
                    // decoder reads skin tones the same way.
                    AVVideoColorPropertiesKey: [
                        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                    ],
                ])
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw CameraCaptureError.unavailable }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? CameraCaptureError.unavailable }
                writer.startSession(atSourceTime: .zero)
                self.writer = writer
                self.input = input
                timeline.start(at: host)
                size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
                onFirstFrame?(host)
            } catch {
                print("[LF Studios] Camera writer failed: \(error)")
                armed = false
                return
            }
        }
        // Paused stretches are cut out, exactly as in the screen recording.
        guard let input, input.isReadyForMoreMediaData,
              let time = timeline.time(at: host), time >= 0,
              lastTime.map({ time > $0 }) ?? true,
              let retimed = RecordingWriterCore.copy(sampleBuffer: sampleBuffer, presentationTime: CMTime(seconds: time, preferredTimescale: 60_000), duration: .invalid)
        else { return }
        if input.append(retimed) { lastTime = time }
    }

    func finish() async -> Result? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.armed = false
                guard let writer = self.writer,
                      let input = self.input,
                      let first = self.timeline.origin,
                      let url = self.url,
                      writer.status == .writing else {
                    self.writer = nil
                    self.input = nil
                    continuation.resume(returning: nil)
                    return
                }
                let size = self.size
                self.writer = nil
                self.input = nil
                input.markAsFinished()
                nonisolated(unsafe) let finishing = writer
                writer.finishWriting {
                    let ok = finishing.status == .completed
                    continuation.resume(returning: ok ? Result(url: url, firstFrameTime: first, size: size) : nil)
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.armed = false
            self.writer?.cancelWriting()
            if let url = self.url { try? FileManager.default.removeItem(at: url) }
            self.writer = nil
            self.input = nil
        }
    }
}

/// The camera preview shown before and while recording, in the shape
/// chosen in the recording bar. Invisible to screen capture — the editor
/// draws the camera from its own file. What it covers of the recording
/// frame is where the camera goes in the video (VideoCameraSetup.swift);
/// drag it outside the frame to get it out of the way.
final class CameraBubbleWindow: NSPanel {
    /// Set once the user drags or resizes it: later placements leave it there.
    private(set) var wasMovedByUser = false
    /// The recording frame (screen points).
    private(set) var frameRect: CGRect = .zero
    private(set) var setup: VideoRecordingCameraSetup
    /// Select size: handles on the edges and corners.
    var showsHandles = false { didSet { bubbleView.showsHandles = showsHandles; updateLabel() } }
    /// Told after the user moves or resizes it (the bar remembers it).
    var changed: ((CameraBubbleWindow) -> Void)?

    private let bubbleView: CameraBubbleView
    private let labelWindow = CameraBubbleLabelWindow()

    init(session: AVCaptureSession, setup: VideoRecordingCameraSetup) {
        self.setup = setup
        bubbleView = CameraBubbleView(session: session)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Floating over any screen: always the dark look.
        appearance = AppAppearance.overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        sharingType = .none
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        bubbleView.frame = NSRect(x: 0, y: 0, width: 168, height: 168)
        bubbleView.autoresizingMask = [.width, .height]
        bubbleView.window_ = self
        contentView = bubbleView
        applyLook()
        setAccessibilityLabel(L("Camera preview"))
    }

    override var canBecomeKey: Bool { false }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        if labelWindow.parent == nil { addChildWindow(labelWindow, ordered: .above) }
        updateLabel()
    }

    override func close() {
        labelWindow.close()
        super.close()
    }

    /// The label goes once recording starts (what's saved is decided then).
    var showsLabel = true { didSet { updateLabel() } }

    /// Puts the preview where the camera goes in `frame`'s video: its
    /// remembered place, or the usual spot.
    func place(around rect: CGRect, on screen: NSScreen) {
        frameRect = rect
        setFrame(Self.kept(VideoCameraPreviewGeometry.previewRect(setup, in: rect), on: screen), display: true)
        updateLabel()
    }

    /// The frame moved or changed size: a preview in the video keeps its
    /// place in it; one moved out of the way stays where it is.
    func update(frame rect: CGRect, on screen: NSScreen) {
        let inside = VideoCameraPreviewGeometry.placement(of: frame, in: frameRect)
        frameRect = rect
        if !wasMovedByUser {
            place(around: rect, on: screen)
        } else if let inside {
            setup.placement = inside
            setFrame(Self.kept(VideoCameraPreviewGeometry.rect(setup, in: rect), on: screen), display: true)
            updateLabel()
        } else {
            updateLabel()
        }
    }

    /// A new shape or roundness: the same center and width, the new shape.
    func apply(_ newSetup: VideoRecordingCameraSetup) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let width = frame.width
        setup = newSetup
        applyLook()
        let aspect = setup.webcam.effectiveAspect
        var rect = CGRect(x: center.x - width / 2, y: center.y - width / aspect / 2, width: width, height: width / aspect)
        if let screen = screen ?? NSScreen.main { rect = Self.kept(rect, on: screen) }
        setFrame(rect, display: true)
        updateLabel()
    }

    /// What's saved for a recording of `frame` now.
    func currentSetup(frame rect: CGRect) -> VideoRecordingCameraSetup {
        VideoCameraPreviewGeometry.setup(setup, preview: frame, frame: rect)
    }

    fileprivate func userChanged(to rect: CGRect) {
        wasMovedByUser = true
        setFrame(rect, display: true)
        if setup.shape == .free { setup.freeAspect = Double(rect.width / max(rect.height, 1)) }
        updateLabel()
        changed?(self)
    }

    fileprivate var keepsShape: Bool { setup.shape != .free }
    fileprivate var aspect: CGFloat { setup.webcam.effectiveAspect }

    private func applyLook() {
        let webcam = setup.webcam
        bubbleView.roundness = webcam.shape == .circle ? 1 : webcam.effectiveRoundness
    }

    private func updateLabel() {
        guard showsLabel, isVisible, frameRect.width > 1 else {
            labelWindow.orderOut(nil)
            return
        }
        labelWindow.show(VideoCameraPreviewGeometry.label(preview: frame, frame: frameRect), below: frame)
    }

    /// Kept on the screen it's on.
    private static func kept(_ rect: CGRect, on screen: NSScreen) -> CGRect {
        let visible = screen.frame
        var rect = rect
        rect.size.width = min(rect.width, visible.width)
        rect.size.height = min(rect.height, visible.height)
        rect.origin.x = min(max(rect.minX, visible.minX), visible.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, visible.minY), visible.maxY - rect.height)
        return rect
    }
}

/// The live picture in its shape, with a light rim; dragging moves it, and
/// with Select size its edges and corners resize it.
private final class CameraBubbleView: NSView {
    weak var window_: CameraBubbleWindow?
    var roundness: Double = 1 { didSet { needsLayout = true } }
    var showsHandles = false { didSet { needsLayout = true; window?.invalidateCursorRects(for: self) } }

    private let preview: AVCaptureVideoPreviewLayer
    private let shapeMask = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private var drag: (handle: VideoCameraHandle, start: CGPoint, frame: CGRect)?

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        let picture = CALayer()
        picture.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        picture.addSublayer(preview)
        picture.mask = shapeMask
        layer?.addSublayer(picture)
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        ring.lineWidth = 3
        layer?.addSublayer(ring)
        handleLayer.fillColor = NSColor.white.cgColor
        handleLayer.strokeColor = NSColor.systemBlue.cgColor
        handleLayer.lineWidth = 1.5
        layer?.addSublayer(handleLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var radius: CGFloat { CGFloat(roundness) * min(bounds.width, bounds.height) / 2 }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.first?.frame = bounds
        preview.frame = bounds
        shapeMask.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let inset = bounds.insetBy(dx: 1.5, dy: 1.5)
        let ringRadius = max(radius - 1.5, 0)
        ring.path = CGPath(roundedRect: inset, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)
        ring.strokeColor = (showsHandles ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.85)).cgColor
        let handles = CGMutablePath()
        if showsHandles {
            for handle in VideoCameraHandle.resizing {
                handles.addEllipse(in: handleRect(handle))
            }
        }
        handleLayer.path = handles
        CATransaction.commit()
    }

    /// A handle's dot, in view coordinates (y up).
    private func handleRect(_ handle: VideoCameraHandle) -> CGRect {
        let unit = handle.unit
        let point = CGPoint(x: bounds.minX + 5 + (bounds.width - 10) * unit.x, y: bounds.maxY - 5 - (bounds.height - 10) * unit.y)
        return CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
    }

    private func handle(at point: CGPoint) -> VideoCameraHandle {
        guard showsHandles else { return .move }
        for handle in VideoCameraHandle.resizing where handleRect(handle).insetBy(dx: -6, dy: -6).contains(point) { return handle }
        // Near an edge: that edge.
        let edge: CGFloat = 8
        if point.x < edge { return .left }
        if point.x > bounds.width - edge { return .right }
        if point.y < edge { return .bottom }
        if point.y > bounds.height - edge { return .top }
        return .move
    }

    override func resetCursorRects() {
        guard showsHandles else { return }
        for handle in VideoCameraHandle.resizing {
            let cursor: NSCursor = handle.isCorner ? .crosshair : ((handle.movesLeft || handle.movesRight) ? .resizeLeftRight : .resizeUpDown)
            addCursorRect(handleRect(handle).insetBy(dx: -6, dy: -6), cursor: cursor)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window = window_ else { return }
        drag = (handle(at: convert(event.locationInWindow, from: nil)), NSEvent.mouseLocation, window.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window = window_ else { return }
        let now = NSEvent.mouseLocation
        // Worked out with y down, like the editor.
        let start = drag.frame
        let flipped = CGRect(x: start.minX, y: -start.maxY, width: start.width, height: start.height)
        let delta = CGSize(width: now.x - drag.start.x, height: -(now.y - drag.start.y))
        let keepsShape = window.keepsShape || event.modifierFlags.contains(.shift)
        let aspect: CGFloat? = keepsShape ? (window.keepsShape ? window.aspect : start.width / max(start.height, 1)) : nil
        let moved = VideoCameraPreviewGeometry.resized(flipped, handle: drag.handle, by: delta, aspect: aspect, minimum: VideoCameraPreviewGeometry.minimumSide)
        window.userChanged(to: CGRect(x: moved.minX, y: -moved.maxY, width: moved.width, height: moved.height))
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
    }
}

/// "Camera: 25% of width, bottom right" under the preview.
private final class CameraBubbleLabelWindow: NSPanel {
    private let text = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        appearance = AppAppearance.overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        sharingType = .none
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let pill = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.88).cgColor
        pill.autoresizingMask = [.width, .height]
        text.font = .systemFont(ofSize: 11, weight: .semibold)
        text.textColor = NSColor.white.withAlphaComponent(0.92)
        text.alignment = .center
        text.frame = NSRect(x: 8, y: 3, width: 184, height: 16)
        text.autoresizingMask = [.width]
        pill.addSubview(text)
        contentView = pill
    }

    override var canBecomeKey: Bool { false }

    func show(_ string: String, below rect: CGRect) {
        text.stringValue = string
        let width = ceil(text.intrinsicContentSize.width) + 20
        setFrame(NSRect(x: rect.midX - width / 2, y: rect.minY - 28, width: width, height: 22), display: true)
        orderFrontRegardless()
    }
}
