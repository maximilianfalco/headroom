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

    /// Derived so the bundle prefix stays configurable at build time. The widget asks for its
    /// own id and gets it back unchanged; the app asks and gets the widget's.
    static func widgetBundleID(from bundleID: String?) -> String {
        let id = bundleID ?? ""
        return id.hasSuffix(".Widget") ? id : id + ".Widget"
    }

    /// Inside the sandboxed widget `home` is already the container, so the path must not be
    /// appended twice.
    static func fallbackDirectory(home: URL, widgetBundleID: String) -> URL {
        let container = "Library/Containers/\(widgetBundleID)/Data"
        let base = home.path.contains(container) ? home : home.appending(path: container)
        return base.appending(path: "Library/Application Support/Headroom")
    }

    private static var fallbackDirectory: URL {
        fallbackDirectory(home: URL(fileURLWithPath: NSHomeDirectory()),
                          widgetBundleID: widgetBundleID(from: Bundle.main.bundleIdentifier))
    }

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

    static func load(from override: URL? = nil) -> UsageSnapshot? {
        let url = (override ?? directory).appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    /// Writes through a temporary file so a reader never sees a half written snapshot.
    static func save(_ snapshot: UsageSnapshot, to override: URL? = nil) throws {
        let dir = override ?? directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appending(path: ".\(fileName).tmp")
        try encoder.encode(snapshot).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(dir.appending(path: fileName), withItemAt: tmp)
    }
}
