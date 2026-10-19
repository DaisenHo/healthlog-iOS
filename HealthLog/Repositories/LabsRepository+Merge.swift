import Foundation

/// #130 (server v1.43) — merging markers and the per-marker history.
public extension LabsRepository {
    /// `POST /api/biomarkers/{targetId}/merge`. A dry run changes nothing; the
    /// real merge moves the readings, adds the source names as aliases and
    /// deletes the sources, with no undo. Never queued offline: a merge the
    /// person cannot watch land is not one to replay later.
    func mergeBiomarkers(into targetId: String, sourceIds: [String], dryRun: Bool) async throws -> BiomarkerMergeResult {
        let req: APIRequest<BiomarkerMergeResult> = try .post(
            "/api/biomarkers/\(targetId)/merge",
            body: BiomarkerMergeRequest(sourceIds: sourceIds, dryRun: dryRun)
        )
        let result = try await api.send(req)
        if !dryRun { await invalidate([.biomarkers, .labsResults]) }
        return result
    }

    /// The whole history of one marker (`GET /api/labs?biomarkerId=` or
    /// `?analyte=`, up to 500 rows), for a detail page whose readings lie
    /// beyond the list's page. Network-direct.
    func markerHistory(biomarkerId: String?, analyte: String?) async throws -> [LabResultDTO] {
        try await labs(biomarkerId: biomarkerId, analyte: biomarkerId == nil ? analyte : nil, limit: 500).results
    }
}
