import SwiftUI

/// #137 (server v1.43) — one calm line above the cycle calendar when the
/// server merged a later start into the one just logged ("Your start on
/// 17 Sep was merged into 14 Sep.") or gave a start back ("The start on
/// 17 Sep is back."). The calendar itself already shows the result; this line
/// only says why it changed. Monochrome, dismissible, spoken once by VoiceOver
/// when it appears.
struct CycleStartNoticeRow: View {
    let notice: CycleStartNotice
    let onDismiss: () -> Void

    var body: some View {
        let sentence = notice.sentence()
        HStack(alignment: .firstTextBaseline, spacing: HLSpace.sm) {
            Image(systemName: "info.circle")
                .font(.hlSubhead)
                .foregroundStyle(HLText.secondary)
                .accessibilityHidden(true)
            Text(sentence)
                .font(.hlSubhead)
                .foregroundStyle(HLText.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.hlCaption.weight(.semibold))
                    .foregroundStyle(HLText.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cycle.startNotice.dismiss"))
            .accessibilityIdentifier("cycle.startNotice.dismiss")
        }
        .padding(HLSpace.md)
        .background(HLSurface.tertiary, in: RoundedRectangle(cornerRadius: HLRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycle.startNotice")
        .onAppear {
            AccessibilityNotification.Announcement(sentence).post()
        }
    }
}
