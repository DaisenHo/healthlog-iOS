import SwiftUI

/// #126 P2 (server v1.40 / v1.40.2) — the parts of the daily digest the hero
/// did not show yet, rendered as delivered: Rest Mode with its day, how many
/// weeks the score has held, and up to five facts about the day (`today[]`,
/// label and value pre-formatted by the server). Nothing is computed here; a
/// digest without them shows nothing.
struct TodayHeroFacts: View {
    let digest: DailyDigest

    var body: some View {
        let lines = Self.statusLines(digest)
        if !lines.isEmpty || !digest.today.isEmpty {
            VStack(alignment: .leading, spacing: HLSpace.xs) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.hlSubhead)
                        .foregroundStyle(HLText.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(digest.today.prefix(Self.maxFacts).enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline, spacing: HLSpace.sm) {
                        Text(verbatim: fact.label)
                            .font(.hlSubhead)
                            .foregroundStyle(HLText.secondary)
                        Spacer(minLength: HLSpace.sm)
                        Text(verbatim: fact.value)
                            .font(.hlSubhead.weight(.medium))
                            .foregroundStyle(HLText.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("today.hero.facts")
        }
    }

    /// The server sends at most five; more would not be its shape.
    static let maxFacts = 5

    /// Rest Mode and the steady weeks, each only when the server said so.
    static func statusLines(_ digest: DailyDigest) -> [String] {
        var lines: [String] = []
        if let restMode = digest.restMode, restMode.day > 0 {
            lines.append(String(localized: "today.restMode.day \(restMode.day)"))
        }
        if let weeks = digest.score?.steadyWeeks, weeks > 0 {
            lines.append(
                digest.score?.steadyAtLeast == true
                    ? String(localized: "today.score.steadyAtLeast \(weeks)")
                    : String(localized: "today.score.steady \(weeks)")
            )
        }
        return lines
    }
}
