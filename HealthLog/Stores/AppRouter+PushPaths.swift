import Foundation

/// #141 / #126 3.2 — the More-stack screens a link opens. Split out of
/// `AppRouter.swift` (file length and the `applyImmediate` complexity budget):
/// `healthlog://settings/notifications` and the four screens only a push `url`
/// names (``DeepLinkRoute/fromPushPath(_:)``) all land on the More tab with the
/// real back stack behind them.
extension AppRouter {
    func applyMoreStackRoute(_ route: DeepLinkRoute) {
        switch route {
        case .settingsNotifications:
            openSettings(.notifications)
        case .settingsSecurity:
            openSettings(.security)
        case .settingsIntegrations:
            requestSettingsIntegrations()
        case .checkups:
            openMoreDestination(.checkups)
        case .cycle:
            openMoreDestination(.cycle)
        default:
            break
        }
    }

    /// Mehr, Einstellungen, then `leaf`.
    private func openSettings(_ leaf: SettingsRoute) {
        selectedTab = .more
        morePath = .init()
        morePath.append(SettingsRoute.root)
        morePath.append(leaf)
    }

    /// Mehr, then the clinical-spine screen the More list itself links to.
    private func openMoreDestination(_ destination: SettingsRoute) {
        selectedTab = .more
        morePath = .init()
        morePath.append(destination)
    }
}
