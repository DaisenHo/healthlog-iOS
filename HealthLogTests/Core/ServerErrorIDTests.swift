import Foundation

// swiftlint:disable force_unwrapping
import Testing
#if SWIFT_PACKAGE
    @testable import HealthLogCore
#else
    @testable import HealthLog
#endif

// #134 (server v1.43): the request id of a failed response, the ring buffer of
// recent failures, and the plain-text lines every report prints.
//
// Fixtures follow `docs/api/openapi.yaml` on HealthLog `main` at `2f5c4659f`
// (the merge of `release/v1.43.0`, `d06ce3604`): `ErrorEnvelope.meta` carries
// `requestId` beside `errorCode`, equal to the `x-request-id` header, shaped
// `^[A-Za-z0-9-]{8,64}$` (`src/lib/http/request-id.ts`); the server mints a v4
// UUID (`src/lib/random-id.ts`).

private enum Fixture {
    static let bodyID = "3f9a2c1b-7d4e-4f10-9a2b-c3d4e5f60718"
    static let headerID = "8b1e0c5d-2f3a-4b6c-8d7e-9f0a1b2c3d4e"
    static let url = URL(string: "https://test.healthlog.local/api/probe")!

    static func response(_ status: Int, header: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: header.map { ["X-Request-Id": $0] } ?? [:]
        )!
    }

    /// A v1.43 error envelope.
    static func envelope(requestId: String? = bodyID, errorCode: String? = "internal_error") -> Data {
        var meta: [String: Any] = [:]
        if let requestId { meta["requestId"] = requestId }
        if let errorCode { meta["errorCode"] = errorCode }
        let object: [String: Any] = ["data": NSNull(), "error": "Internal server error", "meta": meta]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

@Suite("ServerErrorID")
struct ServerErrorIDTests {
    @Test("v1.43: meta.requestId wins over the header")
    func bodyWins() {
        let id = ServerErrorID.extract(from: Fixture.response(500, header: Fixture.headerID), body: Fixture.envelope())
        #expect(id == Fixture.bodyID)
    }

    @Test("before v1.43: the x-request-id header, in any letter case")
    func headerFallback() throws {
        let body = Data(#"{"data":null,"error":"Service Unavailable"}"#.utf8)
        #expect(ServerErrorID.extract(from: Fixture.response(503, header: Fixture.headerID), body: body) == Fixture.headerID)
        let lower = try #require(HTTPURLResponse(
            url: Fixture.url, statusCode: 502, httpVersion: nil, headerFields: ["x-request-id": Fixture.headerID]
        ))
        #expect(ServerErrorID.extract(from: lower, body: Data()) == Fixture.headerID)
    }

    @Test("no id anywhere is a normal answer")
    func noID() {
        #expect(ServerErrorID.extract(from: Fixture.response(500), body: Fixture.envelope(requestId: nil)) == nil)
        #expect(ServerErrorID.extract(from: Fixture.response(500), body: Data("<html>Bad Gateway</html>".utf8)) == nil)
        #expect(ServerErrorID.extract(from: Fixture.response(500), body: Data()) == nil)
    }

    @Test(
        "anything but the server's id shape is dropped",
        arguments: [
            "short12",
            String(repeating: "a", count: 65),
            "3f9a2c1b 7d4e",
            "3f9a2c1b\"><script>",
            "max@example.com",
            "3f9a2c1b_7d4e4f10",
            "3f9a2c1bä7d4e4f10",
            "3f9a2c1b\n7d4e4f10"
        ]
    )
    func malformedDropped(value: String) {
        #expect(ServerErrorID.wellFormed(value) == nil)
        #expect(ServerErrorID.extract(from: Fixture.response(500, header: value), body: Fixture.envelope(requestId: value)) == nil)
    }

    @Test("the edges of the shape are accepted")
    func shapeEdges() {
        #expect(ServerErrorID.wellFormed("abcd1234") == "abcd1234")
        #expect(ServerErrorID.wellFormed(String(repeating: "A", count: 64)) != nil)
        #expect(ServerErrorID.wellFormed(Fixture.bodyID) == Fixture.bodyID)
    }

    @Test("a malformed body id falls back to a good header")
    func malformedBodyFallsBack() {
        let id = ServerErrorID.extract(
            from: Fixture.response(500, header: Fixture.headerID),
            body: Fixture.envelope(requestId: "not an id")
        )
        #expect(id == Fixture.headerID)
    }

    @Test("a non-string requestId does not break anything")
    func nonStringRequestID() {
        let body = Data(#"{"data":null,"error":"x","meta":{"requestId":42,"errorCode":"probe.conflict"}}"#.utf8)
        #expect(ServerErrorID.extract(from: Fixture.response(409), body: body) == nil)
        #expect(ServerErrorID.fields(in: body).errorCode == "probe.conflict")
    }

    @Test("a 2xx body is never parsed for the id, the header still counts")
    func successBodyNotParsed() {
        let body = Data(#"{"meta":{"requestId":"3f9a2c1b-7d4e-4f10-9a2b-c3d4e5f60718"}}"#.utf8)
        #expect(ServerErrorID.extract(from: Fixture.response(200), body: body) == nil)
        #expect(ServerErrorID.extract(from: Fixture.response(200, header: Fixture.headerID), body: body) == Fixture.headerID)
    }

    @Test("error code: meta first, then top level, prose dropped")
    func errorCode() {
        #expect(ServerErrorID.fields(in: Fixture.envelope(errorCode: "medication.notFound")).errorCode == "medication.notFound")
        let topLevel = Data(#"{"error":"x","errorCode":"assistant.disabled.coach"}"#.utf8)
        #expect(ServerErrorID.fields(in: topLevel).errorCode == "assistant.disabled.coach")
        #expect(ServerErrorID.fields(in: Fixture.envelope(errorCode: "Max Mustermann hat keinen Zugriff")).errorCode == nil)
    }

    @Test("the short form is the first 8 characters")
    func shortForm() {
        #expect(ServerErrorID.short(Fixture.bodyID) == "3f9a2c1b")
        #expect(ServerErrorID.short("abcd1234") == "abcd1234")
    }
}

@Suite("RecentFailureLog")
struct RecentFailureLogTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_792_000_000)
        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            value += seconds
        }
    }

    private static func failure(status: Int = 500, id: String?, kind: RecentFailure.Kind = .status, at: Date) -> RecentFailure {
        RecentFailure(at: at, method: "GET", route: "/api/probe", status: status, errorCode: nil, requestId: id, kind: kind)
    }

    @Test("keeps the last five, newest first")
    func ringBuffer() {
        let log = RecentFailureLog()
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        for index in 0 ..< 7 {
            log.record(Self.failure(id: "request-id-\(index)", at: start + Double(index)))
        }
        let ids = log.snapshot().map(\.requestId)
        #expect(ids == ["request-id-6", "request-id-5", "request-id-4", "request-id-3", "request-id-2"])
        log.clear()
        #expect(log.snapshot().isEmpty)
    }

    @Test("only failures the server answered are recorded")
    func recordsAnsweredFailuresOnly() {
        let log = RecentFailureLog()
        let response = Fixture.response(500, header: Fixture.headerID)
        for error: HLError in [.offline, .network(.timeout), .network(.connectionLost), .canceled] {
            log.record(error, method: .get, path: "/api/probe", response: response, body: Data())
        }
        log.record(CancellationError(), method: .get, path: "/api/probe", response: response, body: Data())
        #expect(log.snapshot().isEmpty)

        log.record(
            HLError.server(status: 500, code: "internal_error", message: "x"),
            method: .post, path: "/api/probe", response: response, body: Fixture.envelope()
        )
        log.record(
            HLError.decoding("x"),
            method: .get,
            path: "/api/probe",
            response: Fixture.response(200, header: Fixture.headerID),
            body: Data()
        )
        let entries = log.snapshot()
        #expect(entries.map(\.kind) == [.decoding, .status])
        #expect(entries.last?.requestId == Fixture.bodyID)
        #expect(entries.last?.errorCode == "internal_error")
        #expect(entries.first?.requestId == Fixture.headerID)
        #expect(entries.first?.errorCode == nil)
    }

    @Test("an entry holds the route template and no body, query or value")
    func redaction() throws {
        let log = RecentFailureLog()
        let body = Data(
            #"{"data":null,"error":"max@example.com 142/91 mmHg","meta":{"requestId":"3f9a2c1b-7d4e-4f10-9a2b-c3d4e5f60718","errorCode":"internal_error"}}"#
                .utf8
        )
        log.record(
            HLError.server(status: 500, code: "internal_error", message: "max@example.com 142/91 mmHg"),
            method: .put,
            path: "/api/medications/018f3c2a-9b4d-7c11-8a2e-1f5b6c7d8e90/dose-history?from=2026-10-01&note=Max",
            response: Fixture.response(500),
            body: body
        )
        let entry = try #require(log.snapshot().first)
        #expect(entry.route == "/api/medications/:id/dose-history")
        let line = RecentFailureLines.line(entry)
        for leak in ["max@example.com", "142", "mmHg", "018f3c2a", "from=", "Max", "test.healthlog.local"] {
            #expect(!line.contains(leak), "leaked \(leak)")
        }
    }

    @Test("a banner names the id of a 5xx or an unreadable answer")
    func displayIDForUnexpectedFailures() {
        let clock = Clock()
        let log = RecentFailureLog(now: { clock.now })
        log.record(Self.failure(status: 503, id: Fixture.headerID, at: clock.now))
        #expect(log.displayID(for: .server(status: 503, code: nil, message: "")) == Fixture.headerID)
        #expect(log.displayID(for: .server(status: 500, code: nil, message: "")) == nil)
        #expect(log.displayID(for: .decoding("x")) == nil)

        log.record(Self.failure(status: 200, id: Fixture.bodyID, kind: .decoding, at: clock.now))
        #expect(log.displayID(for: .decoding("x")) == Fixture.bodyID)
    }

    @Test("a 4xx and a failure without an answer never show an id")
    func noIDForExpectedRefusals() {
        let clock = Clock()
        let log = RecentFailureLog(now: { clock.now })
        log.record(Self.failure(status: 422, id: Fixture.bodyID, at: clock.now))
        #expect(log.displayID(for: .server(status: 422, code: "x", message: "Bitte prüfen")) == nil)
        #expect(log.displayID(for: .offline) == nil)
        #expect(log.displayID(for: .network(.timeout)) == nil)
        #expect(log.displayID(for: .unauthorized) == nil)
    }

    @Test("the newest matching failure decides, even without an id")
    func newestDecides() {
        let clock = Clock()
        let log = RecentFailureLog(now: { clock.now })
        log.record(Self.failure(id: Fixture.bodyID, at: clock.now))
        clock.advance(5)
        log.record(Self.failure(id: nil, at: clock.now))
        #expect(log.displayID(for: .server(status: 500, code: nil, message: "")) == nil)
    }

    @Test("an id older than the display window is not shown")
    func displayWindow() {
        let clock = Clock()
        let log = RecentFailureLog(now: { clock.now })
        log.record(Self.failure(id: Fixture.bodyID, at: clock.now))
        clock.advance(RecentFailureLog.displayWindow - 1)
        #expect(log.displayID(for: .server(status: 500, code: nil, message: "")) == Fixture.bodyID)
        clock.advance(2)
        #expect(log.displayID(for: .server(status: 500, code: nil, message: "")) == nil)
    }
}

@Suite("RecentFailureLines")
struct RecentFailureLinesTests {
    private static let at = Date(timeIntervalSince1970: 1_792_141_923) // 2026-10-16T09:12:03Z

    @Test("one line per failure, fixed words")
    func lineFormat() {
        let failures = [
            RecentFailure(
                at: Self.at, method: "GET", route: "/api/medications/:id", status: 500,
                errorCode: "internal_error", requestId: Fixture.bodyID, kind: .status
            ),
            RecentFailure(
                at: Self.at,
                method: "POST",
                route: "/api/measurements/batch",
                status: 502,
                errorCode: nil,
                requestId: nil,
                kind: .status
            ),
            RecentFailure(
                at: Self.at,
                method: "GET",
                route: "/api/labs/overview",
                status: 200,
                errorCode: nil,
                requestId: Fixture.headerID,
                kind: .decoding
            )
        ]
        #expect(RecentFailureLines.lines(failures) == [
            "recent errors:",
            "  2026-10-16T09:12:03Z GET /api/medications/:id 500 internal_error id 3f9a2c1b-7d4e-4f10-9a2b-c3d4e5f60718",
            "  2026-10-16T09:12:03Z POST /api/measurements/batch 502 no id",
            "  2026-10-16T09:12:03Z GET /api/labs/overview 200 unreadable id 8b1e0c5d-2f3a-4b6c-8d7e-9f0a1b2c3d4e"
        ])
        #expect(RecentFailureLines.lines([]) == ["recent errors: none"])
    }
}

// MARK: - Integration: the real APIClient over MockURLProtocol

@Suite("ServerErrorID: APIClient integration", .mockURLSession)
struct ServerErrorIDIntegrationTests {
    private struct Probe: Decodable {
        let value: Int
    }

    private static let path = "/api/error-id-probe/018f3c2a-9b4d-7c11-8a2e-1f5b6c7d8e90"

    private func makeClient(_ log: RecentFailureLog) -> APIClient {
        let env = AppEnvironment(
            baseURL: URL(string: "https://test.healthlog.local")!,
            cfAccessClientID: nil,
            cfAccessClientToken: nil,
            bundleID: "dev.healthlog.app",
            appVersion: "0.1.0",
            buildNumber: "1"
        )
        return APIClient(environment: env, keychain: InMemoryKeychain(), sessionConfiguration: .mock(), failureLog: log)
    }

    /// Its own log per test, so suites running in parallel never see each
    /// other's failures.
    private func send(_ handler: @escaping MockURLProtocol.Handler) async -> (RecentFailureLog, Error?) {
        MockURLProtocol.install(handler)
        let log = RecentFailureLog()
        let api = makeClient(log)
        do {
            _ = try await api.send(APIRequest<Probe>(method: .get, path: Self.path, maxRetries: 0))
            return (log, nil)
        } catch {
            return (log, error)
        }
    }

    @Test("v1.43: a 500 records the envelope's id, the thrown error is unchanged")
    func serverErrorRecorded() async {
        let (log, error) = await send { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: ["x-request-id": Fixture.bodyID])!,
                Fixture.envelope()
            )
        }
        #expect(error as? HLError == .server(status: 500, code: "internal_error", message: "Internal server error"))
        let entry = log.snapshot().first
        #expect(log.snapshot().count == 1)
        #expect(entry?.requestId == Fixture.bodyID)
        #expect(entry?.status == 500)
        #expect(entry?.errorCode == "internal_error")
        #expect(entry?.route == "/api/error-id-probe/:id")
        #expect(entry?.method == "GET")
        if let hlError = error as? HLError {
            #expect(log.displayID(for: hlError) == Fixture.bodyID)
        }
    }

    @Test("before v1.43: the header id is recorded")
    func headerOnlyServer() async {
        let (log, _) = await send { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: ["X-Request-Id": Fixture.headerID])!,
                Data(#"{"data":null,"error":"Service Unavailable"}"#.utf8)
            )
        }
        #expect(log.snapshot().first?.requestId == Fixture.headerID)
    }

    @Test("no id: the failure is still recorded, without one")
    func noIDRecorded() async {
        let (log, error) = await send { req in
            (HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!, Data("Bad Gateway".utf8))
        }
        #expect(log.snapshot().count == 1)
        #expect(log.snapshot().first?.requestId == nil)
        if let hlError = error as? HLError {
            #expect(log.displayID(for: hlError) == nil)
        }
    }

    @Test("an unreadable 2xx records the header id as a decoding failure")
    func decodingRecorded() async {
        let (log, error) = await send { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-request-id": Fixture.headerID])!,
                Data(#"{"totally":"unexpected"}"#.utf8)
            )
        }
        #expect(log.snapshot().first?.kind == .decoding)
        #expect(log.snapshot().first?.requestId == Fixture.headerID)
        if let hlError = error as? HLError {
            #expect(log.displayID(for: hlError) == Fixture.headerID)
        }
    }

    @Test("offline and success record nothing")
    func nothingRecorded() async {
        let (offline, _) = await send { _ -> (HTTPURLResponse, Data?) in throw URLError(.notConnectedToInternet) }
        #expect(offline.snapshot().isEmpty)
        let (success, error) = await send { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-request-id": Fixture.headerID])!,
                Data(#"{"data":{"value":1}}"#.utf8)
            )
        }
        #expect(error == nil)
        #expect(success.snapshot().isEmpty)
    }

    @Test("logout's cache purge clears the recent ids")
    func purgeClears() async {
        let (log, _) = await send { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Fixture.envelope())
        }
        #expect(log.snapshot().count == 1)
        // Through the protocol, as `performFullLocalLogout` calls it. On the
        // concrete actor in an async context, `await` would pick the
        // protocol extension's async no-op over the actor's own method.
        let api: APIClientProtocol = makeClient(log)
        await api.purgeCachedResponses()
        #expect(log.snapshot().isEmpty)
    }

    @Test("INT-Q: the purge on the concrete APIClient purges too, not the protocol's no-op")
    func concretePurgeClears() async {
        let log = RecentFailureLog()
        log.record(RecentFailure(
            at: Date(), method: "GET", route: "/api/medications/:id", status: 500,
            errorCode: "internal_error", requestId: Fixture.headerID, kind: .status
        ))
        #expect(log.snapshot().count == 1)
        // The call shape X1 found purging nothing: `await` on the concrete
        // actor in an async context.
        let client: APIClient = makeClient(log)
        await client.purgeCachedResponses()
        #expect(log.snapshot().isEmpty)
    }
}

// swiftlint:enable force_unwrapping
