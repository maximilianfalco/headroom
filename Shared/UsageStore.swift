import Foundation

/// Shared read/write point for the snapshot the app fetches and the widget renders.
enum UsageStore {
    private static let fileName = "usage.json"

    private static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// Falls back to the widget's own container when App Groups are unavailable
    /// (free Apple IDs often cannot provision them). The unsandboxed app can still write there.
    private static var directory: URL {
        if let id = appGroupID,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url.appending(path: "Library/Application Support/Headroom")
        }
        return fallbackDirectory
    }

    /// Derived so the bundle prefix stays configurable at build time.
    private static var widgetBundleID: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix(".Widget") ? id : id + ".Widget"
    }

    private static var fallbackDirectory: URL {
        let widgetContainer = "Library/Containers/\(widgetBundleID)/Data"
        let home = URL(fileURLWithPath: NSHomeDirectory())
        // Inside the sandboxed widget NSHomeDirectory() is already the container.
        let base = home.path.contains(widgetContainer) ? home : home.appending(path: widgetContainer)
        return base.appending(path: "Library/Application Support/Headroom")
    }

    private static var fileURL: URL { directory.appending(path: fileName) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appending(path: ".\(fileName).tmp")
        try encoder.encode(snapshot).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }
}
