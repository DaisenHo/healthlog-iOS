import SwiftUI

/// #126 P2 (server v1.40.2) — how far back the Coach may read. The server
/// treats it as a real limit for every answer; `All` (its default) is none.
struct CoachWindowCard: View {
    let store: AICoachSettingsStore

    var body: some View {
        HLSettingsCard(icon: "calendar", title: "settings.coach.window.title") {
            VStack(alignment: .leading, spacing: HLSpace.sm) {
                HStack(spacing: HLSpace.md) {
                    Text("settings.coach.window.pickerLabel")
                        .font(.hlSubhead.weight(.semibold))
                        .foregroundStyle(HLText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if store.isWindowWriteInFlight {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                    Picker(
                        String(localized: "settings.coach.window.pickerLabel"),
                        selection: Binding(
                            get: { store.coachDefaultWindow ?? .allTime },
                            set: { newValue in Task { await store.setCoachDefaultWindow(newValue) } }
                        )
                    ) {
                        ForEach(CoachDefaultWindow.allCases) { window in
                            Text(LocalizedStringKey(window.labelKey)).tag(window)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(store.coachDefaultWindow == nil || store.isWindowWriteInFlight)
                    .accessibilityIdentifier("settings.coach.windowPicker")
                }
                Text("settings.coach.window.description")
                    .font(.hlCaption)
                    .foregroundStyle(HLText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await store.loadCoachDefaultWindow() }
    }
}
