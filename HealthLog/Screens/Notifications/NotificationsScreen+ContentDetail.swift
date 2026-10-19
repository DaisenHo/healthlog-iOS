import SwiftUI

extension NotificationsScreen {
    /// #126 3.3 (server v1.42.2) — what a notification may show. Off
    /// (`generic`, the server default) names what it is about with no health
    /// figure; on (`detailed`) adds figures, such as the score in the morning
    /// briefing's title. Shown only when the server sends `content`.
    @ViewBuilder
    var notificationContentCard: some View {
        if let detailed = store?.notificationContentDetailed {
            HLSettingsCard(
                icon: "text.bubble",
                title: "notifications.content.title",
                footer: "notifications.content.footer"
            ) {
                HLSettingsToggleRow(
                    title: "notifications.content.toggle",
                    description: nil,
                    isOn: Binding(
                        get: { detailed },
                        set: { newValue in Task { await store?.setNotificationContentDetailed(newValue) } }
                    ),
                    accessibilityID: "NotificationsScreen.contentDetailToggle"
                )
            }
        }
    }
}
