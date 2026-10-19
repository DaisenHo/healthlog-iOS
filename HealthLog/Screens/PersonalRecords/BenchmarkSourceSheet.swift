import SwiftUI

/// v0.5.5.7 RECONCILE-COMPARE — disclaimer + source sheet for the
/// `ComparisonBand`.
///
/// **Why a dedicated sheet rather than a popover:** the band paints
/// a one-line claim ("Dein Bestwert liegt im typischen Bereich"); WHERE
/// that reference curve comes from deserves a full surface. Tap
/// surfaces this sheet with: per-metric source label, the reference
/// band, and the global provenance line at the full-height `.form`
/// detent per `hlSheetPresentation` contract.
///
/// **UI-Standard R17 + R18 (U1):** das Sheet heißt *Quellen*-Sheet, und
/// genau das trägt es jetzt — „Quelle: CDC / WHO Daten 2020–2024."
/// Der angehängte Pauschalteil („Werte sind Richtwerte, kein
/// medizinischer Befund. Bei Fragen wende dich an deinen Arzt oder deine
/// Ärztin.") ist gefallen; er lebt am Ack-Sheet und in Einstellungen →
/// Über diese App. Gleichzeitig sind die bis dahin hart im `Layout`-Enum
/// kodierten deutschen Literale echte Katalogschlüssel geworden — sie
/// waren `LocalizedStringKey`s ohne Katalogeintrag und rannen damit
/// unübersetzt durch (PROJECT_GUIDE.md: keine hardcodierten UI-Strings).
///
/// **1.0.3 (App Review 1.4.1):** die Pauschalzeile „Quelle: CDC / WHO Daten
/// 2020–2024" war eine Behauptung ohne Beleg. Sie ist durch die benannten
/// Referenzen aus ``MedicalSourceCatalog`` ersetzt (`.personalRecords(kind)`),
/// jede als Safari-`Link` über ``HLSourceRow``. Das Quellenlabel der Kurve
/// selbst kommt jetzt aus `benchmark.sourceLabel.<kind>` (de + en) statt aus
/// einem deutschen Literal im Provider.
///
/// **Localization:** every string surfaced here flows through
/// `LocalizedStringKey` + the project `Localizable.xcstrings` so the
/// EN translation can extend without code edits. #135 — the source label
/// and the band are the server's (`benchmark.sourceLabel`, already in the
/// account's language; `low` and `high` in the record's unit).
struct BenchmarkSourceSheet: View {
    let metricLabel: String
    /// 1.0.3 (App Review 1.4.1) — which metric's references to cite.
    let kind: MetricKind
    let band: RecordBenchmarkBand
    let onDismiss: () -> Void

    private var sources: [MedicalSource] {
        MedicalSourceCatalog.sources(for: .personalRecords(kind))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HLSpace.xl) {
                    header
                    sourceCard
                    if !sources.isEmpty {
                        referencesCard
                    }
                }
                .padding(.horizontal, HLSpace.lg)
                .padding(.vertical, HLSpace.xl)
            }
            .hlScreenBackground()
            .navigationTitle(LocalizedStringKey(Layout.navigationTitle))
            .navigationBarTitleDisplayMode(.inline)
            // v0.6.1 Y2 — Home-Compliance pattern: drop the 'Schließen'
            // confirmationAction. Drag-indicator dismisses. `onDismiss`
            // stays on the surface so the host can react to interactive
            // dismissal if needed.
        }
        .hlSheetPresentation(.form)
        .presentationBackground(HLColor.surface)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: HLSpace.sm) {
            HStack(spacing: HLSpace.xs) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.hlIcon(HLIconSize.lg))
                    .foregroundStyle(HLAccent.userBrandTint)
                    .accessibilityHidden(true)
                HLSectionLabel(LocalizedStringKey(Layout.eyebrow))
            }
            Text(metricLabel)
                .font(.hlTitle2)
                .foregroundStyle(HLText.primary)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: HLSpace.sm) {
            HLSectionLabel(LocalizedStringKey(Layout.sourceTitle))
            Text(band.sourceLabel)
                .font(.hlBody)
                .foregroundStyle(HLText.primary)
                .fixedSize(horizontal: false, vertical: true)
            referenceRangeRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HLSpace.lg)
        .background(HLSurface.secondary, in: RoundedRectangle(cornerRadius: HLRadius.card, style: .continuous))
    }

    private var referenceRangeRow: some View {
        HStack(spacing: HLSpace.xs) {
            Text(LocalizedStringKey(Layout.typicalRangeLabel))
                .font(.hlCaption.weight(.semibold))
                .foregroundStyle(HLText.secondary)
            Text(band.formattedRange)
                .font(.hlCaption)
                .foregroundStyle(HLText.primary)
                .monospacedDigit()
        }
        .padding(.top, HLSpace.xs)
    }

    /// 1.0.3 (App Review 1.4.1) — the standing "CDC/WHO 2020–2024" prose is
    /// replaced by the named references themselves, each a Safari `Link`
    /// (A360-3), rendered with the shared ``HLSourceRow``.
    private var referencesCard: some View {
        VStack(alignment: .leading, spacing: HLSpace.md) {
            HStack(spacing: HLSpace.xs) {
                Image(systemName: "text.book.closed")
                    .font(.hlIcon(HLIconSize.rowAction))
                    .foregroundStyle(HLText.secondary)
                    .accessibilityHidden(true)
                HLSectionLabel("sources.sheet.referencesTitle")
            }
            ForEach(sources) { source in
                HLSourceRow(name: source.name, year: source.year, caveatKey: source.caveatKey, url: source.url)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HLSpace.lg)
        .background(HLSurface.tertiary, in: RoundedRectangle(cornerRadius: HLRadius.card, style: .continuous))
        .accessibilityIdentifier("benchmark.source.references")
    }
}

extension BenchmarkSourceSheet {
    /// Katalogschlüssel dieser Fläche. Bis U1 standen hier deutsche Literale,
    /// die als `LocalizedStringKey` durchgereicht wurden — ohne Katalogeintrag
    /// blieben sie in jeder Sprache deutsch.
    enum Layout {
        static let navigationTitle = "benchmark.source.title"
        static let eyebrow = "benchmark.source.eyebrow"
        static let sourceTitle = "benchmark.source.sourceTitle"
        static let typicalRangeLabel = "benchmark.source.typicalRange"
    }
}

#Preview("BenchmarkSourceSheet — VO2 max") {
    BenchmarkSourceSheet(
        metricLabel: "VO₂ max",
        kind: .vo2Max,
        band: RecordBenchmarkBand(low: 35, high: 43, value: 41, unit: "ml/kg/min", sourceLabel: "ACSM, 11th edition"),
        onDismiss: {}
    )
}
