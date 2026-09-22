import Foundation

actor CodexLocalUsageReader {
    static let shared = CodexLocalUsageReader()

    private struct Entry {
        let id: String
        let at: Date
        let new: Int
        let cached: Int
        let cost: Double?
    }

    private struct Parsed {
        let modified: Date
        let size: Int
        let entries: [Entry]
    }

    private var cache: [URL: Parsed] = [:]

    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
    }

    func usage(sessionEndsAt: Date?, now: Date, root: URL? = nil) -> LocalUsage? {
        let dayStart = Calendar.current.startOfDay(for: now)
        let reset = sessionEndsAt.flatMap { $0 > now ? $0 : nil }
        let sessionStart = (reset ?? now) - Config.sessionWindow
        let entries = entries(in: root ?? Self.defaultRoot, since: min(dayStart, sessionStart))
        guard !entries.isEmpty else { return nil }
        var seen = Set<String>()
        var result = LocalUsage(todayNew: 0, todayCached: 0, todayCost: 0,
                                sessionNew: 0, sessionCached: 0, sessionCost: 0, newPerMinute: 0,
                                sessionLabel: reset == nil ? "Last 5h" : "Session",
                                todayCostComplete: true, sessionCostComplete: true)
        for entry in entries where entry.at <= now {
            guard seen.insert(entry.id).inserted else { continue }
            if entry.at >= dayStart {
                result.todayNew += entry.new
                result.todayCached += entry.cached
                result.todayCost += entry.cost ?? 0
                if entry.cost == nil { result.todayCostComplete = false }
            }
            if entry.at >= sessionStart {
                result.sessionNew += entry.new
                result.sessionCached += entry.cached
                result.sessionCost += entry.cost ?? 0
                if entry.cost == nil { result.sessionCostComplete = false }
            }
        }
        result.newPerMinute = Double(result.sessionNew) / (max(60, now.timeIntervalSince(sessionStart)) / 60)
        return result
    }

    private func entries(in root: URL, since: Date) -> [Entry] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var found: [Entry] = []
        var paths = Set<URL>()
        for directory in ["sessions", "archived_sessions"] {
            guard let walker = FileManager.default.enumerator(
                at: root.appending(path: directory), includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= since,
                      let size = values.fileSize else { continue }
                paths.insert(url)
                if let hit = cache[url], hit.modified == modified, hit.size == size {
                    found += hit.entries
                } else {
                    let entries = Self.parse(url)
                    cache[url] = Parsed(modified: modified, size: size, entries: entries)
                    found += entries
                }
            }
        }
        cache = cache.filter { paths.contains($0.key) }
        return found
    }

    private static func parse(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var thread: String?
        var models: [String: String] = [:]
        var found: [Entry] = []
        for line in text.split(separator: "\n") {
            guard line.contains("\"session_meta\"") || line.contains("\"turn_context\"")
                    || line.contains("\"token_usage_record\""),
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { continue }
            switch json["type"] as? String {
            case "session_meta": thread = payload["id"] as? String
            case "turn_context":
                if let turn = payload["turn_id"] as? String {
                    models[turn] = payload["model"] as? String
                }
            case "token_usage_record":
                // Forks copy old records with new dates. Count each response in its own thread.
                guard let thread, payload["thread_id"] as? String == thread,
                      let response = payload["response_id"] as? String, !response.isEmpty,
                      let turn = payload["turn_id"] as? String,
                      let usage = payload["usage"] as? [String: Any],
                      let timestamp = json["timestamp"] as? String,
                      let at = isoParser.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp),
                      let input = usage["input_tokens"] as? Int, input >= 0,
                      let output = usage["output_tokens"] as? Int, output >= 0,
                      let cached = usage["cached_input_tokens"] as? Int, cached >= 0, cached <= input,
                      output <= Int.max - input else { continue }
                let cacheWrite = usage["cache_write_input_tokens"] as? Int ?? 0
                guard cacheWrite >= 0, cacheWrite <= input - cached else { continue }
                let cost = CodexModelPricing.cost(model: models[turn] ?? "", input: input,
                                                 cached: cached, cacheWrite: cacheWrite, output: output)
                found.append(Entry(id: "\(thread):\(response)", at: at,
                                   new: input - cached + output, cached: cached, cost: cost))
            default: break
            }
        }
        return found
    }

    private static let isoParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()
}
