import SwiftUI

struct ThemeManagerView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var selectedThemeID: UUID?
    @State private var editedNames: [UUID: String] = [:]

    var body: some View {
        List {
            ForEach(themeStore.themes) { theme in
                HStack(spacing: 8) {
                    Image(systemName: theme.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    TextField("Name", text: binding(for: theme))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            themeStore.rename(theme, to: editedNames[theme.id] ?? theme.name)
                        }
                        .disabled(theme.kind == .builtIn)

                    Spacer()

                    if theme.kind == .builtIn {
                        Text(theme.builtInPreset?.groupName ?? "Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            var mutableSelection = selectedThemeID
                            themeStore.delete(theme, selectedThemeID: &mutableSelection)
                            selectedThemeID = mutableSelection
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete imported theme")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedThemeID = theme.id
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func binding(for theme: SoundTheme) -> Binding<String> {
        Binding {
            editedNames[theme.id] ?? theme.name
        } set: { newValue in
            editedNames[theme.id] = newValue
            themeStore.rename(theme, to: newValue)
        }
    }
}
