import Foundation

/// Names an edit from what it changed, for "Undo Delete Zoom" / "Redo Cut".
/// The name is an English identifier ("Delete Zoom"): it's kept with the
/// undo step and never shown as it is. `undoTitle` and `redoTitle` turn it
/// into the whole command in the user's language, since each language words
/// "Undo Delete Zoom" its own way (never "Undo" plus a translated piece).
enum VideoEditDescription {
    static func describe(from old: VideoDemoProject, to new: VideoDemoProject) -> String {
        // Recordings, music, cards, transitions (VideoEditorMedia.swift).
        if let framing = framing(from: old, to: new) { return framing }
        if old.timelineClips != new.timelineClips { return clips(old.timelineClips, new.timelineClips) }
        if old.zoomRegions != new.zoomRegions { return items(old.zoomRegions, new.zoomRegions, names: .zooms) }
        if old.overlayEffects != new.overlayEffects { return overlays(old.overlayEffects, new.overlayEffects) }
        if old.captions != new.captions {
            if old.captions.isEmpty { return "Captions" }
            if new.captions.isEmpty { return "Remove Captions" }
            return items(old.captions, new.captions, names: .captions)
        }
        if old.cameraLayouts != new.cameraLayouts { return items(old.cameraLayouts, new.cameraLayouts, names: .cameraLayouts) }
        if old.clickEvents != new.clickEvents { return items(old.clickEvents, new.clickEvents, names: .clicks) }
        if old.keystrokes != new.keystrokes { return new.keystrokes.count < old.keystrokes.count ? "Hide Shortcut" : "Shortcuts" }
        if old.markers != new.markers {
            if new.markers.count > old.markers.count { return "Add Marker" }
            if new.markers.count < old.markers.count { return "Delete Marker" }
            return "Markers"
        }
        if old.crop != new.crop { return "Crop" }
        if old.audio != new.audio {
            if old.audio.muted != new.audio.muted { return new.audio.muted ? "Mute Video" : "Unmute Video" }
            if old.audio.enhanceVoice != new.audio.enhanceVoice { return "Enhance Voice" }
            return "Sound Change"
        }
        if old.aspectPreset != new.aspectPreset || old.reframe != new.reframe { return "Aspect Ratio" }
        if old.background != new.background || old.backgroundBlur != new.backgroundBlur { return "Background" }
        if old.cursor != new.cursor { return "Cursor Change" }
        if old.importedCamera != new.importedCamera {
            guard let before = old.importedCamera else { return "Add Camera Video" }
            guard let after = new.importedCamera else { return "Remove Camera Video" }
            return before.path == after.path ? "Camera Offset" : "Replace Camera Video"
        }
        if old.webcam != new.webcam { return "Camera Change" }
        if old.captionStyle != new.captionStyle { return "Caption Style" }
        if old.keystrokeStyle != new.keystrokeStyle { return "Shortcut Style" }
        return "Style Change"
    }

    private static func clips(_ old: [VideoDemoTimelineClip], _ new: [VideoDemoTimelineClip]) -> String {
        let oldIDs = old.map(\.id)
        let newIDs = new.map(\.id)
        if Set(oldIDs) == Set(newIDs) {
            if oldIDs != newIDs { return "Move Clip" }
            let pairs = zip(old, new)
            if pairs.contains(where: { $0.speed != $1.speed }) { return "Speed Change" }
            if pairs.contains(where: { $0.muted != $1.muted }) { return pairs.contains(where: { !$0.muted && $1.muted }) ? "Mute Clip" : "Unmute Clip" }
            if pairs.contains(where: { $0.fadeIn != $1.fadeIn || $0.fadeOut != $1.fadeOut }) { return "Fade" }
            return "Trim"
        }
        if new.count == old.count + 1, Set(oldIDs).isSubset(of: Set(newIDs)) { return "Split" }
        if new.count < old.count, Set(newIDs).isSubset(of: Set(oldIDs)) { return old.count - new.count == 1 ? "Delete Clip" : "Delete Clips" }
        let oldLength = old.reduce(0) { $0 + $1.sourceDuration }
        let newLength = new.reduce(0) { $0 + $1.sourceDuration }
        return newLength < oldLength ? "Cut" : "Restore"
    }

    /// The names of the edits to one kind of item, each written out whole.
    private struct ItemNames {
        let add: String
        let addSeveral: String
        let delete: String
        let deleteSeveral: String
        /// Some added and some deleted.
        let mixed: String
        let change: String

        static let zooms = ItemNames(add: "Add Zoom", addSeveral: "Add Zooms", delete: "Delete Zoom", deleteSeveral: "Delete Zooms", mixed: "Zooms", change: "Zoom Change")
        static let captions = ItemNames(add: "Add Caption", addSeveral: "Add Captions", delete: "Delete Caption", deleteSeveral: "Delete Captions", mixed: "Captions", change: "Edit Caption")
        static let cameraLayouts = ItemNames(add: "Add Camera Layout", addSeveral: "Add Camera Layouts", delete: "Delete Camera Layout", deleteSeveral: "Delete Camera Layouts", mixed: "Camera Layouts", change: "Camera Layout Change")
        static let clicks = ItemNames(add: "Add Click", addSeveral: "Add Clicks", delete: "Delete Click", deleteSeveral: "Delete Clicks", mixed: "Clicks", change: "Move Click")
    }

    private static func items<Item: Identifiable & Equatable>(_ old: [Item], _ new: [Item], names: ItemNames) -> String {
        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        let added = newIDs.subtracting(oldIDs).count
        let removed = oldIDs.subtracting(newIDs).count
        if added > 0, removed == 0 { return added == 1 ? names.add : names.addSeveral }
        if removed > 0, added == 0 { return removed == 1 ? names.delete : names.deleteSeveral }
        if added > 0 { return names.mixed }
        return names.change
    }

    private static func overlays(_ old: [VideoDemoOverlayEffect], _ new: [VideoDemoOverlayEffect]) -> String {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let added = new.filter { oldByID[$0.id] == nil }
        let removed = old.filter { newByID[$0.id] == nil }
        if added.count == 1, removed.isEmpty { return addName(added[0].kind) }
        if removed.count == 1, added.isEmpty { return deleteName(removed[0].kind) }
        if !added.isEmpty || !removed.isEmpty { return removed.count > 1 ? "Delete Annotations" : "Annotations" }
        guard let changed = new.first(where: { oldByID[$0.id] != $0 }), let before = oldByID[changed.id] else { return "Annotation Change" }
        if before.text != changed.text { return "Edit Text" }
        if before.time != changed.time || before.duration != changed.duration || before.layer != changed.layer { return moveName(changed.kind) }
        if before.x != changed.x || before.y != changed.y || before.width != changed.width || before.height != changed.height || before.arrowEnds != changed.arrowEnds {
            return moveName(changed.kind)
        }
        return styleName(changed.kind)
    }

    // The annotation names spelled out (not from the kind's title, which is
    // in the user's language).

    private static func addName(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .text: return "Add Text"
        case .arrow: return "Add Arrow"
        case .highlight: return "Add Highlight"
        case .blur: return "Add Blur"
        case .spotlight: return "Add Spotlight"
        case .image: return "Add Image"
        }
    }

    private static func deleteName(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .text: return "Delete Text"
        case .arrow: return "Delete Arrow"
        case .highlight: return "Delete Highlight"
        case .blur: return "Delete Blur"
        case .spotlight: return "Delete Spotlight"
        case .image: return "Delete Image"
        }
    }

    private static func moveName(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .text: return "Move Text"
        case .arrow: return "Move Arrow"
        case .highlight: return "Move Highlight"
        case .blur: return "Move Blur"
        case .spotlight: return "Move Spotlight"
        case .image: return "Move Image"
        }
    }

    private static func styleName(_ kind: VideoDemoOverlayEffectKind) -> String {
        switch kind {
        case .text: return "Text Style"
        case .arrow: return "Arrow Style"
        case .highlight: return "Highlight Style"
        case .blur: return "Blur Style"
        case .spotlight: return "Spotlight Style"
        case .image: return "Image Style"
        }
    }
}

// MARK: - Undo and Redo, in the user's language

extension VideoEditDescription {
    /// The Undo command for the edit named `name`: "Undo Delete Zoom" (just
    /// "Undo" when there's no name, or one without its own phrase).
    static func undoTitle(_ name: String?) -> String {
        name.flatMap { commands(for: $0)?.undo } ?? L("Undo")
    }

    /// The Redo command for the edit named `name`: "Redo Delete Zoom".
    static func redoTitle(_ name: String?) -> String {
        name.flatMap { commands(for: $0)?.redo } ?? L("Redo")
    }

    /// Several items moved or deleted at once ("Move 3 Items"): the verb
    /// and the count.
    private static func severalItems(_ name: String) -> (verb: String, count: Int)? {
        let words = name.split(separator: " ")
        guard words.count == 3, words[2] == "Items", let count = Int(words[1]) else { return nil }
        return (String(words[0]), count)
    }

    /// Every edit name the editor gives (here, in VideoEditorModel,
    /// VideoEditorFeatures, VideoEditorMedia, and VideoEditorSelection), as
    /// the whole Undo and Redo commands.
    static func commands(for name: String) -> (undo: String, redo: String)? {
        if let several = severalItems(name) {
            let count = several.count
            switch several.verb {
            case "Move": return (L("Undo Move \(count) Items"), L("Redo Move \(count) Items"))
            case "Delete": return (L("Undo Delete \(count) Items"), L("Redo Delete \(count) Items"))
            default: return nil
            }
        }
        switch name {
        // Recordings, music, cards, transitions.
        // The timeline's tracks and tools (1.14.0).
        case "Text Change": return (L("Undo Text Change"), L("Redo Text Change"))
        case "Clear Beats": return (L("Undo Clear Beats"), L("Redo Clear Beats"))
        case "Detect Beats": return (L("Undo Detect Beats"), L("Redo Detect Beats"))
        case "Normalize Loudness": return (L("Undo Normalize Loudness"), L("Redo Normalize Loudness"))
        case "Speed Curve": return (L("Undo Speed Curve"), L("Redo Speed Curve"))
        case "Change Pitch": return (L("Undo Change Pitch"), L("Redo Change Pitch"))
        case "Keep Pitch": return (L("Undo Keep Pitch"), L("Redo Keep Pitch"))
        case "Speed": return (L("Undo Speed"), L("Redo Speed"))
        case "Animation": return (L("Undo Animation"), L("Redo Animation"))
        case "Blend": return (L("Undo Blend"), L("Redo Blend"))
        case "Remove Background": return (L("Undo Remove Background"), L("Redo Remove Background"))
        case "Keep Background": return (L("Undo Keep Background"), L("Redo Keep Background"))
        case "Chroma Key": return (L("Undo Chroma Key"), L("Redo Chroma Key"))
        case "Mask": return (L("Undo Mask"), L("Redo Mask"))
        case "Add Keyframe": return (L("Undo Add Keyframe"), L("Redo Add Keyframe"))
        case "Remove Keyframe": return (L("Undo Remove Keyframe"), L("Redo Remove Keyframe"))
        case "Keyframe Easing": return (L("Undo Keyframe Easing"), L("Redo Keyframe Easing"))
        case "Freeze Frame": return (L("Undo Freeze Frame"), L("Redo Freeze Frame"))
        case "Group": return (L("Undo Group"), L("Redo Group"))
        case "Ungroup": return (L("Undo Ungroup"), L("Redo Ungroup"))
        case "Paste": return (L("Undo Paste"), L("Redo Paste"))
        case "Record Voiceover": return (L("Undo Record Voiceover"), L("Redo Record Voiceover"))
        case "Reverse": return (L("Undo Reverse"), L("Redo Reverse"))
        case "Add to Track": return (L("Undo Add to Track"), L("Redo Add to Track"))
        case "Fill": return (L("Undo Fill"), L("Redo Fill"))
        case "Fit": return (L("Undo Fit"), L("Redo Fit"))
        case "Mirror": return (L("Undo Mirror"), L("Redo Mirror"))
        case "Rotate": return (L("Undo Rotate"), L("Redo Rotate"))
        case "Slip Clip": return (L("Undo Slip Clip"), L("Redo Slip Clip"))
        case "Split Clip": return (L("Undo Split Clip"), L("Redo Split Clip"))
        case "Trim Clip": return (L("Undo Trim Clip"), L("Redo Trim Clip"))
        case "Clip Change": return (L("Undo Clip Change"), L("Redo Clip Change"))
        case "Turn On Clip": return (L("Undo Turn On Clip"), L("Redo Turn On Clip"))
        case "Turn Off Clip": return (L("Undo Turn Off Clip"), L("Redo Turn Off Clip"))
        // The Library's media (VideoMediaBin.swift).
        case "Import Media": return (L("Undo Import Media"), L("Redo Import Media"))
        case "Rename Media": return (L("Undo Rename Media"), L("Redo Rename Media"))
        case "Move Media": return (L("Undo Move Media"), L("Redo Move Media"))
        case "New Folder": return (L("Undo New Folder"), L("Redo New Folder"))
        case "Rename Folder": return (L("Undo Rename Folder"), L("Redo Rename Folder"))
        case "Delete Folder": return (L("Undo Delete Folder"), L("Redo Delete Folder"))
        case "Delete from Project": return (L("Undo Delete from Project"), L("Redo Delete from Project"))
        case "Replace Media": return (L("Undo Replace Media"), L("Redo Replace Media"))
        case "Extract Audio": return (L("Undo Extract Audio"), L("Redo Extract Audio"))
        case "Add Recording": return (L("Undo Add Recording"), L("Redo Add Recording"))
        case "Remove Recording": return (L("Undo Remove Recording"), L("Redo Remove Recording"))
        case "Move Recording": return (L("Undo Move Recording"), L("Redo Move Recording"))
        case "Add Music": return (L("Undo Add Music"), L("Redo Add Music"))
        case "Add Audio": return (L("Undo Add Audio"), L("Redo Add Audio"))
        case "Remove Audio": return (L("Undo Remove Audio"), L("Redo Remove Audio"))
        case "Split Audio": return (L("Undo Split Audio"), L("Redo Split Audio"))
        case "Move Audio": return (L("Undo Move Audio"), L("Redo Move Audio"))
        case "Trim Audio": return (L("Undo Trim Audio"), L("Redo Trim Audio"))
        case "Sync Audio by Sound": return (L("Undo Sync Audio by Sound"), L("Redo Sync Audio by Sound"))
        case "Audio Track Change": return (L("Undo Audio Track Change"), L("Redo Audio Track Change"))
        case "Remove Music": return (L("Undo Remove Music"), L("Redo Remove Music"))
        case "Replace Music": return (L("Undo Replace Music"), L("Redo Replace Music"))
        case "Music Change": return (L("Undo Music Change"), L("Redo Music Change"))
        case "Add Intro Card": return (L("Undo Add Intro Card"), L("Redo Add Intro Card"))
        case "Remove Intro Card": return (L("Undo Remove Intro Card"), L("Redo Remove Intro Card"))
        case "Add Outro Card": return (L("Undo Add Outro Card"), L("Redo Add Outro Card"))
        case "Remove Outro Card": return (L("Undo Remove Outro Card"), L("Redo Remove Outro Card"))
        case "Title Card": return (L("Undo Title Card"), L("Redo Title Card"))
        case "Transitions": return (L("Undo Transitions"), L("Redo Transitions"))
        case "Click Sounds": return (L("Undo Click Sounds"), L("Redo Click Sounds"))
        case "Caption Translation": return (L("Undo Caption Translation"), L("Redo Caption Translation"))
        case "Intro and Outro": return (L("Undo Intro and Outro"), L("Redo Intro and Outro"))
        case "Start Over": return (L("Undo Start Over"), L("Redo Start Over"))
        // Clips and cuts.
        case "Move Clip": return (L("Undo Move Clip"), L("Redo Move Clip"))
        case "Speed Change": return (L("Undo Speed Change"), L("Redo Speed Change"))
        case "Mute Clip": return (L("Undo Mute Clip"), L("Redo Mute Clip"))
        case "Unmute Clip": return (L("Undo Unmute Clip"), L("Redo Unmute Clip"))
        case "Mute Part": return (L("Undo Mute Part"), L("Redo Mute Part"))
        case "Unmute Part": return (L("Undo Unmute Part"), L("Redo Unmute Part"))
        case "Fade": return (L("Undo Fade"), L("Redo Fade"))
        case "Trim": return (L("Undo Trim"), L("Redo Trim"))
        case "Split": return (L("Undo Split"), L("Redo Split"))
        case "Delete Clip": return (L("Undo Delete Clip"), L("Redo Delete Clip"))
        case "Delete Clips": return (L("Undo Delete Clips"), L("Redo Delete Clips"))
        case "Cut": return (L("Undo Cut"), L("Redo Cut"))
        case "Restore": return (L("Undo Restore"), L("Redo Restore"))
        case "Restore Cut": return (L("Undo Restore Cut"), L("Redo Restore Cut"))
        case "Restore Cuts": return (L("Undo Restore Cuts"), L("Redo Restore Cuts"))
        case "Speed Up Idle": return (L("Undo Speed Up Idle"), L("Redo Speed Up Idle"))
        case "Split at Markers": return (L("Undo Split at Markers"), L("Redo Split at Markers"))
        // Markers.
        case "Add Marker": return (L("Undo Add Marker"), L("Redo Add Marker"))
        case "Rename Marker": return (L("Undo Rename Marker"), L("Redo Rename Marker"))
        case "Delete Marker": return (L("Undo Delete Marker"), L("Redo Delete Marker"))
        case "Markers": return (L("Undo Markers"), L("Redo Markers"))
        // Words and pauses.
        case "Transcribe": return (L("Undo Transcribe"), L("Redo Transcribe"))
        case "Cut Word": return (L("Undo Cut Word"), L("Redo Cut Word"))
        case "Cut Words": return (L("Undo Cut Words"), L("Redo Cut Words"))
        case "Restore Word": return (L("Undo Restore Word"), L("Redo Restore Word"))
        case "Restore Words": return (L("Undo Restore Words"), L("Redo Restore Words"))
        case "Restore Pause": return (L("Undo Restore Pause"), L("Redo Restore Pause"))
        case "Shorten Pause": return (L("Undo Shorten Pause"), L("Redo Shorten Pause"))
        case "Shorten Pauses": return (L("Undo Shorten Pauses"), L("Redo Shorten Pauses"))
        case "Remove Ums": return (L("Undo Remove Ums"), L("Redo Remove Ums"))
        // Zooms.
        case "Add Zoom": return (L("Undo Add Zoom"), L("Redo Add Zoom"))
        case "Add Zooms": return (L("Undo Add Zooms"), L("Redo Add Zooms"))
        case "Delete Zoom": return (L("Undo Delete Zoom"), L("Redo Delete Zoom"))
        case "Delete Zooms": return (L("Undo Delete Zooms"), L("Redo Delete Zooms"))
        case "Zooms": return (L("Undo Zooms"), L("Redo Zooms"))
        case "Zoom Change": return (L("Undo Zoom Change"), L("Redo Zoom Change"))
        case "Zoom Level for All": return (L("Undo Zoom Level for All"), L("Redo Zoom Level for All"))
        case "Auto Zoom": return (L("Undo Auto Zoom"), L("Redo Auto Zoom"))
        case "Remove All Zooms": return (L("Undo Remove All Zooms"), L("Redo Remove All Zooms"))
        // Annotations.
        case "Add Text": return (L("Undo Add Text"), L("Redo Add Text"))
        case "Add Arrow": return (L("Undo Add Arrow"), L("Redo Add Arrow"))
        case "Add Highlight": return (L("Undo Add Highlight"), L("Redo Add Highlight"))
        case "Add Blur": return (L("Undo Add Blur"), L("Redo Add Blur"))
        case "Add Spotlight": return (L("Undo Add Spotlight"), L("Redo Add Spotlight"))
        case "Add Image": return (L("Undo Add Image"), L("Redo Add Image"))
        case "Delete Text": return (L("Undo Delete Text"), L("Redo Delete Text"))
        case "Delete Arrow": return (L("Undo Delete Arrow"), L("Redo Delete Arrow"))
        case "Delete Highlight": return (L("Undo Delete Highlight"), L("Redo Delete Highlight"))
        case "Delete Blur": return (L("Undo Delete Blur"), L("Redo Delete Blur"))
        case "Delete Spotlight": return (L("Undo Delete Spotlight"), L("Redo Delete Spotlight"))
        case "Delete Image": return (L("Undo Delete Image"), L("Redo Delete Image"))
        case "Move Text": return (L("Undo Move Text"), L("Redo Move Text"))
        case "Move Arrow": return (L("Undo Move Arrow"), L("Redo Move Arrow"))
        case "Move Highlight": return (L("Undo Move Highlight"), L("Redo Move Highlight"))
        case "Move Blur": return (L("Undo Move Blur"), L("Redo Move Blur"))
        case "Move Spotlight": return (L("Undo Move Spotlight"), L("Redo Move Spotlight"))
        case "Move Image": return (L("Undo Move Image"), L("Redo Move Image"))
        case "Text Style": return (L("Undo Text Style"), L("Redo Text Style"))
        case "Arrow Style": return (L("Undo Arrow Style"), L("Redo Arrow Style"))
        case "Highlight Style": return (L("Undo Highlight Style"), L("Redo Highlight Style"))
        case "Blur Style": return (L("Undo Blur Style"), L("Redo Blur Style"))
        case "Spotlight Style": return (L("Undo Spotlight Style"), L("Redo Spotlight Style"))
        case "Image Style": return (L("Undo Image Style"), L("Redo Image Style"))
        case "Edit Text": return (L("Undo Edit Text"), L("Redo Edit Text"))
        case "Delete Annotations": return (L("Undo Delete Annotations"), L("Redo Delete Annotations"))
        case "Annotations": return (L("Undo Annotations"), L("Redo Annotations"))
        case "Annotation Change": return (L("Undo Annotation Change"), L("Redo Annotation Change"))
        // Captions.
        case "Captions": return (L("Undo Captions"), L("Redo Captions"))
        case "Remove Captions": return (L("Undo Remove Captions"), L("Redo Remove Captions"))
        case "Add Caption": return (L("Undo Add Caption"), L("Redo Add Caption"))
        case "Add Captions": return (L("Undo Add Captions"), L("Redo Add Captions"))
        case "Delete Caption": return (L("Undo Delete Caption"), L("Redo Delete Caption"))
        case "Delete Captions": return (L("Undo Delete Captions"), L("Redo Delete Captions"))
        case "Edit Caption": return (L("Undo Edit Caption"), L("Redo Edit Caption"))
        case "Caption Style": return (L("Undo Caption Style"), L("Redo Caption Style"))
        case "Move Caption": return (L("Undo Move Caption"), L("Redo Move Caption"))
        case "Move Captions": return (L("Undo Move Captions"), L("Redo Move Captions"))
        // Camera layouts.
        case "Add Camera Layout": return (L("Undo Add Camera Layout"), L("Redo Add Camera Layout"))
        case "Add Camera Layouts": return (L("Undo Add Camera Layouts"), L("Redo Add Camera Layouts"))
        case "Delete Camera Layout": return (L("Undo Delete Camera Layout"), L("Redo Delete Camera Layout"))
        case "Delete Camera Layouts": return (L("Undo Delete Camera Layouts"), L("Redo Delete Camera Layouts"))
        case "Camera Layouts": return (L("Undo Camera Layouts"), L("Redo Camera Layouts"))
        case "Camera Layout Change": return (L("Undo Camera Layout Change"), L("Redo Camera Layout Change"))
        // Clicks and shortcuts.
        case "Add Click": return (L("Undo Add Click"), L("Redo Add Click"))
        case "Add Clicks": return (L("Undo Add Clicks"), L("Redo Add Clicks"))
        case "Delete Click": return (L("Undo Delete Click"), L("Redo Delete Click"))
        case "Delete Clicks": return (L("Undo Delete Clicks"), L("Redo Delete Clicks"))
        case "Clicks": return (L("Undo Clicks"), L("Redo Clicks"))
        case "Move Click": return (L("Undo Move Click"), L("Redo Move Click"))
        case "Hide Shortcut": return (L("Undo Hide Shortcut"), L("Redo Hide Shortcut"))
        case "Shortcuts": return (L("Undo Shortcuts"), L("Redo Shortcuts"))
        case "Shortcut Style": return (L("Undo Shortcut Style"), L("Redo Shortcut Style"))
        case "Move Shortcuts": return (L("Undo Move Shortcuts"), L("Redo Move Shortcuts"))
        // The look.
        case "Crop": return (L("Undo Crop"), L("Redo Crop"))
        case "Mute Video": return (L("Undo Mute Video"), L("Redo Mute Video"))
        case "Unmute Video": return (L("Undo Unmute Video"), L("Redo Unmute Video"))
        case "Enhance Voice": return (L("Undo Enhance Voice"), L("Redo Enhance Voice"))
        case "Sound Change": return (L("Undo Sound Change"), L("Redo Sound Change"))
        case "Aspect Ratio": return (L("Undo Aspect Ratio"), L("Redo Aspect Ratio"))
        case "Hide Track": return (L("Undo Hide Track"), L("Redo Hide Track"))
        case "Show Track": return (L("Undo Show Track"), L("Redo Show Track"))
        case "Mute Track": return (L("Undo Mute Track"), L("Redo Mute Track"))
        case "Unmute Track": return (L("Undo Unmute Track"), L("Redo Unmute Track"))
        case "Lock Track": return (L("Undo Lock Track"), L("Redo Lock Track"))
        case "Unlock Track": return (L("Undo Unlock Track"), L("Redo Unlock Track"))
        case "Collapse Track": return (L("Undo Collapse Track"), L("Redo Collapse Track"))
        case "Background": return (L("Undo Background"), L("Redo Background"))
        case "Cursor Change": return (L("Undo Cursor Change"), L("Redo Cursor Change"))
        case "Camera Change": return (L("Undo Camera Change"), L("Redo Camera Change"))
        case "Style Change": return (L("Undo Style Change"), L("Redo Style Change"))
        case "Reset Look": return (L("Undo Reset Look"), L("Redo Reset Look"))
        case "Apply Preset": return (L("Undo Apply Preset"), L("Redo Apply Preset"))
        case "Apply My Style": return (L("Undo Apply My Style"), L("Redo Apply My Style"))
        case "Auto-Zoom On": return (L("Undo Auto-Zoom On"), L("Redo Auto-Zoom On"))
        case "Add Typing Zooms": return (L("Undo Add Typing Zooms"), L("Redo Add Typing Zooms"))
        case "Add Loupe": return (L("Undo Add Loupe"), L("Redo Add Loupe"))
        case "Change Loupe": return (L("Undo Change Loupe"), L("Redo Change Loupe"))
        case "Fit Zooms Around Camera": return (L("Undo Fit Zooms Around Camera"), L("Redo Fit Zooms Around Camera"))
        case "Speed Up Typing": return (L("Undo Speed Up Typing"), L("Redo Speed Up Typing"))
        case "Keep Face Centered": return (L("Undo Keep Face Centered"), L("Redo Keep Face Centered"))
        case "Face Tracking": return (L("Undo Face Tracking"), L("Redo Face Tracking"))
        case "Hide Camera During Silences": return (L("Undo Hide Camera During Silences"), L("Redo Hide Camera During Silences"))
        case "Auto Adjust Camera Color": return (L("Undo Auto Adjust Camera Color"), L("Redo Auto Adjust Camera Color"))
        case "Podcast Mode On": return (L("Undo Podcast Mode On"), L("Redo Podcast Mode On"))
        case "Podcast Mode Off": return (L("Undo Podcast Mode Off"), L("Redo Podcast Mode Off"))
        case "Adapt to This Ratio": return (L("Undo Adapt to This Ratio"), L("Redo Adapt to This Ratio"))
        case "Blur Private Info": return (L("Undo Blur Private Info"), L("Redo Blur Private Info"))
        case "Auto-Zoom Off": return (L("Undo Auto-Zoom Off"), L("Redo Auto-Zoom Off"))
        case "Add Camera Video": return (L("Undo Add Camera Video"), L("Redo Add Camera Video"))
        case "Replace Camera Video": return (L("Undo Replace Camera Video"), L("Redo Replace Camera Video"))
        case "Remove Camera Video": return (L("Undo Remove Camera Video"), L("Redo Remove Camera Video"))
        case "Camera Offset": return (L("Undo Camera Offset"), L("Redo Camera Offset"))
        default: return nil
        }
    }
}
