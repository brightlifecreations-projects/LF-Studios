import SwiftUI

// MARK: - Captions in the LF Studios (new) layout (1.17.0)

/// Properties ▸ Captions: the transcript and caption tools, as in the
/// Captions tab.
struct VideoCaptionsPanel: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VideoScriptInspector(model: model)
    }
}
