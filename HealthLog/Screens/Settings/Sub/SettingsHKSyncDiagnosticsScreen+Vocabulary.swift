import Foundation

/// **K1 — words, not identifiers, on the Sync-Diagnose screen.**
///
/// H2 photographed this screen showing Swift enum spellings to the user:
/// „foreground", „healthKitQuery", „failed", „coldActivation". Every internal
/// value the screen renders now passes through one of these functions, and a
/// value none of them knows reads as the neutral „Unbekannt" rather than as
/// the identifier. Pure, so `HKSyncDiagnosticsVocabularyTests`
/// can pin every case without a view.
enum HKSyncDiagnosticsVocabulary {
    /// The heartbeat word `SpeziCollectionTrigger.run` records: either a
    /// `SpeziCollectionTrigger.Source` raw value or, for triggers that have no
    /// member there, the `HealthSyncTrigger` raw value. Persisted as a string,
    /// so an older build's word can come back from `UserDefaults`.
    static func collectionTrigger(_ raw: String) -> String {
        switch raw {
        case "background", "processing":
            AppLocale.string("settings.hkdiag.value.trigger.background")
        case "appRefresh":
            AppLocale.string("settings.hkdiag.value.trigger.appRefresh")
        case "foreground":
            AppLocale.string("settings.hkdiag.value.trigger.foreground")
        case "manual":
            AppLocale.string("settings.hkdiag.value.trigger.manual")
        case "push", "silentPush":
            AppLocale.string("settings.hkdiag.value.trigger.push")
        case "coldActivation":
            AppLocale.string("settings.hkdiag.value.trigger.coldActivation")
        case "postAuthentication":
            AppLocale.string("settings.hkdiag.value.trigger.postAuthentication")
        case "observer":
            AppLocale.string("settings.hkdiag.value.trigger.observer")
        case "accountTeardown":
            AppLocale.string("settings.hkdiag.value.trigger.accountTeardown")
        default:
            unknown
        }
    }

    /// The source of the last direct-workout pass. `nil` = no pass yet.
    static func workoutSource(_ source: WorkoutSyncSource?) -> String {
        guard let source else { return "—" }
        return switch source {
        case .registration: AppLocale.string("settings.hkdiag.value.trigger.registration")
        case .observer: collectionTrigger("observer")
        case .processing: collectionTrigger("processing")
        case .appRefresh: collectionTrigger("appRefresh")
        case .push: collectionTrigger("push")
        case .foreground: collectionTrigger("foreground")
        case .manual: collectionTrigger("manual")
        }
    }

    static func workoutFailure(_ failure: HKSyncDiagnostics.WorkoutFailureClass) -> String {
        switch failure {
        case .registration: AppLocale.string("settings.hkdiag.value.failure.registration")
        case .healthKitQuery: AppLocale.string("settings.hkdiag.value.failure.healthKitQuery")
        case .transport: AppLocale.string("settings.hkdiag.value.failure.transport")
        case .serverRejected: AppLocale.string("settings.hkdiag.value.failure.serverRejected")
        case .persistence: AppLocale.string("settings.hkdiag.value.failure.persistence")
        case .cancelled: AppLocale.string("settings.hkdiag.value.failure.cancelled")
        case .unknown: AppLocale.string("settings.hkdiag.value.failure.unknown")
        }
    }

    static func workoutBackfill(_ state: HKSyncDiagnostics.WorkoutBackfillState) -> String {
        switch state {
        case .idle: AppLocale.string("settings.hkdiag.status_idle")
        case .running: AppLocale.string("settings.hkdiag.value.backfill.running")
        case .progressed: AppLocale.string("settings.hkdiag.value.backfill.progressed")
        case .finished: AppLocale.string("settings.hkdiag.value.backfill.finished")
        case .authorizationPending: AppLocale.string("settings.hkdiag.value.backfill.authorizationPending")
        case .failed: AppLocale.string("settings.hkdiag.value.backfill.failed")
        case .serverUnsupported: AppLocale.string("settings.hkdiag.value.backfill.serverUnsupported")
        }
    }

    /// A server `MeasurementType` from `metricFreshness` („PULSE",
    /// „RESPIRATORY_RATE") as the metric's own name. A type this build has no
    /// metric for keeps its server word: the row is a list entry, and ten rows
    /// all titled „Unbekannt" would say less than the word itself.
    ///
    /// U1 (#18) — the lookup ignores case and separators, so `heart_rate`,
    /// `heart-rate` and `HEART_RATE` are one key. `WORKOUTS` (the server's
    /// pseudo-type from `Workout` rows, `metric-freshness.ts`) and
    /// `MEDICATION_DOSE` (W5, v1.42.4) have their own words.
    /// The fallback is no longer the raw identifier but a sentence-cased one
    /// („HEART_RATE" → „Heart rate"), so no row shouts or shows underscores.
    static func freshnessType(_ raw: String) -> String {
        let key = normalizedTypeKey(raw)
        switch key {
        case "WORKOUTS", "WORKOUT": return AppLocale.string("settings.hkdiag.freshness.workouts")
        // W5 — server v1.42.4: doses imported from Apple Health (W3's bulk call).
        case "MEDICATION_DOSE": return AppLocale.string("settings.hkdiag.freshness.medication_dose")
        case "BLOOD_PRESSURE_DIA": return MetricKind.bloodPressure.displayName
        default: break
        }
        guard let kind = MetricKind.allCases.first(where: { $0.availabilitySummaryKey == key }) else {
            return prettifiedTypeKey(key)
        }
        return kind.displayName
    }

    /// Upper case, every run of non-alphanumerics one underscore.
    static func normalizedTypeKey(_ raw: String) -> String {
        raw.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "_")
    }

    /// „HEART_RATE" → „Heart rate". Empty input reads as „Unbekannt".
    static func prettifiedTypeKey(_ key: String) -> String {
        let words = key.split(separator: "_").map { $0.lowercased() }
        guard let first = words.first else { return unknown }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    /// U1 (#18) — the workout counters as a sentence: „710 gelesen,
    /// 710 gesendet, 710 angenommen, 0 abgelehnt". Workouts HealthKit handed
    /// over that could not be mapped are named only when there are any; the
    /// old „F · M · S · A · X" line needed a code comment to be read.
    static func workoutCounts(_ snapshot: HKSyncDiagnostics.WorkoutSnapshot) -> String {
        let read = snapshot.fetchedTotal
        let sent = snapshot.sentTotal
        let accepted = snapshot.acceptedTotal
        let rejected = snapshot.skippedTotal
        let sentence = AppLocale.string("settings.hkdiag.workout_counts \(read) \(sent) \(accepted) \(rejected)")
        let unmapped = snapshot.fetchedTotal - snapshot.mappedTotal
        guard unmapped > 0 else { return sentence }
        return sentence + AppLocale.string("settings.hkdiag.workout_counts_unmapped \(unmapped)")
    }

    /// #12 — the gate that decided the heart-rate bucket path's last outcome,
    /// in words, followed by its identifier in parentheses. The identifier is
    /// what a tester quotes back and what Console prints after `gate=`.
    static func heartRateBucketGate(_ gate: HRBucketGate) -> String {
        let words = switch gate {
        case .uploaded: AppLocale.string("settings.hkdiag.hrbuckets.gate.uploaded")
        case .upToDate: AppLocale.string("settings.hkdiag.hrbuckets.gate.upToDate")
        case .standalone: AppLocale.string("settings.hkdiag.hrbuckets.gate.standalone")
        case .noAuthToken: AppLocale.string("settings.hkdiag.hrbuckets.gate.noAuthToken")
        case .flagOff: AppLocale.string("settings.hkdiag.hrbuckets.gate.flagOff")
        case .cutoverPending: AppLocale.string("settings.hkdiag.hrbuckets.gate.cutoverPending")
        case .healthDataLocked: AppLocale.string("settings.hkdiag.hrbuckets.gate.healthDataLocked")
        case .queryFailed: AppLocale.string("settings.hkdiag.hrbuckets.gate.queryFailed")
        case .uploadDeferred: AppLocale.string("settings.hkdiag.hrbuckets.gate.uploadDeferred")
        case .uploadFailed: AppLocale.string("settings.hkdiag.hrbuckets.gate.uploadFailed")
        case .rawFallbackSweepFailed: AppLocale.string("settings.hkdiag.hrbuckets.gate.rawFallbackSweepFailed")
        case .rawFallbackSweepStarved: AppLocale.string("settings.hkdiag.hrbuckets.gate.rawFallbackSweepStarved")
        }
        return "\(words) (\(gate.rawValue))"
    }

    /// The neutral word for a value this build cannot name.
    static var unknown: String {
        AppLocale.string("settings.hkdiag.verdict_unknown")
    }
}
