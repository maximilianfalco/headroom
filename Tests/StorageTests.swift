import Foundation
import Testing

private func tempDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "headroom-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct UsageStoreTests {
    private let sample = UsageSnapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_787_000_000),
        buckets: [UsageBucket(key: "five_hour", label: "Session", percent: 11,
                              resetsAt: Date(timeIntervalSince1970: 1_787_003_600))])

    @Test("a snapshot survives a write and a read")
    func roundTrip() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try UsageStore.save(sample, to: dir)
        #expect(UsageStore.load(from: dir) == sample)
    }

    @Test("token counts and cost survive the write too")
    func roundTripWithLocalUsage() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var withLocal = sample
        withLocal.local = LocalUsage(todayNew: 10, todayCached: 20, todayCost: 1.5,
                                     sessionNew: 5, sessionCached: 6, sessionCost: 0.5,
                                     newPerMinute: 2.5)
        try UsageStore.save(withLocal, to: dir)
        #expect(UsageStore.load(from: dir)?.local == withLocal.local)
    }

    @Test("saving twice leaves the newer snapshot, not both")
    func overwritesInPlace() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try UsageStore.save(sample, to: dir)
        var second = sample
        second.buckets = [UsageBucket(key: "five_hour", label: "Session", percent: 99, resetsAt: nil)]
        try UsageStore.save(second, to: dir)

        #expect(UsageStore.load(from: dir)?.buckets.first?.percent == 99)
    }

    @Test("saving creates the directory when it is not there yet")
    func createsMissingDirectory() throws {
        let parent = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let nested = parent.appending(path: "a/b/c")

        try UsageStore.save(sample, to: nested)
        #expect(UsageStore.load(from: nested) == sample)
    }

    @Test("nothing written yet reads as nothing, not as a crash")
    func missingFileReadsAsNil() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(UsageStore.load(from: dir) == nil)
    }

    @Test("a corrupt snapshot reads as nothing rather than throwing")
    func corruptFileReadsAsNil() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{ not a snapshot".write(to: dir.appending(path: "usage.json"),
                                    atomically: true, encoding: .utf8)
        #expect(UsageStore.load(from: dir) == nil)
    }
}

struct TokenStoreTests {
    @Test("a token survives a write and a read of our own keychain item")
    func roundTrip() {
        defer { TokenStore.clear() }
        let expiry = Date(timeIntervalSince1970: 1_787_000_000)
        TokenStore.save(StoredToken(accessToken: "tok-abc", expiresAt: expiry))

        let loaded = TokenStore.load()
        #expect(loaded?.accessToken == "tok-abc")
        #expect(loaded?.expiresAt == expiry)
    }

    @Test("saving again replaces the stored token")
    func saveReplaces() {
        defer { TokenStore.clear() }
        TokenStore.save(StoredToken(accessToken: "first", expiresAt: nil))
        TokenStore.save(StoredToken(accessToken: "second", expiresAt: nil))

        #expect(TokenStore.load()?.accessToken == "second")
    }

    @Test("clearing leaves nothing behind")
    func clearRemovesTheItem() {
        TokenStore.save(StoredToken(accessToken: "gone", expiresAt: nil))
        TokenStore.clear()

        #expect(TokenStore.load() == nil)
    }

    @Test("clearing when there is nothing stored is not an error")
    func clearIsIdempotent() {
        TokenStore.clear()
        TokenStore.clear()
        #expect(TokenStore.load() == nil)
    }
}
