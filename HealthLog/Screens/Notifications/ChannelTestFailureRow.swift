import SwiftUI

/// #112 — the cause of a failed channel test, in plain words: one sentence per
/// server `meta.errorCode`, the relay's HTTP status (or SMTP code) when it
/// answered one, and the relay's own short error text beneath it as plain
/// characters. Shared by the webhook and ntfy cards.
struct ChannelTestFailureRow: View {
    let failure: NotificationChannelTestFailure
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: HLSpace.xxs) {
            Text(Self.sentence(for: failure))
                .font(.hlCaption)
                .foregroundStyle(HLColor.statusBad)
                .fixedSize(horizontal: false, vertical: true)
            if let relayText = failure.upstreamBody {
                // The relay's words, verbatim and as text only (the server
                // bounds them to 200 characters and strips secret shapes).
                Text(verbatim: relayText)
                    .font(.hlCaption.monospaced())
                    .foregroundStyle(HLText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// The reason sentence plus the relay's status or SMTP code.
    static func sentence(for failure: NotificationChannelTestFailure) -> String {
        let reason = reasonText(failure.reason)
        if let status = failure.upstreamStatus {
            return reason + " " + AppLocale.string("notifications.channel.testFailure.httpStatus \(status)")
        }
        if let smtp = failure.smtpCode {
            return reason + " " + AppLocale.string("notifications.channel.testFailure.smtpCode \(smtp)")
        }
        return reason
    }

    static func reasonText(_ reason: NotificationChannelTestFailure.Reason) -> String {
        switch reason {
        case .credentialsRejected: AppLocale.string("notifications.channel.testFailure.credentialsRejected")
        case .endpointNotFound: AppLocale.string("notifications.channel.testFailure.endpointNotFound")
        case .rateLimited: AppLocale.string("notifications.channel.testFailure.rateLimited")
        case .upstreamError: AppLocale.string("notifications.channel.testFailure.upstreamError")
        case .upstreamRejected: AppLocale.string("notifications.channel.testFailure.upstreamRejected")
        case .redirected: AppLocale.string("notifications.channel.testFailure.redirected")
        case .timeout: AppLocale.string("notifications.channel.testFailure.timeout")
        case .connectionFailed: AppLocale.string("notifications.channel.testFailure.connectionFailed")
        case .privateOriginNotApproved: AppLocale.string("notifications.channel.testFailure.privateOriginNotApproved")
        case .privateOriginNotGrantable: AppLocale.string("notifications.channel.testFailure.privateOriginNotGrantable")
        case .unknown: AppLocale.string("notifications.channel.testFailure.unknown")
        }
    }
}
