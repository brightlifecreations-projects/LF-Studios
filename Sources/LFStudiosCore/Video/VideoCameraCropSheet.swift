import AppKit
import CoreImage
import SwiftUI

/// Camera ▸ Crop…: drag a frame over the camera picture to choose the part
/// the bubble shows. Shown mirrored when the bubble is, so the frame sits
/// where you'd expect; stored on the unmirrored picture
/// (`VideoWebcamSettings.crop`).
struct VideoCameraCropSheet: View {
    @ObservedObject var model: VideoEditorModel
    let picture: NSImage
    @Environment(\.dismiss) private var dismiss

    /// The crop as shown (mirrored when the bubble is), y down.
    @State private var shown = VideoCropRect.full
    @State private var dragOrigin: VideoCropRect?

    private enum Grip: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private var mirrored: Bool { model.project.webcam.mirror }

    var body: some View {
        let size = Self.fit(picture.size, in: CGSize(width: 520, height: 360))
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Crop the camera"))
                .font(.system(size: 15, weight: .semibold))
            Text(L("Drag the frame, or its corners, over the part of the camera picture the bubble should show."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                Image(nsImage: picture)
                    .resizable()
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .frame(width: size.width, height: size.height)
                cropFrame(in: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .coordinateSpace(name: "camera-crop")

            HStack {
                Button(L("Reset")) { shown = .full }
                    .disabled(shown.isFull)
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Done")) {
                    let stored = Self.flipped(shown, mirrored)
                    model.setStyle { $0.webcam.crop = stored.isFull ? nil : stored }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: size.width + 40)
        .onAppear {
            shown = Self.flipped(model.project.webcam.effectiveCrop ?? .full, mirrored)
        }
    }

    /// Between the stored crop (unmirrored picture) and the one shown.
    static func flipped(_ crop: VideoCropRect, _ mirrored: Bool) -> VideoCropRect {
        guard mirrored else { return crop }
        return VideoCropRect(x: 1 - crop.x - crop.width, y: crop.y, width: crop.width, height: crop.height)
    }

    static func fit(_ picture: CGSize, in box: CGSize) -> CGSize {
        guard picture.width > 0, picture.height > 0 else { return box }
        let scale = min(box.width / picture.width, box.height / picture.height)
        return CGSize(width: (picture.width * scale).rounded(), height: (picture.height * scale).rounded())
    }

    private func cropFrame(in size: CGSize) -> some View {
        let rect = CGRect(x: shown.x * size.width, y: shown.y * size.height, width: shown.width * size.width, height: shown.height * size.height)
        return ZStack(alignment: .topLeading) {
            // Everything outside the frame, dimmed.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .background(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(moveGesture(in: size))
                .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }

            ForEach(Grip.allCases, id: \.self) { grip in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .offset(x: (grip == .topLeft || grip == .bottomLeft ? rect.minX : rect.maxX) - 6,
                            y: (grip == .topLeft || grip == .topRight ? rect.minY : rect.maxY) - 6)
                    .gesture(resizeGesture(grip, in: size))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("camera-crop"))
            .onChanged { value in
                let origin = dragOrigin ?? shown
                if dragOrigin == nil { dragOrigin = shown }
                var moved = origin
                moved.x = min(max(origin.x + Double(value.translation.width / size.width), 0), 1 - origin.width)
                moved.y = min(max(origin.y + Double(value.translation.height / size.height), 0), 1 - origin.height)
                shown = moved
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(_ grip: Grip, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("camera-crop"))
            .onChanged { value in
                let origin = dragOrigin ?? shown
                if dragOrigin == nil { dragOrigin = shown }
                let dx = Double(value.translation.width / size.width)
                let dy = Double(value.translation.height / size.height)
                let side = VideoCropRect.minimumSide
                var minX = origin.x, minY = origin.y, maxX = origin.x + origin.width, maxY = origin.y + origin.height
                switch grip {
                case .topLeft: minX = min(max(minX + dx, 0), maxX - side); minY = min(max(minY + dy, 0), maxY - side)
                case .topRight: maxX = max(min(maxX + dx, 1), minX + side); minY = min(max(minY + dy, 0), maxY - side)
                case .bottomLeft: minX = min(max(minX + dx, 0), maxX - side); maxY = max(min(maxY + dy, 1), minY + side)
                case .bottomRight: maxX = max(min(maxX + dx, 1), minX + side); maxY = max(min(maxY + dy, 1), minY + side)
                }
                shown = VideoCropRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

extension VideoEditorModel {
    /// The camera picture at the playhead, for the crop sheet.
    func cameraStill() -> NSImage? {
        guard let frame = playback.cameraPicture(at: clock.time)?.image else { return nil }
        let extent = frame.extent
        guard extent.width > 1, extent.height > 1,
              let cgImage = CIContext().createCGImage(frame, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: extent.size)
    }
}
