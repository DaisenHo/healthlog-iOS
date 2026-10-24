import Foundation

/// **CU-34 (Brief C6) — the closed set of Today hero-item kinds.**
///
/// Mirrors the server `PRIORITY_ITEM_KINDS`
/// (`<server-repo>/src/lib/daily/priority-item.ts:29-38`)
/// verbatim — including the DECLARATION ORDER, which is load-bearing: the
/// widgets resolver (`coerceEnabledHeroItemKinds`,
/// `src/lib/dashboard-layout.ts:559-566`) throws away whatever order the client
/// stored and re-filters the set back into this sequence on every read. Keeping
/// the same order locally means the optimistic paint equals the value the next
/// GET echoes, so the picker never flickers into a different order after a save.
///
/// **Why this is its OWN enum and not ``DailyPriorityItem/Kind``.** The two sets
/// look alike but answer different questions and are not the same size today:
/// `DailyPriorityItem.Kind` is the RENDER vocabulary of a rail item the server
/// already decided to send (it currently models seven kinds and drives the row's
/// icon), while `HeroItemKind` is the CONFIGURATION vocabulary of
/// `enabledHeroItemKinds` — the eight kinds the server's Zod enum accepts on
/// `PUT /api/dashboard/widgets`. Sending a token outside that enum is a hard
/// `422`, so this type is the closed set the picker may ever emit.
/// ``HeroItemKindParityTests`` pins that every render kind is also a
/// configurable kind, so the two can drift apart only deliberately.
///
/// The eight kinds split into ACTIONABLE (`coach_checkin`, `dose_window`,
/// `preventive_care`, `sync_issue` — they clear when the user acts) and
/// OBSERVATIONAL (the remaining four — acknowledge-only, hence dismissible).
/// That distinction is the rail's business, not this picker's: the user may
/// switch off any of the eight.
public enum HeroItemKind: String, Codable, Sendable, CaseIterable, Hashable {
    case coachCheckin = "coach_checkin"
    case doseWindow = "dose_window"
    case preventiveCare = "preventive_care"
    case syncIssue = "sync_issue"
    case milestone
    case ecgNewRecording = "ecg_new_recording"
    case tensionWindow = "tension_window"
    case sameTimeBaseline = "same_time_baseline"

    /// Server `.max(PRIORITY_ITEM_KINDS.length)` on the widgets PUT schema
    /// (`route.ts:157-160`) — the whole catalogue, i.e. "select everything" is
    /// the largest legal payload.
    public static let maxSelected = HeroItemKind.allCases.count

    /// Localized picker label. German values are taken VERBATIM from the web
    /// reference (`messages/de.json` → `dashboard.heroItems`), which the parity
    /// glossary names as the source of truth for German terminology — the same
    /// item type must not be called two different things on two clients.
    public var label: String {
        switch self {
        case .coachCheckin:
            AppLocale.string(LocalizedStringResource("Coach check-ins", comment: "Today hero item kind — coach_checkin"))
        case .doseWindow:
            AppLocale.string(LocalizedStringResource("Medication doses", comment: "Today hero item kind — dose_window"))
        case .preventiveCare:
            // No `comment:` on purpose — this key already exists in the catalogue
            // (MoreScreen hub row, same word, same German value "Vorsorge"), and
            // a second call site introducing a comment would only churn the
            // catalogue entry.
            AppLocale.string("Preventive care")
        case .syncIssue:
            AppLocale.string(LocalizedStringResource("Sync issues", comment: "Today hero item kind — sync_issue"))
        case .milestone:
            AppLocale.string(LocalizedStringResource("Milestones", comment: "Today hero item kind — milestone"))
        case .ecgNewRecording:
            AppLocale.string(LocalizedStringResource("New ECG recordings", comment: "Today hero item kind — ecg_new_recording"))
        case .tensionWindow:
            AppLocale.string(LocalizedStringResource("Tension windows", comment: "Today hero item kind — tension_window"))
        case .sameTimeBaseline:
            AppLocale.string(LocalizedStringResource("Same-time activity", comment: "Today hero item kind — same_time_baseline"))
        }
    }
}
