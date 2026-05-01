import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [SoundTheme] = []
    @Published var importError: String?

    private let metadataFileName = "themes.json"
    private let fileManager = FileManager.default

    init() {
        loadThemes()
    }

    var themesDirectory: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("SlapForce", isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    var builtInOverrideDirectory: URL {
        themesDirectory.appendingPathComponent("BuiltInOverrides", isDirectory: true)
    }

    func theme(for id: UUID?) -> SoundTheme {
        if let id, let theme = themes.first(where: { $0.id == id }) {
            return theme
        }
        return themes.first!
    }

    func fileURL(for theme: SoundTheme) -> URL? {
        if let fileName = theme.fileName {
            return themesDirectory.appendingPathComponent(fileName)
        }
        guard let preset = theme.builtInPreset else { return nil }
        return builtInSourceURL(for: preset)
    }

    func importAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a sound file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio, .audio]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        do {
            try importAudioFile(at: sourceURL)
        } catch {
            importError = error.localizedDescription
        }
    }

    func importAudioFile(at sourceURL: URL) throws {
        try ensureDirectories()

        // With App Sandbox enabled, a user-selected file is readable during this
        // operation. Copying it into Application Support makes future launches
        // independent from the original location.
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let copiedName = "\(UUID().uuidString).\(ext)"
        let destination = themesDirectory.appendingPathComponent(copiedName)
        try fileManager.copyItem(at: sourceURL, to: destination)

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let theme = SoundTheme(id: UUID(), name: displayName, kind: .userImported, fileName: copiedName, builtInPreset: nil)
        themes.append(theme)
        saveThemes()
    }

    func rename(_ theme: SoundTheme, to name: String) {
        guard let index = themes.firstIndex(where: { $0.id == theme.id }) else { return }
        themes[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.name : name
        saveThemes()
    }

    func delete(_ theme: SoundTheme, selectedThemeID: inout UUID?) {
        guard theme.isDeletable, let index = themes.firstIndex(where: { $0.id == theme.id }) else { return }
        if let fileURL = fileURL(for: theme) {
            try? fileManager.removeItem(at: fileURL)
        }
        themes.remove(at: index)
        if selectedThemeID == theme.id {
            selectedThemeID = themes.first?.id
        }
        saveThemes()
    }

    private func loadThemes() {
        let builtIns = BuiltInSoundPreset.allCases.map {
            SoundTheme(id: stableID(for: $0.rawValue), name: $0.displayName, kind: .builtIn, fileName: nil, builtInPreset: $0)
        }

        do {
            try ensureDirectories()
            let metadataURL = themesDirectory.appendingPathComponent(metadataFileName)
            let userThemes: [SoundTheme]
            if fileManager.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                userThemes = try JSONDecoder().decode([SoundTheme].self, from: data)
            } else {
                userThemes = []
            }
            themes = builtIns + userThemes
        } catch {
            importError = error.localizedDescription
            themes = builtIns
        }
    }

    private func saveThemes() {
        do {
            try ensureDirectories()
            let metadataURL = themesDirectory.appendingPathComponent(metadataFileName)
            let userThemes = themes.filter { $0.kind == .userImported }
            let data = try JSONEncoder().encode(userThemes)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: builtInOverrideDirectory, withIntermediateDirectories: true)
    }

    private func builtInSourceURL(for preset: BuiltInSoundPreset) -> URL? {
        let extensions = ["wav", "m4a", "mp3", "aif", "aiff"]

        for ext in extensions {
            let overrideURL = builtInOverrideDirectory.appendingPathComponent("\(preset.bundledBaseName).\(ext)")
            if fileManager.fileExists(atPath: overrideURL.path) {
                return overrideURL
            }
        }

        guard let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("BuiltInThemes", isDirectory: true) else {
            return nil
        }
        for ext in extensions {
            let bundleURL = resourceRoot.appendingPathComponent("\(preset.bundledBaseName).\(ext)")
            if fileManager.fileExists(atPath: bundleURL.path) {
                return bundleURL
            }
        }
        return nil
    }

    private func stableID(for string: String) -> UUID {
        // Fixed UUIDs keep user selection stable across launches.
        switch string {
        case BuiltInSoundPreset.animal.rawValue: return UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        case BuiltInSoundPreset.female.rawValue: return UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        case BuiltInSoundPreset.pain.rawValue: return UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        case BuiltInSoundPreset.surprise.rawValue: return UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        case BuiltInSoundPreset.comic.rawValue: return UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        case BuiltInSoundPreset.bassPunch.rawValue: return UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        case BuiltInSoundPreset.glitch.rawValue: return UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        default: return UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        }
    }
}
