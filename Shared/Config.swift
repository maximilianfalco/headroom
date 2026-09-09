import Foundation

/// Every tunable in one place. Bundle identifiers come from the build, not from here.
enum Config {
    /// Keychain item Claude Code stores its OAuth credentials under.
    static let keychainService = "Claude Code-credentials"

    /// Claude Code's session logs, relative to home. Token counts and cost come from here.
    static let claudeProjectsPath = ".claude/projects"
    /// The session limit runs on a five hour window, which the local block is aligned to.
    static let sessionWindow: TimeInterval = 5 * 3600
    /// The weekly limits, per model ones included, run on a seven day window.
    static let weeklyWindow: TimeInterval = 7 * 86_400

    /// No projection until this share of a window has passed. Before that one burst scales
    /// to an absurd number.
    static let projectionWarmup = 0.03
    /// The session pace is read over this span, so it follows what you are doing now.
    static let projectionTrailing: TimeInterval = 30 * 60
    /// A trailing sample younger than this gives a pace too noisy to use.
    static let projectionTrailingMinimum: TimeInterval = 5 * 60
    /// `resets_at` drifts by seconds between polls. Closer than this is the same window.
    static let resetMatchTolerance: TimeInterval = 60
    /// Samples older than this are dropped. A day is enough history to learn the ratio.
    static let sampleRetention: TimeInterval = 24 * 3600
    /// Points of paired history needed before the token ratio is trusted.
    static let ratioMinimumPoints = 5

    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let oauthBetaHeader = "oauth-2025-04-20"
    static let requestTimeout: TimeInterval = 20
    /// Tokens are retired this early, so a poll never spends a request on a token that just died.
    static let tokenExpiryMargin: TimeInterval = 60
    /// What Claude Code allows its own lookup, and long enough that a slow read still lands.
    static let keychainReadTimeout: TimeInterval = 5

    static let pollInterval: Duration = .seconds(60)

    /// WidgetKit refreshes on its own budget, so this only matters when the app is not running.
    static let widgetFallbackRefresh: TimeInterval = 900
    static let widgetKind = "HeadroomLimit"

    static let warningAt = 80
    static let criticalAt = 95

    static let notifyThresholds = [80, 95, 100]
    /// Resets from below this are not worth interrupting for.
    static let resetNoticeFloor = 50
    /// Percentage drop that counts as a window reset rather than noise.
    static let resetDropMargin = 5
    /// Play a sound at or above this level.
    static let soundAt = 95
}
