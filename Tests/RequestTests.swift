import Foundation
import Testing

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let respond = Self.respond else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = respond(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func stubbed(status: Int, body: String,
                     capture: ((URLRequest) -> Void)? = nil) -> URLSession {
    StubURLProtocol.respond = { request in
        capture?(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

struct UsageRequestTests {
    private let body = #"{"five_hour":{"utilization":12.0,"resets_at":"2026-08-19T03:20:00.000Z"}}"#

    @Test("a successful response becomes a snapshot")
    func successReturnsBuckets() async throws {
        defer { StubURLProtocol.respond = nil }
        let snapshot = try await UsageFetcher.request(token: "t", session: stubbed(status: 200, body: body))
        #expect(snapshot.buckets.first?.percent == 12)
        #expect(snapshot.error == nil)
    }

    @Test("the request carries the bearer token and the beta header")
    func sendsAuthorization() async throws {
        defer { StubURLProtocol.respond = nil }
        nonisolated(unsafe) var seen: URLRequest?
        let session = stubbed(status: 200, body: body) { seen = $0 }
        _ = try await UsageFetcher.request(token: "secret-token", session: session)

        #expect(seen?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(seen?.value(forHTTPHeaderField: "anthropic-beta") == Config.oauthBetaHeader)
        #expect(seen?.url == Config.usageEndpoint)
    }

    @Test("a rejected token is reported as expired so the caller can re-source it")
    func unauthorizedBecomesTokenExpired() async {
        defer { StubURLProtocol.respond = nil }
        let session = stubbed(status: 401, body: "")
        await #expect(throws: UsageError.tokenExpired) {
            try await UsageFetcher.request(token: "t", session: session)
        }
    }

    @Test(arguments: [429, 500, 503, 404, 302])
    func otherStatusesAreReportedWithTheirCode(status: Int) async {
        defer { StubURLProtocol.respond = nil }
        let session = stubbed(status: status, body: "")
        await #expect(throws: UsageError.http(status)) {
            try await UsageFetcher.request(token: "t", session: session)
        }
    }

    @Test("a 200 with an unreadable body is an error, not an empty snapshot")
    func malformedSuccessBodyThrows() async {
        defer { StubURLProtocol.respond = nil }
        let session = stubbed(status: 200, body: "<html>nope</html>")
        await #expect(throws: (any Error).self) {
            try await UsageFetcher.request(token: "t", session: session)
        }
    }
}

struct SnapshotDirectoryTests {
    @Test(arguments: [
        ("com.falco.Headroom", "com.falco.Headroom.Widget"),
        ("com.falco.Headroom.Widget", "com.falco.Headroom.Widget"),
        (nil as String?, ".Widget"),
    ])
    func widgetIdIsDerivedOnceOnly(bundleID: String?, expected: String) {
        #expect(UsageStore.widgetBundleID(from: bundleID) == expected)
    }

    @Test("the app appends the widget's container to its own home")
    func appWritesIntoTheWidgetContainer() {
        let directory = UsageStore.fallbackDirectory(home: URL(fileURLWithPath: "/Users/x"),
                                                     widgetBundleID: "com.falco.Headroom.Widget")
        #expect(directory.path == "/Users/x/Library/Containers/com.falco.Headroom.Widget/Data"
                + "/Library/Application Support/Headroom")
    }

    @Test("inside the sandboxed widget the container is not appended twice")
    func widgetDoesNotDoubleUpItsOwnContainer() {
        let home = URL(fileURLWithPath: "/Users/x/Library/Containers/com.falco.Headroom.Widget/Data")
        let directory = UsageStore.fallbackDirectory(home: home,
                                                     widgetBundleID: "com.falco.Headroom.Widget")
        #expect(directory.path == home.path + "/Library/Application Support/Headroom")
    }
}
