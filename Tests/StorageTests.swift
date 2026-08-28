import Foundation
import Security
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

struct LegacyTokenMirrorTests {
    private let service = "Headroom.tests.legacy-mirror"

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func add(_ account: String) {
        var item = query(account)
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = Data("x".utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private func exists(_ account: String) -> Bool {
        SecItemCopyMatching(query(account) as CFDictionary, nil) == errSecSuccess
    }

    @Test("cleanup takes the retired item and leaves anything else under that service alone")
    func removesOnlyTheMirror() {
        add("claude-oauth")
        add("keep-me")
        defer { SecItemDelete(query("keep-me") as CFDictionary) }

        LegacyTokenMirror.remove(service: service)

        #expect(exists("claude-oauth") == false)
        #expect(exists("keep-me"))
    }
}
