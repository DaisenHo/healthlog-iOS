import SwiftUI

struct AccountLanguageCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(BackendAvailability.self) private var backend

    var body: some View {
        HLSettingsCard(
            icon: "globe",
            title: "settings.language.title",
            footer: "settings.language.description"
        ) {
            Picker("settings.language.title", selection: selection) {
                if settings.accountLanguage == nil {
                    Text("settings.language.unsynced").tag(AccountLanguage?.none)
                }
                ForEach(AccountLanguage.allCases, id: \.self) { language in
                    Text(verbatim: language.nativeName).tag(Optional(language))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.isSavingAccountLanguage || !backend.isReachable)
            .accessibilityIdentifier("settings.account.language.picker")

            if settings.isSavingAccountLanguage {
                ProgressView("settings.language.saving")
            }
            if !backend.isOnline || settings.accountLanguageNotice == .onlineRequired {
                Text("settings.language.onlineRequired")
                    .font(.hlCaption)
                    .foregroundStyle(HLText.secondary)
                    .accessibilityIdentifier("settings.account.language.offline")
            } else if settings.accountLanguageNotice == .saveFailed {
                Text("settings.language.saveFailed")
                    .font(.hlCaption)
                    .foregroundStyle(HLText.secondary)
                    .accessibilityIdentifier("settings.account.language.error")
            }
        }
        .task { await settings.refreshAccountLanguage() }
    }

    private var selection: Binding<AccountLanguage?> {
        Binding(
            get: { settings.accountLanguage },
            set: { language in
                guard let language else { return }
                Task { await settings.setAccountLanguage(language) }
            }
        )
    }
}
