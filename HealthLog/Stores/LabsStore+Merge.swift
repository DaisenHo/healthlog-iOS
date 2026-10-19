import Foundation

/// #130 (server v1.43) — merge consequences and aliases. Split from
/// `LabsStore.swift` (file length); the two effectful calls
/// (``runBiomarkerMerge(into:sources:dryRun:)``, ``fetchHistory(biomarkerId:analyte:)``)
/// live there, behind the session lease, and everything here is synchronous.
public extension LabsStore {
    // MARK: - Merge

    /// The server's dry run for merging `sources` into `target`: counts,
    /// conversions and refusals, nothing changed. `nil` on a failure, with the
    /// sentence in ``lastError``.
    func previewMerge(into target: String, sources: [String]) async -> BiomarkerMergeResult? {
        await runBiomarkerMerge(into: target, sources: sources, dryRun: true)
    }

    /// The real merge. On success the sources point at the target from now
    /// on (a stale screen follows them) and the list reloads; there is no undo.
    func merge(into target: String, sources: [String]) async -> BiomarkerMergeResult? {
        let result = await runBiomarkerMerge(into: target, sources: sources, dryRun: false)
        if result != nil { await load() }
        return result
    }

    /// Called by the merge once the server answered, while the lease is current.
    internal func recordMerge(into target: String, sources: [String]) {
        for source in sources {
            mergedMarkerRedirects[source] = target
        }
    }

    /// A write against a marker that was merged answers `404` with
    /// `meta.mergedInto`: remember where it went, so a screen on the old
    /// marker opens the target (``resolvedBiomarker(_:)``) and the next load
    /// drops the cached one. Callers hold the current lease when they call.
    internal func noteMergedMarker(_ error: Error, oldId: String) {
        guard let target = LabsRefusal.mergedTarget(of: error), target != oldId else { return }
        mergedMarkerRedirects[oldId] = target
    }

    /// The marker a screen should show for `marker`: the one it was merged
    /// into when that happened, else the live catalog entry (so an alias edit
    /// shows at once), else `marker` as it was handed over.
    func resolvedBiomarker(_ marker: BiomarkerDTO) -> BiomarkerDTO {
        var id = marker.id
        var seen: Set<String> = [id]
        while let next = mergedMarkerRedirects[id], seen.insert(next).inserted {
            id = next
        }
        return biomarkers.first { $0.id == id } ?? marker
    }

    // MARK: - Aliases

    /// Replaces the marker's aliases (`PUT /api/biomarkers/{id}` with
    /// `aliases`). Trimmed, blanks and duplicates dropped, the server's cap of
    /// 50 respected. A spelling another marker owns comes back as `409
    /// labs.biomarker.alias.taken` with its own sentence in ``lastError``.
    @discardableResult
    func setAliases(_ aliases: [String], for markerId: String) async -> Bool {
        await updateBiomarker(id: markerId, BiomarkerPatch(aliases: Self.cleanAliases(aliases)))
    }

    internal static let maxAliases = 50

    internal static func cleanAliases(_ aliases: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for raw in aliases {
            let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, seen.insert(alias.lowercased()).inserted else { continue }
            out.append(alias)
        }
        return Array(out.prefix(maxAliases))
    }
}
