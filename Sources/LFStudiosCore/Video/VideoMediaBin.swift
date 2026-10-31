import SwiftUI

/// The media bin (filled in the next step).
struct VideoMediaBinView: View {
    @ObservedObject var model: VideoEditorModel
    let kinds: Set<VideoMediaKind>

    var body: some View { Color.clear }
}

enum VideoMediaKind: String, Codable, CaseIterable {
    case video, image, audio
}
