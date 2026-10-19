import Foundation

/// #126 P2 (server v1.42.0) — the batched adherence read with `meta`: the
/// account figure (`meta.aggregate`) and, with `?days=`, the report window.
public extension MedicationsRepository {
    /// `GET /api/medications/compliance[?days=N]`. `days` outside
    /// ``MedicationComplianceReport/acceptedDays`` is not sent (the server
    /// answers 422 rather than rounding). Standalone throws `.offline`, like
    /// ``complianceSummary()``: the route would leak and the device computes no
    /// account figure of its own.
    func complianceReport(days: Int? = nil) async throws -> MedicationComplianceReport {
        if isStandaloneActive { throw HLError.offline }
        var query: [(String, String)] = []
        if let days, MedicationComplianceReport.acceptedDays.contains(days) {
            query.append(("days", String(days)))
        }
        let req: APIRequest<Data> = .get("/api/medications/compliance", query: query)
        let (data, _) = try await api.download(req)
        let report: MedicationComplianceReport
        do {
            report = try JSONDecoder.hlDefault.decode(MedicationComplianceListWire.self, from: data).report
        } catch {
            throw HLError.decoding("medications/compliance: \(LogSanitizer.redact(String(describing: error)))")
        }
        MedicationComplianceAggregateMirror.shared.record(report)
        return report
    }
}

/// #126 P2 — the last account figure the batched read delivered, for the
/// compliance widget (`AppContainer.aggregateServerCompliancePercent`).
///
/// Held beside the read rather than on `MedicationsStore` so the store keeps
/// its shape. Guarded by the medication ids the same response covered: the
/// widget takes the figure only while the store shows exactly those
/// medications, so another account (other ids) or a changed list never reads a
/// figure that was not built from it. Holds a percentage and ids, no names.
final class MedicationComplianceAggregateMirror: @unchecked Sendable {
    static let shared = MedicationComplianceAggregateMirror()

    private let lock = NSLock()
    private var aggregate: MedicationComplianceAggregate?
    private var coveredApplicableIDs: Set<String> = []

    func record(_ report: MedicationComplianceReport) {
        let applicable = Set(report.entries.filter(\.isApplicable).map(\.medicationId))
        lock.withLock {
            aggregate = report.aggregate
            coveredApplicableIDs = applicable
        }
    }

    /// The figure, when it was built from exactly `applicableIDs`.
    func aggregate(matching applicableIDs: Set<String>) -> MedicationComplianceAggregate? {
        lock.withLock {
            guard !applicableIDs.isEmpty, applicableIDs == coveredApplicableIDs else { return nil }
            return aggregate
        }
    }

    func clear() {
        lock.withLock {
            aggregate = nil
            coveredApplicableIDs = []
        }
    }
}
