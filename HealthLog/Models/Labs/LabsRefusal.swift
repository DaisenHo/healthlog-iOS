import Foundation

/// #126 P2 / 3.5 (v1.42.3) and #130 (v1.43) — the lab refusals whose reason the
/// app turns into its own sentence (the server's prose is written for the web).
public enum LabsRefusal {
    /// `422 labs.unit.mismatch`: a numeric reading in a unit the server cannot
    /// convert to the marker's (`meta.reason`: `unknown_analyte`,
    /// `unknown_unit`, `not_finite`). Nothing was written.
    public static let unitMismatch = "labs.unit.mismatch"
    /// `409 labs.biomarker.alias.taken`: `meta.alias` is already another
    /// marker's name or alias.
    public static let aliasTaken = "labs.biomarker.alias.taken"
    /// `404 labs.biomarker.notFound`; with `meta.mergedInto` the marker was
    /// merged into that one.
    public static let markerNotFound = "labs.biomarker.notFound"
    /// `422 labs.biomarker.merge.unitMismatch` (`meta.sources`).
    public static let mergeUnitMismatch = "labs.biomarker.merge.unitMismatch"
    /// `422 labs.biomarker.merge.invalid`.
    public static let mergeInvalid = "labs.biomarker.merge.invalid"

    /// The sentence for a lab refusal, or `nil` for anything else (the caller
    /// keeps its generic copy then).
    public static func sentence(for error: Error) -> String? {
        guard let error = error as? HLError else { return nil }
        switch error {
        case let .refusedWithReason(code, reason) where code == unitMismatch:
            return unitMismatchSentence(reason: reason)
        case let .refusedWithReason(code, alias) where code == aliasTaken:
            return AppLocale.string("labs.refusal.aliasTaken \(alias)")
        case let .refusedWithReason(code, _) where code == markerNotFound:
            return AppLocale.string("labs.refusal.merged")
        case let .server(_, code?, _) where code == mergeUnitMismatch:
            return AppLocale.string("labs.refusal.mergeUnitMismatch")
        case let .server(_, code?, _) where code == mergeInvalid:
            return AppLocale.string("labs.refusal.mergeInvalid")
        default:
            return nil
        }
    }

    /// One sentence per `labs.unit.mismatch` reason; an unknown reason gets
    /// the general one, never a guess.
    public static func unitMismatchSentence(reason: String) -> String {
        switch reason {
        case "unknown_analyte": AppLocale.string("labs.refusal.unit.unknownAnalyte")
        case "unknown_unit": AppLocale.string("labs.refusal.unit.unknownUnit")
        case "not_finite": AppLocale.string("labs.refusal.unit.notFinite")
        default: AppLocale.string("labs.refusal.unit.general")
        }
    }

    /// The marker a merged one went into, from a `404` with `meta.mergedInto`.
    public static func mergedTarget(of error: Error) -> String? {
        if case let HLError.refusedWithReason(code, target) = error, code == markerNotFound {
            return target
        }
        return nil
    }
}
