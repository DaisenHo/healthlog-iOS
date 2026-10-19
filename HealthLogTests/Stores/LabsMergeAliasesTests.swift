// #130 and #126 3.5 (server v1.42.3 / v1.43) — labs: a reading in another
// unit, the unit refusal with its reason, aliases, merging markers and the
// consequences of a merge. Drives the REAL store over the REAL `APIClient` on a
// session-scoped `MockURLProtocolSession`, like `LabsOverviewListTests`.
// Fixtures follow `CreateLabResultRequest`, `Biomarker`, `BiomarkerMergeRequest`
// and `BiomarkerMergeResult` in `docs/api/openapi.yaml` on `release/v1.43.0`
// (`d06ce3604`).

// swiftlint:disable force_unwrapping

#if !SWIFT_PACKAGE

    import Foundation
    @testable import HealthLog
    import Testing

    @Suite("#130 labs: unit conversion, aliases and merge", .serialized)
    @MainActor
    struct LabsMergeAliasesTests {
        private nonisolated static let owner = "owner-labs-merge"

        struct Seen {
            let method: String
            let path: String
            let query: String
            let body: String
        }

        private final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var seen: [Seen] = []

            func record(_ request: URLRequest) {
                let body = (request.httpBody ?? request.httpBodyStream.map(Self.read)).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
                lock.withLock {
                    seen.append(Seen(
                        method: request.httpMethod ?? "", path: request.url?.path ?? "",
                        query: request.url?.query ?? "", body: body
                    ))
                }
            }

            var all: [Seen] {
                lock.withLock { seen }
            }

            private static func read(_ stream: InputStream) -> Data {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                return data
            }
        }

        private func makeStore(_ session: MockURLProtocolSession) throws -> LabsStore {
            let keychain = InMemoryKeychain()
            try? keychain.setString("token", forKey: KeychainKey.authToken)
            let api = APIClient(
                environment: AppEnvironment(
                    baseURL: session.baseURL,
                    bundleID: "dev.healthlog.app",
                    appVersion: "1.3.0",
                    buildNumber: "1"
                ),
                keychain: keychain,
                sessionConfiguration: session.configuration
            )
            let repository = try LabsRepository(api: api, outbox: OutboxQueue(inMemory: true))
            let registry = AuthenticatedSessionLeaseRegistry()
            registry.activate(ownerID: Self.owner)
            let store = LabsStore(repository: repository)
            store.bindAuthenticatedSessionRegistry(registry, ownerIDProvider: { Self.owner })
            return store
        }

        private nonisolated static let catalog = Data(#"""
        {"data":{"biomarkers":[
          {"id":"bm_a1c","name":"HbA1c","unit":"%","hasContext":false,"createdAt":"","updatedAt":"","aliases":["Hb A1c"]},
          {"id":"bm_a1c_ifcc","name":"HbA1c IFCC","unit":"mmol/mol","hasContext":false,"createdAt":"","updatedAt":"","aliases":[]}]}}
        """#.utf8)

        private nonisolated static let mergedCatalog = Data(#"""
        {"data":{"biomarkers":[
          {"id":"bm_a1c","name":"HbA1c","unit":"%","hasContext":false,"createdAt":"","updatedAt":"",
           "aliases":["Hb A1c","HbA1c IFCC"]}]}}
        """#.utf8)

        private nonisolated static let emptyPage = Data(#"{"data":{"results":[],"meta":{"total":0,"limit":500,"offset":0}}}"#.utf8)

        private nonisolated static func mergeResult(dryRun: Bool, refused: Bool = false) -> Data {
            let conversion = refused ? #""refused","refusal":"unknown_unit""# : #""converted","refusal":null"#
            return Data("""
            {"data":{"dryRun":\(dryRun),"target":{"id":"bm_a1c","name":"HbA1c","unit":"%","hasContext":false,
             "createdAt":"","updatedAt":"","aliases":["Hb A1c"]},
             "sources":[{"id":"bm_a1c_ifcc","name":"HbA1c IFCC","unit":"mmol/mol","readingCount":12,"conversion":\(conversion)}],
             "movedReadings":12,"convertedReadings":12,"aliasesAdded":["HbA1c IFCC"],
             "mergeId":\(dryRun ? "null" : "\"mg_1\"")},"error":null}
            """.utf8)
        }

        private nonisolated static func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        }

        // MARK: - 3.5 and the unit refusal

        @Test("A converted reading names what was printed and the printed range; a plain one names nothing")
        func conversionLines() {
            let converted = LabConversion(
                converted: true, sourceValue: 5.4, sourceUnit: "mmol/L", printedReferenceText: "3.9 - 5.5 mmol/L"
            )
            let printed = "\(5.4.formatted(.number.precision(.fractionLength(0 ... 4)))) mmol/L"
            #expect(converted.convertedLine == String(localized: "labs.conversion.from \(printed)"))
            #expect(converted.printedRangeLine?.contains("3.9 - 5.5 mmol/L") == true)
            #expect(converted.lines.count == 2)
            let plain = LabConversion(converted: false, sourceValue: 5.4, sourceUnit: "mmol/L", printedReferenceText: nil)
            #expect(plain.lines.isEmpty)
        }

        @Test("A linked reading sends the printed unit only when it differs from the marker's")
        func printedUnitRule() throws {
            #expect(LabPrintedUnit.sent("  mmol/L ", markerUnit: "mg/dL") == "mmol/L")
            #expect(LabPrintedUnit.sent("mg/dL", markerUnit: "mg/dL") == nil)
            #expect(LabPrintedUnit.sent("  ", markerUnit: "mg/dL") == nil)
            let body = LabResultCreate(biomarkerId: "bm_glu", value: 5.4, unit: "mmol/L", takenAt: "2026-10-01T08:00:00Z")
            let json = try #require(String(data: JSONEncoder.hlDefault.encode(body), encoding: .utf8))
            #expect(json.contains(#""unit":"mmol\/L""#) || json.contains(#""unit":"mmol/L""#))
            #expect(json.contains(#""biomarkerId":"bm_glu""#))
        }

        @Test("422 labs.unit.mismatch names its reason in a sentence; nothing is queued", arguments: [
            ("unknown_analyte", "labs.refusal.unit.unknownAnalyte"),
            ("unknown_unit", "labs.refusal.unit.unknownUnit"),
            ("not_finite", "labs.refusal.unit.notFinite"),
            ("from_the_future", "labs.refusal.unit.general")
        ])
        func unitMismatchSentence(reason: String, key: String) async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            session.install { request in
                (Self.response(request, 422), Data("""
                {"data":null,"error":"Unit mismatch","meta":{"errorCode":"labs.unit.mismatch","reason":"\(reason)",
                 "markerUnit":"mg/dL","readingUnit":"mmol/L"}}
                """.utf8))
            }
            let store = try makeStore(session)
            let ok = await store.createLab(
                LabResultCreate(biomarkerId: "bm_glu", value: 5.4, unit: "mmol/L", takenAt: "2026-10-01T08:00:00Z")
            )
            #expect(!ok)
            #expect(store.lastError == String(localized: String.LocalizationValue(key)))
            #expect(store.labs.isEmpty, "a refused reading is not inserted optimistically")
        }

        // MARK: - Aliases

        @Test("Editing aliases PUTs the cleaned list; a patch without them omits the key")
        func aliasesPut() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            let recorder = Recorder()
            session.install { request in
                recorder.record(request)
                switch request.url?.path ?? "" {
                case "/api/biomarkers": return (Self.response(request, 200), Self.catalog)
                case "/api/labs/overview": return (Self.response(request, 404), Data(#"{"data":null,"error":"x"}"#.utf8))
                case "/api/biomarkers/bm_a1c":
                    return (
                        Self.response(request, 200),
                        Data(
                            #"{"data":{"id":"bm_a1c","name":"HbA1c","unit":"%","hasContext":false,"createdAt":"","updatedAt":"","aliases":["Hb A1c","HBA1C"]}}"#
                                .utf8
                        )
                    )
                default: return (Self.response(request, 200), Self.emptyPage)
                }
            }
            let store = try makeStore(session)
            let ok = await store.setAliases([" Hb A1c ", "HBA1C", "hba1c", ""], for: "bm_a1c")
            #expect(ok)
            let put = try #require(recorder.all.first { $0.method == "PUT" })
            #expect(put.path == "/api/biomarkers/bm_a1c")
            let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(put.body.utf8))
            #expect(decoded["aliases"] == ["Hb A1c", "HBA1C"])
            let plain = try String(data: JSONEncoder.hlDefault.encode(BiomarkerPatch(name: "HbA1c")), encoding: .utf8)
            #expect(plain?.contains("aliases") == false)
        }

        @Test("409 labs.biomarker.alias.taken names the spelling, not a duplicate marker name")
        func aliasTaken() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            session.install { request in
                (Self.response(request, 409), Data(#"""
                {"data":null,"error":"Alias taken","meta":{"errorCode":"labs.biomarker.alias.taken","alias":"A1c","biomarkerId":"bm_other"}}
                """#.utf8))
            }
            let store = try makeStore(session)
            let ok = await store.setAliases(["A1c"], for: "bm_a1c")
            #expect(!ok)
            #expect(store.lastError == String(localized: "labs.refusal.aliasTaken \("A1c")"))
            #expect(!store.lastErrorWasDuplicateName)
        }

        // MARK: - Merge

        @Test("A merge is a dry run first; the preview is rendered as delivered")
        func mergeDryRun() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            let recorder = Recorder()
            session.install { request in
                recorder.record(request)
                return (Self.response(request, 200), Self.mergeResult(dryRun: true))
            }
            let store = try makeStore(session)
            let preview = try #require(await store.previewMerge(into: "bm_a1c", sources: ["bm_a1c_ifcc", "bm_a1c"]))
            let post = try #require(recorder.all.first)
            #expect(post.path == "/api/biomarkers/bm_a1c/merge")
            let body = try JSONSerialization.jsonObject(with: Data(post.body.utf8)) as? [String: Any]
            #expect(body?["dryRun"] as? Bool == true)
            #expect(body?["sourceIds"] as? [String] == ["bm_a1c_ifcc"], "the target is never among the sources")
            #expect(preview.dryRun)
            #expect(preview.movedReadings == 12)
            #expect(preview.sources.first?.conversion == .converted)
            #expect(!preview.hasRefusal)
            #expect(store.mergedMarkerRedirects.isEmpty, "a dry run changes nothing")
            let lines = BiomarkerMergeCopy.summaryLines(preview)
            #expect(lines.count == 2)
        }

        @Test("A preview with a refused source cannot be confirmed and says why")
        func refusedPreview() throws {
            let preview = try JSONDecoder.hlDefault.decode(
                APIEnvelope<BiomarkerMergeResult>.self, from: Self.mergeResult(dryRun: true, refused: true)
            ).data
            let result = try #require(preview)
            #expect(result.hasRefusal)
            let lines = BiomarkerMergeCopy.summaryLines(result)
            #expect(lines.first == String(localized: "labs.refusal.unit.unknownUnit"))
            #expect(lines.last == String(localized: "labs.merge.refused"))
        }

        @Test("After a merge the old marker opens the target, with the new spellings")
        func mergeRedirects() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            let merged = LockedFlag()
            session.install { request in
                switch request.url?.path ?? "" {
                case "/api/biomarkers/bm_a1c/merge":
                    merged.set()
                    return (Self.response(request, 200), Self.mergeResult(dryRun: false))
                case "/api/biomarkers":
                    return (Self.response(request, 200), merged.isSet ? Self.mergedCatalog : Self.catalog)
                case "/api/labs/overview": return (Self.response(request, 404), Data(#"{"data":null,"error":"x"}"#.utf8))
                default: return (Self.response(request, 200), Self.emptyPage)
                }
            }
            let store = try makeStore(session)
            await store.load()
            let stale = try #require(store.biomarkers.first { $0.id == "bm_a1c_ifcc" })
            let result = await store.merge(into: "bm_a1c", sources: ["bm_a1c_ifcc"])
            #expect(result?.mergeId == "mg_1")
            #expect(store.mergedMarkerRedirects["bm_a1c_ifcc"] == "bm_a1c")
            let opened = store.resolvedBiomarker(stale)
            #expect(opened.id == "bm_a1c")
            #expect(opened.aliases.contains("HbA1c IFCC"))
            #expect(!store.biomarkers.contains { $0.id == "bm_a1c_ifcc" })
        }

        @Test("A write to a merged marker (404 with meta.mergedInto) remembers where it went")
        func notFoundMergedInto() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            session.install { request in
                if request.httpMethod == "PUT" {
                    return (Self.response(request, 404), Data(#"""
                    {"data":null,"error":"Not found","meta":{"errorCode":"labs.biomarker.notFound","mergedInto":"bm_a1c"}}
                    """#.utf8))
                }
                switch request.url?.path ?? "" {
                case "/api/biomarkers": return (Self.response(request, 200), Self.mergedCatalog)
                case "/api/labs/overview": return (Self.response(request, 404), Data(#"{"data":null,"error":"x"}"#.utf8))
                default: return (Self.response(request, 200), Self.emptyPage)
                }
            }
            let store = try makeStore(session)
            let ok = await store.updateBiomarker(id: "bm_a1c_ifcc", BiomarkerPatch(name: "x"))
            #expect(!ok)
            #expect(store.mergedMarkerRedirects["bm_a1c_ifcc"] == "bm_a1c")
            #expect(store.lastError == String(localized: "labs.refusal.merged"))
            let plain = HLError.server(status: 404, code: "labs.biomarker.notFound", message: "x")
            #expect(LabsRefusal.mergedTarget(of: plain) == nil, "a plain not-found is no merge")
        }

        @Test("A marker's whole history is read by its id, up to 500 rows")
        func markerHistory() async throws {
            let session = MockURLProtocolSession()
            defer { session.invalidate() }
            let recorder = Recorder()
            session.install { request in
                recorder.record(request)
                return (Self.response(request, 200), Data(#"""
                {"data":{"results":[{"id":"old","biomarkerId":"bm_tsh","panel":null,"analyte":"TSH","value":2.1,"unit":"mU/l",
                 "referenceLow":null,"referenceHigh":null,"takenAt":"2001-03-01T08:00:00Z","source":"MANUAL","hasNote":false,
                 "rangeStatus":"unknown","createdAt":"","updatedAt":""}],"meta":{"total":1,"limit":500,"offset":0}}}
                """#.utf8))
            }
            let store = try makeStore(session)
            let rows = await store.fetchHistory(biomarkerId: "bm_tsh", analyte: "TSH")
            #expect(recorder.all.count == 1)
            #expect(recorder.all.first?.query.contains("biomarkerId=bm_tsh") == true)
            #expect(recorder.all.first?.query.contains("limit=500") == true)
            #expect(rows?.first?.takenAt == "2001-03-01T08:00:00Z")
            store.clearOnLogout()
            #expect(store.mergedMarkerRedirects.isEmpty)
        }
    }

    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.withLock { value = true }
        }

        var isSet: Bool {
            lock.withLock { value }
        }
    }
#endif
