import Foundation

/// How caption words come in (Caption style ▸ Animation). None draws the
/// caption as it always was.
enum VideoCaptionAnimation: String, Codable, CaseIterable, Identifiable {
    case none
    case popIn
    case oneWord
    case karaoke
    case typewriter
    case bounce
    case fadeUp
    case highlightBox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L("None")
        case .popIn: return L("Pop-in words")
        case .oneWord: return L("One word at a time")
        case .karaoke: return L("Karaoke fill")
        case .typewriter: return L("Typewriter")
        case .bounce: return L("Bounce")
        case .fadeUp: return L("Fade up")
        case .highlightBox: return L("Highlight box")
        }
    }

    /// Room above and below the words for what moves past them (font sizes).
    var verticalRoom: Double {
        switch self {
        case .bounce: return 0.34
        case .fadeUp: return 0.4
        case .popIn: return 0.12
        default: return 0
        }
    }

    /// The animation colors words itself, so "Highlight words" stands aside.
    var colorsWords: Bool { self == .karaoke || self == .highlightBox }
}

/// One word at a moment.
struct VideoCaptionWordState: Equatable {
    var opacity = 1.0
    var scale = 1.0
    /// Up, in font sizes.
    var lift = 0.0
    /// Karaoke: how much of the word is filled, left to right.
    var fill = 0.0
    /// Typewriter: letters shown (nil: all of them).
    var letters: Int?
}

/// Every word of a caption at a moment.
struct VideoCaptionAnimationFrame: Equatable {
    var animation: VideoCaptionAnimation
    var words: [VideoCaptionWordState]
    /// Highlight box: the word it's on, a fraction past it while it glides
    /// to the next (nil: no box yet).
    var box: Double?
    /// One word at a time: the word shown.
    var single: Int?

    /// Equal frames draw the same picture (states are rounded for this).
    var cacheKey: String {
        var parts = [animation.rawValue, box.map { String(format: "%.3f", $0) } ?? "-", single.map(String.init) ?? "-"]
        for word in words {
            parts.append(String(format: "%.2f,%.2f,%.2f,%.3f,%d", word.opacity, word.scale, word.lift, word.fill, word.letters ?? -1))
        }
        return parts.joined(separator: "|")
    }
}

/// Word timings → how each word looks. Pure arithmetic, so the preview and
/// every export draw the same frame for the same moment.
enum VideoCaptionAnimator {
    struct Timing: Equatable {
        var start: Double
        var end: Double
    }

    static let popDuration = 0.22
    static let bounceDuration = 0.42
    static let fadeDuration = 0.28
    static let glideDuration = 0.12

    /// A caption's words when it has no word times (typed, or translated):
    /// split at spaces, or letter by letter in writing without them.
    static func words(of text: String) -> [String] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if pieces.count == 1, let only = pieces.first, only.count > 1, only.unicodeScalars.contains(where: isUnspaced) {
            return only.map(String.init)
        }
        return pieces
    }

    private static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0x0E00...0x0E7F: return true
        default: return false
        }
    }

    /// Times for words spread evenly over a caption (by length, so long
    /// words take longer).
    static func evenTimings(for words: [String], start: Double, end: Double) -> [Timing] {
        guard !words.isEmpty else { return [] }
        let weights = words.map { Double(max($0.count, 1)) + 1.5 }
        let total = weights.reduce(0, +)
        let span = max(end - start, 0.1)
        var cursor = start
        return weights.map { weight in
            let length = span * weight / total
            defer { cursor += length }
            return Timing(start: cursor, end: cursor + length)
        }
    }

    static func frame(_ animation: VideoCaptionAnimation, timings: [Timing], letters: [Int], at time: Double) -> VideoCaptionAnimationFrame {
        var frame = VideoCaptionAnimationFrame(animation: animation, words: Array(repeating: VideoCaptionWordState(), count: timings.count))
        guard !timings.isEmpty else { return frame }
        let current = timings.lastIndex { $0.start <= time + 0.0001 }
        for (index, timing) in timings.enumerated() {
            let since = time - timing.start
            var state = VideoCaptionWordState()
            switch animation {
            case .none:
                break
            case .popIn:
                if since < 0 {
                    state.opacity = 0
                } else if since < popDuration {
                    let p = since / popDuration
                    state.opacity = min(p / 0.45, 1)
                    state.scale = 0.55 + 0.45 * easeOutBack(p)
                }
            case .oneWord:
                // Each word pops slightly as it replaces the last.
                if since >= 0, since < 0.12 { state.scale = 0.86 + 0.14 * easeOut(since / 0.12) }
            case .karaoke:
                let length = max(timing.end - timing.start, 0.05)
                state.fill = min(max(since / length, 0), 1)
            case .typewriter:
                let count = index < letters.count ? letters[index] : 1
                let length = min(max(timing.end - timing.start, 0.05), 0.05 + 0.045 * Double(count))
                state.letters = since < 0 ? 0 : min(Int((since / length * Double(count)).rounded(.up)), count)
            case .bounce:
                if since >= 0, since < bounceDuration {
                    let p = since / bounceDuration
                    state.lift = 0.3 * abs(sin(p * .pi * 1.5)) * pow(1 - p, 1.6)
                }
            case .fadeUp:
                if since < 0 {
                    state.opacity = 0
                } else if since < fadeDuration {
                    let p = easeOut(since / fadeDuration)
                    state.opacity = p
                    state.lift = -0.38 * (1 - p)
                }
            case .highlightBox:
                break
            }
            frame.words[index] = rounded(state)
        }
        switch animation {
        case .oneWord:
            frame.single = current ?? 0
        case .highlightBox:
            if let current {
                let since = time - timings[current].start
                if current > 0, since < glideDuration {
                    frame.box = Double(current - 1) + easeOut(since / glideDuration)
                } else {
                    frame.box = Double(current)
                }
                frame.box = frame.box.map { ($0 * 32).rounded() / 32 }
            }
        default:
            break
        }
        return frame
    }

    private static func rounded(_ state: VideoCaptionWordState) -> VideoCaptionWordState {
        var state = state
        state.opacity = (state.opacity * 40).rounded() / 40
        state.scale = (state.scale * 100).rounded() / 100
        state.lift = (state.lift * 100).rounded() / 100
        state.fill = (state.fill * 64).rounded() / 64
        return state
    }

    static func easeOut(_ p: Double) -> Double {
        let t = min(max(p, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// Past 1 and back: a pop.
    static func easeOutBack(_ p: Double) -> Double {
        let t = min(max(p, 0), 1) - 1
        let s = 1.9
        return 1 + t * t * ((s + 1) * t + s)
    }
}
