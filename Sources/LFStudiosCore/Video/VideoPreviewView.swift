import AppKit
import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

/// Draws the live preview into a Metal view with the export renderer, at
/// the view's own pixel size. Idle when nothing changes; 60fps while
/// playing or editing.
@MainActor
final class VideoPreviewRenderer: NSObject, MTKViewDelegate {
    private weak var model: VideoEditorModel?
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext
    private let renderer = VideoFrameRenderer()
    /// Where the live frame put the caption and the keys (their drag handles).
    let textLayout = VideoTextLayoutStore()
    private var lastBuffer: CVPixelBuffer?
    private var lastBufferTime: Double = 0
    /// The camera frame composed with `lastBuffer` (kept so a missed lookup
    /// never blinks the bubble).
    private var lastCameraFrame: VideoCameraFrame?
    /// The newest frame of each video track above the main track.
    private var lastLayerFrames: [UUID: CIImage] = [:]
    private var playingTime: Double?
    private var dirty = true
    private var peekImage: CIImage?
    private var peekTime: Double?
    private var peekInFlight = false
    private var pendingPeek: Double?
    private lazy var peekGenerator: AVAssetImageGenerator? = {
        guard let model else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: model.project.sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        return generator
    }()

    init(model: VideoEditorModel) {
        self.model = model
        device = VideoRenderContext.device
        queue = device?.makeCommandQueue()
        context = VideoRenderContext.makeContext()
        super.init()
    }

    func invalidate() {
        dirty = true
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated { dirty = true }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { drawFrame(in: view) }
    }

    private func drawFrame(in view: MTKView) {
        guard let model, model.isReady else { return }
        let hostTime = CACurrentMediaTime()
        if let frame = model.playback.frame(forHostTime: hostTime) {
            lastBuffer = frame.buffer
            lastBufferTime = frame.time
            if let camera = model.playback.cameraPicture(at: frame.time) {
                lastCameraFrame = camera
            }
            lastLayerFrames.merge(model.playback.layerFrames(at: frame.time)) { _, new in new }
            dirty = true
        }
        // While playing, redraw every display refresh at the exact playback
        // time: the camera and cursor move at the screen's rate even when
        // the recording has fewer frames.
        if model.isPlaying, let time = model.playback.itemTime(forHostTime: hostTime) {
            playingTime = time
            dirty = true
        } else {
            playingTime = nil
        }
        guard dirty else { return }
        let size = view.drawableSize
        guard size.width > 2, size.height > 2,
              let drawable = view.currentDrawable,
              let commandBuffer = queue?.makeCommandBuffer() else { return }
        dirty = false

        let image = compose(model: model, size: size)
        let destination = CIRenderDestination(
            width: Int(size.width),
            height: Int(size.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )
        destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        _ = try? context.startTask(toRender: image, from: CGRect(origin: .zero, size: size), to: destination, at: .zero)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func compose(model: VideoEditorModel, size: CGSize) -> CIImage {
        var options = VideoFrameRenderer.Options(frameRate: 60)
        // A big recording on the move: skip the costliest passes.
        options.draft = model.previewPrefersSpeed
        options.solidOverlay = Self.editedOverlay(model)
        options.webcamFrame = model.plan.webcam == nil ? nil : lastCameraFrame?.image
        options.webcamMask = model.plan.webcam == nil ? nil : lastCameraFrame?.mask
        options.layerFrames = lastLayerFrames
        var source = lastBuffer.map { CIImage(cvPixelBuffer: $0) }
        var time = playingTime ?? lastBufferTime
        if model.isCropping {
            options.rawSource = true
        } else if let peek = model.trimPeekSourceTime {
            requestPeek(peek)
            if let peekImage { source = peekImage }
            options.cameraOverride = .rest
            options.sourceTimeOverride = peek
            time = model.clock.time
        } else if model.isAimingZoom {
            options.cameraOverride = .rest
        }
        // The held side of a dissolve (VideoEditorMedia.swift).
        if !model.isCropping, model.trimPeekSourceTime == nil {
            options.transitionFrame = model.heldFrame(at: time)
        }
        options.recordsTextLayout = true
        let image = renderer.render(source: source, timelineTime: time, plan: model.plan, outputSize: size, options: options)
        if renderer.textLayout != textLayout.layout {
            textLayout.layout = renderer.textLayout
        }
        return image
    }

    /// The annotation being edited while paused — shown fully, fades aside.
    private static func editedOverlay(_ model: VideoEditorModel) -> UUID? {
        guard !model.isPlaying, case .overlay(let id) = model.selection else { return nil }
        return id
    }

    /// Source frames for clip-edge drags (possibly outside the current
    /// edit), fetched one at a time, newest request wins.
    private func requestPeek(_ time: Double) {
        if let peekTime, abs(peekTime - time) < 0.001 { return }
        // Several recordings: the frame comes from whichever one is there.
        if let model, model.project.hasAppendedSources {
            let image = model.media.frames(for: model.project).cachedImage(at: time) { [weak self] in
                MainActor.assumeIsolated { self?.dirty = true }
            }
            if let image {
                peekImage = image
                peekTime = time
            }
            return
        }
        guard !peekInFlight else {
            pendingPeek = time
            return
        }
        guard let generator = peekGenerator else { return }
        peekInFlight = true
        let requested = time
        generator.generateCGImageAsynchronously(for: CMTime(seconds: requested, preferredTimescale: 600)) { [weak self] image, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.peekInFlight = false
                if let image {
                    self.peekImage = CIImage(cgImage: image)
                    self.peekTime = requested
                    self.dirty = true
                }
                if let pending = self.pendingPeek {
                    self.pendingPeek = nil
                    self.requestPeek(pending)
                }
            }
        }
    }

    /// The frame at a timeline moment, decoded directly rather than from
    /// playback — offscreen windows (editor snapshots) never show Metal.
    func still(size: CGSize, at time: Double) -> NSImage? {
        guard let model, size.width > 2, size.height > 2 else { return nil }
        // From whichever recording is at that moment (VideoEditorMedia.swift).
        let location = model.sourceFrameLocation(at: model.sourceTime(forTimeline: time))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: location.url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try? generator.copyCGImage(at: CMTime(seconds: location.time, preferredTimescale: 600), actualTime: nil)
        var options = VideoFrameRenderer.Options(frameRate: 60)
        options.rawSource = model.isCropping
        options.solidOverlay = Self.editedOverlay(model)
        // Like the live preview: aiming a zoom shows the whole frame.
        if model.isAimingZoom && !model.isCropping { options.cameraOverride = .rest }
        if model.plan.webcam != nil, let camera = model.playback.cameraPicture(at: time) {
            options.webcamFrame = camera.image
            options.webcamMask = camera.mask
        }
        if let request = model.plan.heldFrameRequest(at: time) {
            options.transitionFrame = model.media.frames(for: model.project).image(at: request.sourceTime)
        }
        options.layerFrames = VideoLayerStills.frames(for: model.plan.layers, at: time)
        let pixels = CGSize(width: size.width * 2, height: size.height * 2)
        let image = renderer.render(source: frame.map { CIImage(cgImage: $0) }, timelineTime: time, plan: model.plan, outputSize: pixels, options: options)
        guard let cgImage = context.createCGImage(image, from: CGRect(origin: .zero, size: pixels), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// The frame under the playhead, rendered at `size`.
    func snapshot(size: CGSize) -> NSImage? {
        guard let model else { return nil }
        var options = VideoFrameRenderer.Options(frameRate: 60)
        options.webcamFrame = lastCameraFrame?.image
        options.webcamMask = lastCameraFrame?.mask
        options.layerFrames = lastLayerFrames
        let image = renderer.render(source: lastBuffer.map { CIImage(cvPixelBuffer: $0) }, timelineTime: lastBufferTime, plan: model.plan, outputSize: size, options: options)
        guard let cgImage = context.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
}

/// The Metal surface.
struct VideoPreviewSurface: NSViewRepresentable {
    let renderer: VideoPreviewRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.wantsLayer = true
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.isOpaque = true
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        renderer.invalidate()
    }
}

// MARK: - Stage (preview + direct manipulation)

struct VideoStageView: View {
    @ObservedObject var model: VideoEditorModel
    /// Snapshot tests: draw the preview as a still image.
    nonisolated(unsafe) static var drawsStills = false

    var body: some View {
        GeometryReader { proxy in
            let canvas = model.isCropping ? model.project.sourceSize : model.project.canvasSize()
            // The player's zoom (Fit, 150%…): larger than the space, it scrolls.
            let zoom = model.isCropping ? 1 : max(model.previewZoom, 1)
            let base = Self.fit(canvas, in: proxy.size)
            let fitted = CGSize(width: (base.width * zoom).rounded(), height: (base.height * zoom).rounded())
            ScrollView(zoom > 1.001 ? [.horizontal, .vertical] : [], showsIndicators: zoom > 1.001) {
            ZStack {
                Group {
                    if Self.drawsStills, let still = model.previewRenderer.still(size: fitted, at: model.clock.time) {
                        Image(nsImage: still).resizable()
                    } else {
                        VideoPreviewSurface(renderer: model.previewRenderer)
                    }
                }
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)

                if model.isCropping {
                    VideoCropOverlay(model: model, viewSize: fitted)
                        .frame(width: fitted.width, height: fitted.height)
                } else {
                    VideoStageInteractionLayer(model: model, clock: model.clock, textLayout: model.previewRenderer.textLayout, viewSize: fitted)
                        .frame(width: fitted.width, height: fitted.height)
                    // Over the preview only: the renderer never sees it.
                    if let layout = model.phoneOverlay, model.canShowPhoneOverlay {
                        VideoPhoneOverlayView(layout: layout, size: fitted)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .frame(width: max(proxy.size.width, fitted.width), height: max(proxy.size.height, fitted.height))
            }
        }
    }

    static func fit(_ canvas: CGSize, in available: CGSize) -> CGSize {
        guard canvas.width > 0, canvas.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / canvas.width, available.height / canvas.height)
        return CGSize(width: floor(canvas.width * scale), height: floor(canvas.height * scale))
    }
}

/// Handles drawn over the preview: the zoom target rectangle while aiming,
/// and selection frames for callouts. Maps through the live camera so
/// handles stay glued to what's drawn.
struct VideoStageInteractionLayer: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var clock: VideoDemoPlaybackClock
    @ObservedObject var textLayout: VideoTextLayoutStore
    let viewSize: CGSize

    @State private var aimOrigin: (id: UUID, centerX: Double, centerY: Double, scale: Double)?
    @State private var overlayOrigin: VideoDemoOverlayEffect?
    /// The camera being dragged: by which handle, and where it is now.
    @State private var bubbleDrag: (handle: VideoCameraHandle, rect: CGRect)?
    @State private var hoveringBubble = false
    /// A press on the picture: whether its first moment was handled, and
    /// the annotation it landed on (nil: empty picture).
    @State private var pressStarted = false
    @State private var pressedOverlay: UUID?
    /// The last click on an annotation, to spot a double-click.
    @State private var lastClick: (id: UUID, time: Date)?

    /// The layer's own coordinates (it doesn't move while things on it do).
    static let space = "video-stage"

    /// The canvas the scene is laid out on (the recording's own shape when
    /// reframing a narrow output).
    private var canvas: CGSize { model.plan.canvasSize }
    private var stage: CGRect { (model.project.reframeActive ? model.project.reframeScene() : model.project).stageRect(in: canvas) }
    /// Width of the whole scene in view points, and how far the reframing
    /// window has panned into it.
    private var sceneWidth: CGFloat {
        model.plan.reframe == nil ? viewSize.width : viewSize.height * canvas.width / max(canvas.height, 1)
    }
    private var sceneOffset: CGFloat {
        model.plan.reframe?.windowOrigin(at: clock.time, sceneWidth: sceneWidth) ?? 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Clicking an annotation selects it (drag to move, double-click
            // text to type); clicking the picture around them plays/pauses.
            Color.clear
                .contentShape(Rectangle())
                .gesture(pictureGesture)
                .accessibilityElement()
                .accessibilityLabel(L("Video preview"))
                .accessibilityHint(L("Plays or pauses. Use Option-arrow keys to select what's on the timeline."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.togglePlay() }
                .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                    guard pressedOverlay == nil else { return }
                    if case .active(let point) = phase, annotation(at: point) != nil {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }

            if model.isAimingZoom, let zoom = model.selectedZoom {
                aimRectangle(zoom)
            } else if let zoom = model.selectedZoom, zoom.followsCursor, !model.isPlaying {
                followBadge
            }

            // A locked track's things stay put here too (its header's Lock).
            if !model.isPlaying, !model.isTrackLocked(.annotations), let overlay = model.selectedOverlay, isVisibleNow(overlay) {
                if overlay.kind == .image {
                    // Pinned to the frame (VideoImageOverlays.swift).
                    VideoImageOverlayHandles(model: model, effect: overlay, viewSize: viewSize)
                } else {
                    overlayFrame(overlay)
                }
            }

            // The selected item on a track above the main track (1.14.0).
            if !model.isPlaying, let item = model.selectedLayerItem, item.isShowing(at: clock.time),
               let track = model.project.layerTrackIndex(of: item.id), !model.isTrackLocked(.layer(model.project.layerTracks[track].id)) {
                VideoLayerItemHandles(model: model, item: item, viewSize: viewSize)
            }

            // The bubble handle only where the bubble is (not during a full
            // camera, side by side, or hidden stretch).
            if let webcam = model.plan.webcam, webcam.visible, !model.isAimingZoom, !model.isTrackLocked(.camera), model.plan.showsBubble(at: clock.time), model.plan.hasCameraFootage(at: clock.time) {
                webcamHandle(webcam)
            }

            // Split screen's divider, while the split shows in full.
            if let webcam = model.plan.webcam, !model.isAimingZoom, !model.isPlaying, !model.isTrackLocked(.camera), showsSplit(webcam) {
                splitDivider(webcam.effectiveSplit)
            }

            // Captions and shortcut keys, dragged anywhere (VideoTextHandles.swift).
            if !model.isPlaying, !model.isAimingZoom, !model.isTrackLocked(.captions) || !model.isTrackLocked(.keys) {
                VideoTextHandles(model: model, layout: textLayout.layout, viewSize: viewSize)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    // MARK: Picking annotations

    /// The frontmost annotation on screen under `point` (view points).
    func annotation(at point: CGPoint) -> VideoDemoOverlayEffect? {
        // Drawn lowest lane first: the last drawn is in front.
        for overlay in model.plan.overlays.reversed() where overlay.effect.onCamera != true && overlay.isShowing(at: clock.time, margin: 0.05) {
            let effect = overlay.effect
            if VideoAnnotationHitTest.hits(effect, rect: viewRect(effect), arrow: effect.kind == .arrow ? viewArrow(effect) : nil, point: point) {
                return effect
            }
        }
        return nil
    }

    /// The frontmost item of the tracks above the main track under `point`.
    func layerItem(at point: CGPoint) -> VideoLayerItem? {
        for layer in model.plan.layers.reversed() where layer.item.isShowing(at: clock.time) {
            let r = layer.item.rect(in: viewSize)
            let box = CGRect(x: r.minX, y: viewSize.height - r.maxY, width: r.width, height: r.height)
            // Measured along its own sides when it's turned.
            let along = VideoImageOverlayHandles.unturn(CGSize(width: point.x - box.midX, height: point.y - box.midY), by: layer.item.rotation)
            if abs(along.width) <= box.width / 2, abs(along.height) <= box.height / 2 { return layer.item }
        }
        return nil
    }

    private var pictureGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !pressStarted {
                    pressStarted = true
                    pressedOverlay = nil
                    if annotation(at: value.startLocation) == nil, let item = layerItem(at: value.startLocation) {
                        // An item on a track above the main track: selected;
                        // its box moves it (VideoTransformBox.swift).
                        if model.isPlaying { model.pause() }
                        model.selection = .layer(item.id)
                        pressedOverlay = item.id
                        overlayOrigin = nil
                    } else if let effect = annotation(at: value.startLocation) {
                        pressedOverlay = effect.id
                        overlayOrigin = effect
                        // Editing needs a still frame.
                        if model.isPlaying { model.pause() }
                        model.selection = .overlay(effect.id)
                        if effect.kind == .text, let last = lastClick, last.id == effect.id,
                           value.time.timeIntervalSince(last.time) < NSEvent.doubleClickInterval {
                            // Double-click: type in it.
                            model.textEditRequest += 1
                        }
                    }
                }
                guard let origin = overlayOrigin, pressedOverlay == origin.id,
                      hypot(value.translation.width, value.translation.height) > 2 else { return }
                NSCursor.closedHand.set()
                model.updateOverlay(origin.id, coalesce: "move-\(origin.id)") { overlay in
                    // Images move across the frame; the rest across the recording.
                    let across = overlay.kind == .image ? viewSize : CGSize(width: stage.width * viewScale, height: stage.height * viewScale)
                    overlay.x = origin.x + Double(value.translation.width / max(across.width, 1))
                    overlay.y = origin.y + Double(value.translation.height / max(across.height, 1))
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 2
                if let id = pressedOverlay {
                    model.endGesture()
                    lastClick = moved ? nil : (id, value.time)
                } else {
                    lastClick = nil
                    if !moved {
                        if model.selection != .none {
                            model.selection = .none
                        } else {
                            model.togglePlay()
                        }
                    }
                }
                pressStarted = false
                pressedOverlay = nil
                overlayOrigin = nil
            }
    }

    /// An annotation's box on the view (top-left origin).
    private func viewRect(_ effect: VideoDemoOverlayEffect) -> CGRect {
        if effect.kind == .image {
            // Pinned to the frame, not the recording (VideoImageOverlays.swift).
            let r = effect.imageRect(in: viewSize)
            return CGRect(x: r.minX, y: viewSize.height - r.maxY, width: r.width, height: r.height)
        }
        // A blur that follows something: where it is now.
        let effect = effect.placed(atSource: model.plan.sourceTime(forTimelineTime: clock.time))
        let center = viewPoint(CGPoint(x: stage.minX + stage.width * CGFloat(effect.x), y: stage.minY + stage.height * CGFloat(effect.y)))
        let width = stage.width * CGFloat(effect.width) * viewScale
        let height = stage.height * CGFloat(effect.height) * viewScale
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// An arrow's tail and head on the view.
    private func viewArrow(_ effect: VideoDemoOverlayEffect) -> (tail: CGPoint, head: CGPoint) {
        let ends = effect.arrowPoints
        func view(_ p: CGPoint) -> CGPoint { viewPoint(CGPoint(x: stage.minX + stage.width * p.x, y: stage.minY + stage.height * p.y)) }
        return (view(ends.tail), view(ends.head))
    }

    // MARK: Camera bubble

    /// The bubble's rect in view points (top-left origin).
    private func bubbleRect(_ settings: VideoWebcamSettings) -> CGRect {
        let rect = VideoFrameRenderer.webcamRect(settings, outputSize: viewSize, cameraScale: camera.scale)
        return CGRect(x: rect.minX, y: viewSize.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Split screen's divider

    /// The split is on screen in full (not on its way in or out).
    private func showsSplit(_ webcam: VideoWebcamSettings) -> Bool {
        guard webcam.visible, model.plan.hasCameraFootage(at: clock.time) else { return false }
        if let region = model.plan.cameraLayout(at: clock.time) {
            return region.layout == .sideBySide && webcam.split != nil && region.progress >= 0.999
        }
        return webcam.effectiveLayout == .split
    }

    /// Drag it between 30/70 and 70/30; one ⌘Z per drag.
    private func splitDivider(_ split: VideoWebcamSettings.Split) -> some View {
        let size = viewSize
        let sideBySide = VideoSplitLayout.isSideBySide(split, in: size)
        let position = VideoSplitLayout.dividerPosition(split, in: size)
        let grab: CGFloat = 14
        return ZStack {
            Capsule()
                .fill(Color.white.opacity(0.92))
                .overlay(Capsule().strokeBorder(VideoEditorTheme.camera, lineWidth: 1.5))
                .frame(width: sideBySide ? 6 : 44, height: sideBySide ? 44 : 6)
        }
        .frame(width: sideBySide ? grab : size.width, height: sideBySide ? size.height : grab)
        .contentShape(Rectangle())
        .offset(x: sideBySide ? position * size.width - grab / 2 : 0, y: sideBySide ? 0 : position * size.height - grab / 2)
        .onHover { inside in (inside ? (sideBySide ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown) : NSCursor.arrow).set() }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let at = sideBySide ? value.location.x / max(size.width, 1) : value.location.y / max(size.height, 1)
                    let share = VideoSplitLayout.share(forDivider: at, split, in: size)
                    model.setStyle(coalesce: "split-divider") {
                        $0.webcam.split = $0.webcam.effectiveSplit
                        $0.webcam.split?.cameraShare = share
                    }
                }
                .onEnded { _ in model.endGesture() }
        )
        .help(L("Drag to change how much of the video the camera takes"))
        .accessibilityLabel(L("Split screen divider"))
    }

    /// The camera after a drag: moved or resized (a fixed shape keeps its
    /// ratio, Free doesn't unless ⇧ is held), snapped to the video's
    /// corners, edges and center, kept inside the video.
    private func draggedBubble(_ rect: CGRect, handle: VideoCameraHandle, by delta: CGSize, settings: VideoWebcamSettings, shift: Bool) -> CGRect {
        let bounds = CGRect(origin: .zero, size: viewSize)
        let keepsShape = settings.shape != .free || shift
        let aspect: CGFloat? = keepsShape ? (settings.shape == .free ? rect.width / max(rect.height, 1) : settings.effectiveAspect) : nil
        let moved = VideoCameraPreviewGeometry.resized(rect, handle: handle, by: delta, aspect: aspect, minimum: 24, within: bounds)
        let short = min(viewSize.width, viewSize.height)
        let snapped = VideoCameraPreviewGeometry.snapped(moved, handle: handle, in: bounds, margin: (short * 0.04).rounded(), threshold: 7, keepsShape: keepsShape)
        return VideoCameraPreviewGeometry.resized(snapped, handle: .move, by: .zero, aspect: nil, minimum: 24, within: bounds)
    }

    /// Drag the camera anywhere (it snaps to the corners, edges and
    /// center); drag its edges and corners to resize it. One undo per drag.
    private func webcamHandle(_ settings: VideoWebcamSettings) -> some View {
        let rect = bubbleRect(settings)
        let shown = bubbleDrag?.rect ?? rect
        let radius = VideoFrameRenderer.webcamCornerRadius(settings, rect: shown)
        let showsHandles = !model.isPlaying && (hoveringBubble || bubbleDrag != nil || model.inspectorTab == .camera)
        return ZStack(alignment: .topLeading) {
            if bubbleDrag != nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(VideoEditorTheme.camera.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(VideoEditorTheme.camera, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
                    .allowsHitTesting(false)
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(bubbleDrag != nil ? 0.95 : (hoveringBubble ? 0.7 : 0)), lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(bubbleDrag != nil ? 0.12 : 0.001)))
                .frame(width: rect.width, height: rect.height)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .offset(x: rect.minX, y: rect.minY)
                .onHover { inside in
                    hoveringBubble = inside
                    (inside ? NSCursor.openHand : NSCursor.arrow).set()
                }
                .onTapGesture {
                    model.selection = .none
                    model.inspectorTab = .camera
                }
                .gesture(bubbleGesture(.move, rect: rect, settings: settings))
                .help(L("Camera — drag to move it, drag its edges to resize it, click for options"))
            if showsHandles, bubbleDrag == nil {
                // The bubble turns (1.14.0): the knob above it.
                VideoRotateKnob(rect: rect, label: L("Turn the camera"), turned: { degrees in
                    model.setStyle(coalesce: "camera-rotate") { $0.webcam.rotation = degrees }
                }, ended: { model.endGesture() })
            }
            if showsHandles {
                ForEach(VideoCameraHandle.resizing, id: \.self) { handle in
                    let unit = handle.unit
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(VideoEditorTheme.camera, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .offset(x: shown.minX + shown.width * unit.x - 11, y: shown.minY + shown.height * unit.y - 11)
                        .onHover { inside in
                            if inside { (handle.isCorner ? NSCursor.crosshair : ((handle.movesLeft || handle.movesRight) ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown)).set() } else { NSCursor.arrow.set() }
                        }
                        .gesture(bubbleGesture(handle, rect: rect, settings: settings))
                        .accessibilityLabel(L("Resize the camera"))
                }
            }
        }
    }

    private func bubbleGesture(_ handle: VideoCameraHandle, rect: CGRect, settings: VideoWebcamSettings) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let shift = NSEvent.modifierFlags.contains(.shift)
                bubbleDrag = (handle, draggedBubble(rect, handle: handle, by: value.translation, settings: settings, shift: shift))
                if handle == .move { NSCursor.closedHand.set() }
            }
            .onEnded { value in
                let shift = NSEvent.modifierFlags.contains(.shift)
                let final = draggedBubble(rect, handle: handle, by: value.translation, settings: settings, shift: shift)
                bubbleDrag = nil
                guard final != rect else { return }
                // Saved unshrunk: Shrink while zoomed makes it smaller now.
                let full = VideoFrameRenderer.webcamRect(settings, outputSize: viewSize).width
                let grow = full / max(rect.width, 1)
                let size = viewSize
                var placement = VideoCameraPreviewGeometry.placement(ofVideoRect: final, in: size)
                placement.width *= Double(grow)
                let freeAspect = settings.shape == .free && handle != .move ? Double(final.width / max(final.height, 1)) : nil
                model.setStyle {
                    $0.webcam.placement = placement
                    if let freeAspect { $0.webcam.freeAspect = freeAspect }
                }
                if handle == .move { NSCursor.openHand.set() }
            }
    }

    private func isVisibleNow(_ effect: VideoDemoOverlayEffect) -> Bool {
        // The span the renderer draws, after cuts.
        guard let span = model.plan.overlays.first(where: { $0.effect.id == effect.id }) else { return false }
        return span.isShowing(at: clock.time, margin: 0.05)
    }

    // MARK: Geometry

    private var camera: VideoCameraState {
        model.isAimingZoom ? .rest : model.cameraState(at: clock.time)
    }

    /// Canvas point (top-left) → view point.
    private func viewPoint(_ p: CGPoint) -> CGPoint {
        let s = CGFloat(camera.scale)
        let x = ((p.x / canvas.width - CGFloat(camera.centerX)) * s + 0.5) * sceneWidth - sceneOffset
        let y = ((p.y / canvas.height - CGFloat(camera.centerY)) * s + 0.5) * viewSize.height
        return CGPoint(x: x, y: y)
    }

    private var viewScale: CGFloat { sceneWidth / max(canvas.width, 1) * CGFloat(camera.scale) }

    // MARK: Zoom aiming

    private func aimRectangle(_ zoom: VideoZoomRegion) -> some View {
        let s = zoom.scale
        let crop = model.project.crop.normalized
        let inCrop = crop.map(CGPoint(x: zoom.focusX, y: zoom.focusY))
        let focusX = (stage.minX + stage.width * inCrop.x) / canvas.width
        let focusY = (stage.minY + stage.height * inCrop.y) / canvas.height
        let cx = VideoCameraState.clampedCenter(Double(focusX), scale: s)
        let cy = VideoCameraState.clampedCenter(Double(focusY), scale: s)
        let width = sceneWidth / CGFloat(s)
        let height = viewSize.height / CGFloat(s)
        let rect = CGRect(x: CGFloat(cx) * sceneWidth - width / 2 - sceneOffset, y: CGFloat(cy) * viewSize.height - height / 2, width: width, height: height)

        return ZStack(alignment: .topLeading) {
            // Dim everything outside the shot.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: viewSize))
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .background(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.magnifyingglass")
                        Text(VideoEditorModel.formatScale(zoom.scale))
                            .monospacedDigit()
                        Text(L("· drag to aim"))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .padding(8)
                }
                .offset(x: rect.minX, y: rect.minY)
                .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if aimOrigin?.id != zoom.id {
                                aimOrigin = (zoom.id, cx, cy, s)
                            }
                            guard let origin = aimOrigin else { return }
                            NSCursor.closedHand.set()
                            let newX = VideoCameraState.clampedCenter(origin.centerX + Double(value.translation.width / sceneWidth), scale: origin.scale)
                            let newY = VideoCameraState.clampedCenter(origin.centerY + Double(value.translation.height / viewSize.height), scale: origin.scale)
                            // Canvas-normalized center → recording-normalized focus.
                            let inCrop = CGPoint(
                                x: (CGFloat(newX) * canvas.width - stage.minX) / max(stage.width, 1),
                                y: (CGFloat(newY) * canvas.height - stage.minY) / max(stage.height, 1)
                            )
                            let focus = crop.unmap(inCrop)
                            model.updateZoom(zoom.id, coalesce: "aim-\(zoom.id)") { region in
                                region.focusX = Double(focus.x)
                                region.focusY = Double(focus.y)
                            }
                        }
                        .onEnded { _ in
                            aimOrigin = nil
                            model.endGesture()
                            NSCursor.openHand.set()
                        }
                )

            // Corner handles resize the shot (= zoom level).
            ForEach(0..<4, id: \.self) { corner in
                let isRight = corner == 1 || corner == 3
                let isBottom = corner >= 2
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .contentShape(Circle().inset(by: -8))
                    .offset(x: (isRight ? rect.maxX : rect.minX) - 6, y: (isBottom ? rect.maxY : rect.minY) - 6)
                    .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if aimOrigin?.id != zoom.id {
                                    aimOrigin = (zoom.id, cx, cy, s)
                                }
                                guard let origin = aimOrigin else { return }
                                let originWidth = sceneWidth / CGFloat(origin.scale)
                                let delta = (isRight ? value.translation.width : -value.translation.width) * 2
                                let newWidth = max(originWidth + delta, sceneWidth / CGFloat(VideoZoomRegion.scaleRange.upperBound))
                                let newScale = Double(sceneWidth / newWidth)
                                model.updateZoom(zoom.id, coalesce: "aim-\(zoom.id)") { region in
                                    region.scale = min(max(newScale, VideoZoomRegion.scaleRange.lowerBound), VideoZoomRegion.scaleRange.upperBound)
                                }
                            }
                            .onEnded { _ in
                                aimOrigin = nil
                                model.endGesture()
                            }
                    )
            }
        }
    }

    private var followBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.motionlines")
            Text(L("Camera follows your cursor"))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .padding(12)
        .allowsHitTesting(false)
    }

    // MARK: Overlay editing

    @ViewBuilder
    private func overlayFrame(_ effect: VideoDemoOverlayEffect) -> some View {
        if effect.kind == .arrow {
            arrowHandles(effect)
        } else {
            boxFrame(effect)
        }
    }

    /// An arrow: a dashed guide along it and a handle at each end — drag
    /// the head or the tail to point it anywhere (the arrow itself drags
    /// through the picture below).
    private func arrowHandles(_ effect: VideoDemoOverlayEffect) -> some View {
        let ends = viewArrow(effect)
        let stageWidthInView = stage.width * viewScale
        let stageHeightInView = stage.height * viewScale
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: ends.tail)
                path.addLine(to: ends.head)
            }
            .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .allowsHitTesting(false)

            ForEach(0..<2, id: \.self) { index in
                let isHead = index == 1
                let point = isHead ? ends.head : ends.tail
                Circle()
                    .fill(isHead ? Color.accentColor : Color.white)
                    .overlay(Circle().stroke(isHead ? Color.white : Color.accentColor, lineWidth: 1.5))
                    .frame(width: 12, height: 12)
                    .contentShape(Circle().inset(by: -7))
                    .offset(x: point.x - 6, y: point.y - 6)
                    .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                    .help(isHead ? L("Drag to point the arrow") : L("Drag to move where the arrow starts"))
                    .accessibilityLabel(isHead ? L("Arrow head") : L("Arrow tail"))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if overlayOrigin?.id != effect.id { overlayOrigin = effect }
                                guard let origin = overlayOrigin else { return }
                                let points = origin.arrowPoints
                                let start = isHead ? points.head : points.tail
                                let moved = CGPoint(
                                    x: start.x + value.translation.width / max(stageWidthInView, 1),
                                    y: start.y + value.translation.height / max(stageHeightInView, 1)
                                )
                                model.updateOverlay(effect.id, coalesce: "arrow-end-\(effect.id)") { overlay in
                                    overlay.setArrow(tail: isHead ? points.tail : moved, head: isHead ? moved : points.head)
                                }
                            }
                            .onEnded { _ in
                                overlayOrigin = nil
                                model.endGesture()
                            }
                    )
            }
        }
    }

    private func boxFrame(_ effect: VideoDemoOverlayEffect) -> some View {
        let rect = viewRect(effect)
        let stageWidthInView = stage.width * viewScale
        let stageHeightInView = stage.height * viewScale

        return ZStack(alignment: .topLeading) {
            // Text turns (1.14.0): the knob above it.
            if effect.kind == .text {
                VideoRotateKnob(rect: rect, label: L("Turn the text"), turned: { degrees in
                    model.updateOverlay(effect.id, coalesce: "text-rotate-\(effect.id)") { $0.rotation = degrees }
                }, ended: { model.endGesture() })
            }
            // Just the outline: pressing inside reaches the picture layer,
            // which moves it (and spots a double-click on text).
            Group {
                if effect.kind == .spotlight, effect.shape == .ellipse {
                    Ellipse().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.degrees(effect.kind == .text ? effect.rotation ?? 0 : 0))
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)

            ForEach(0..<4, id: \.self) { corner in
                let isRight = corner == 1 || corner == 3
                let isBottom = corner >= 2
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .contentShape(Circle().inset(by: -7))
                    .offset(x: (isRight ? rect.maxX : rect.minX) - 5.5, y: (isBottom ? rect.maxY : rect.minY) - 5.5)
                    .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if overlayOrigin?.id != effect.id { overlayOrigin = effect }
                                guard let origin = overlayOrigin else { return }
                                let sx: Double = isRight ? 1 : -1
                                let sy: Double = isBottom ? 1 : -1
                                let fixedX = origin.x - sx * origin.width / 2
                                let fixedY = origin.y - sy * origin.height / 2
                                var movingX = origin.x + sx * origin.width / 2 + Double(value.translation.width / max(stageWidthInView, 1))
                                var movingY = origin.y + sy * origin.height / 2 + Double(value.translation.height / max(stageHeightInView, 1))
                                movingX = sx > 0 ? max(movingX, fixedX + 0.04) : min(movingX, fixedX - 0.04)
                                movingY = sy > 0 ? max(movingY, fixedY + 0.03) : min(movingY, fixedY - 0.03)
                                model.updateOverlay(effect.id, coalesce: "resize-\(effect.id)") { overlay in
                                    overlay.x = (fixedX + movingX) / 2
                                    overlay.y = (fixedY + movingY) / 2
                                    overlay.width = abs(movingX - fixedX)
                                    overlay.height = abs(movingY - fixedY)
                                }
                            }
                            .onEnded { _ in
                                overlayOrigin = nil
                                model.endGesture()
                            }
                    )
            }
        }
    }
}
