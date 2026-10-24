import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// #134 (server v1.43) — "Support-Info kopieren" on About: app, iOS, device
// class, language, server version and the recent request ids as plain text on
// the clipboard (``SupportInfoReport``). Copying is the whole effect: nothing
// is sent anywhere, and the one request it makes is the public
// `GET /api/version`, bounded so an offline phone still copies at once.

extension SettingsAboutScreen {
    enum SupportInfoCopyState: Equatable {
        case idle
        case copying
        case copied
    }

    var supportCard: some View {
        HLSettingsCard(
            icon: "lifepreserver",
            title: "settings.about.support.title",
            footer: "settings.about.support.footer"
        ) {
            VStack(alignment: .leading, spacing: HLSpace.sm) {
                HLSettingsActionRow(
                    icon: "doc.on.doc",
                    title: "settings.about.support.copy",
                    presents: .confirm
                ) {
                    Task { await copySupportInfo() }
                }
                .disabled(supportInfoState == .copying)
                .accessibilityIdentifier("settings.about.copySupportInfo")
                if supportInfoState == .copied {
                    Text("settings.about.support.copied")
                        .font(.hlCaption)
                        .foregroundStyle(HLText.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.about.supportInfoCopied")
                }
            }
        }
    }

    @MainActor
    private func copySupportInfo() async {
        supportInfoState = .copying
        let server = await Self.serverVersion(api: container?.api)
        let text = SupportInfoReport(SupportInfoReport.Input(
            generatedAt: Date(),
            build: Self.buildMetadata(),
            osVersion: Self.osVersion,
            deviceClass: Self.deviceClass,
            appLanguage: AppLocale.shared.serverCode,
            server: server,
            lastKnownServerVersion: UserDefaults.standard.string(forKey: KnownServerVersion.defaultsKey),
            failures: RecentFailureLog.shared.snapshot()
        )).text
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #endif
        supportInfoState = .copied
    }

    /// `GET /api/version`, given at most ``serverVersionBudget``. The patient
    /// session waits for connectivity, which is right for the outbox and
    /// wrong for a button: past the budget the report says "last known".
    private static func serverVersion(api: APIClientProtocol?) async -> ServerVersionInfo? {
        guard let api else { return nil }
        return await withTaskGroup(of: ServerVersionInfo?.self) { group in
            group.addTask { try? await api.fetchServerVersion() }
            group.addTask {
                try? await Task.sleep(for: serverVersionBudget)
                return nil
            }
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first
        }
    }

    private static let serverVersionBudget: Duration = .seconds(4)

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// `iPhone` or `iPad`: the model class, never the name the owner gave
    /// the device.
    private static var deviceClass: String {
        #if canImport(UIKit)
            UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
            "unknown"
        #endif
    }
}
