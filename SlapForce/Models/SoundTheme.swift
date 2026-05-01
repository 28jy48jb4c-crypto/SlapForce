import Foundation

enum SoundThemeKind: String, Codable {
    case builtIn
    case userImported
}

struct SoundTheme: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var kind: SoundThemeKind
    var fileName: String?
    var builtInPreset: BuiltInSoundPreset?

    var isDeletable: Bool {
        kind == .userImported
    }

    var systemImage: String {
        switch kind {
        case .builtIn:
            return builtInPreset?.systemImage ?? "waveform"
        case .userImported:
            return "folder.badge.plus"
        }
    }

    var sourceDescription: String {
        switch kind {
        case .builtIn:
            return builtInPreset?.sourceDescription ?? "Built-in synth"
        case .userImported:
            return "Imported file"
        }
    }
}

enum BuiltInSoundPreset: String, Codable, CaseIterable {
    case animal
    case female
    case pain
    case surprise
    case comic
    case bassPunch
    case glitch
    case whip

    var displayName: String {
        switch self {
        case .animal: return "Playful Yelp"
        case .female: return "Vocal Hit"
        case .pain: return "Impact Cry"
        case .surprise: return "Shock Pop"
        case .comic: return "Comic Whack"
        case .bassPunch: return "Bass Punch"
        case .glitch: return "Glitch Snap"
        case .whip: return "Whip Crack"
        }
    }

    var systemImage: String {
        switch self {
        case .animal: return "pawprint"
        case .female: return "music.mic"
        case .pain: return "burst"
        case .surprise: return "sparkles"
        case .comic: return "theatermasks"
        case .bassPunch: return "waveform.path"
        case .glitch: return "bolt.horizontal"
        case .whip: return "wind"
        }
    }

    var groupName: String {
        switch self {
        case .animal, .female, .pain, .surprise:
            return "Classic"
        case .comic, .bassPunch, .glitch, .whip:
            return "Expansion"
        }
    }

    var sourceDescription: String {
        switch self {
        case .animal, .female, .pain, .surprise:
            return "Bundle file or synth fallback"
        case .comic, .bassPunch, .glitch, .whip:
            return "Expansion bundle file or synth fallback"
        }
    }

    var bundledBaseName: String {
        switch self {
        case .animal: return "playful-yelp"
        case .female: return "vocal-hit"
        case .pain: return "impact-cry"
        case .surprise: return "shock-pop"
        case .comic: return "comic-whack"
        case .bassPunch: return "bass-punch"
        case .glitch: return "glitch-snap"
        case .whip: return "whip-crack"
        }
    }
}
