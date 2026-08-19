import Foundation

/// Token counts and cost, read straight out of Claude Code's session logs. The usage endpoint
/// only reports percentages, so everything here comes from `~/.claude/projects/**/*.jsonl`
/// and needs no credentials at all.
actor LocalUsageReader {
    static let shared = LocalUsageReader()

    private struct Entry {
        let id: String
        let date: Date
        /// Generated, or entering the cache for the first time.
        let new: Int
        /// Prefix read back out of the cache.
        let cached: Int
        let cost: Double
    }

    private struct LogFile {
        let path: String
        let modified: Date
        let size: Int
    }

    /// Parsed entries per file, reused while the file is untouched. Only logs written since
    /// midnight are ever opened, and of those only the few that changed get reparsed, so a
    /// poll costs almost nothing after the first one.
    private struct Parsed {
        let modified: Date
        let size: Int
        let entries: [Entry]
    }

    private var cache: [String: Parsed] = [:]

    static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: Config.claudeProjectsPath)
    }

    /// `sessionEndsAt` is the five hour bucket's reset, which pins the window to the real
    /// session rather than to a rolling guess. A missing or already elapsed reset falls back
    /// to the last five hours.
    func usage(sessionEndsAt: Date?, now: Date, projectsRoot: URL? = nil) -> LocalUsage? {
        let dayStart = Calendar.current.startOfDay(for: now)
        let sessionStart = sessionEndsAt.flatMap { $0 > now ? $0 - Config.sessionWindow : nil }
            ?? now - Config.sessionWindow

        let files = logFiles(in: projectsRoot ?? Self.defaultProjectsRoot, modifiedSince: dayStart)
        guard !files.isEmpty else { return nil }

        var seen = Set<String>()
        var todayNew = 0, todayCached = 0, sessionNew = 0, sessionCached = 0
        var todayCost = 0.0, sessionCost = 0.0

        for file in files {
            for entry in entries(for: file) {
                guard entry.date >= dayStart, seen.insert(entry.id).inserted else { continue }
                todayNew += entry.new
                todayCached += entry.cached
                todayCost += entry.cost
                if entry.date >= sessionStart {
                    sessionNew += entry.new
                    sessionCached += entry.cached
                    sessionCost += entry.cost
                }
            }
        }

        let paths = Set(files.map(\.path))
        cache = cache.filter { paths.contains($0.key) }

        let elapsed = max(60, now.timeIntervalSince(sessionStart)) / 60
        return LocalUsage(todayNew: todayNew, todayCached: todayCached, todayCost: todayCost,
                          sessionNew: sessionNew, sessionCached: sessionCached,
                          sessionCost: sessionCost,
                          newPerMinute: Double(sessionNew) / elapsed)
    }

    private func logFiles(in root: URL, modifiedSince: Date) -> [LogFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        var found: [LogFile] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= modifiedSince,
                  let size = values.fileSize
            else { continue }
            found.append(LogFile(path: url.path, modified: modified, size: size))
        }
        return found
    }

    private func entries(for file: LogFile) -> [Entry] {
        if let hit = cache[file.path], hit.modified == file.modified, hit.size == file.size {
            return hit.entries
        }
        let parsed = Self.parse(path: file.path)
        cache[file.path] = Parsed(modified: file.modified, size: file.size, entries: parsed)
        return parsed
    }

    private static func parse(path: String) -> [Entry] {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        var found: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Most lines are user turns and tool output. Skipping them here keeps the JSON
            // parse off ~99% of a day's logs, which is what makes a full rescan affordable.
            guard line.contains("\"assistant\""), let entry = entry(from: Data(line.utf8)) else {
                continue
            }
            found.append(entry)
        }
        return found
    }

    private static func entry(from data: Data) -> Entry? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let date = date(from: json["timestamp"] as? String)
        else { return nil }

        let creation = usage["cache_creation"] as? [String: Any]
        let write5m = creation?["ephemeral_5m_input_tokens"] as? Int ?? 0
        let write1h = creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
        let recorded = usage["cache_creation_input_tokens"] as? Int ?? 0
        // Lines without the TTL split carry only a total, which bills at the five minute rate.
        let split = write5m + write1h
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        let cost = ModelPricing.cost(
            model: message["model"] as? String ?? "",
            fastMode: usage["speed"] as? String == "fast",
            input: input, output: output,
            cacheWrite5m: split > 0 ? write5m : recorded,
            cacheWrite1h: write1h,
            cacheRead: cacheRead)

        // Resumed sessions and sidechains replay the same message into several files.
        let id = "\(message["id"] as? String ?? "")|\(json["requestId"] as? String ?? "")"
        return Entry(id: id, date: date,
                     new: input + output + (split > 0 ? split : recorded),
                     cached: cacheRead,
                     cost: cost)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoParser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
