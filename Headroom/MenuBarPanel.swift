import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Headroom")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await model.refresh(allowPrompt: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .opacity(model.isRefreshing ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
            }

            if let snapshot = model.snapshot, !snapshot.buckets.isEmpty {
                VStack(spacing: 10) {
                    ForEach(snapshot.buckets) { UsageBar(bucket: $0) }
                }
                UsageFooter(snapshot: snapshot)
            } else if let error = model.snapshot?.error {
                UsageUnavailable(message: error)
            } else {
                Text("Loading usage...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let local = model.snapshot?.local {
                Divider()
                usage(local)
            }

            if model.notificationsDenied {
                notificationsOff
            }

            if model.needsReconnect {
                reconnect
            }

            Divider()

            HStack {
                Toggle("Notify me", isOn: $model.notificationsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    @ViewBuilder
    private func usage(_ local: LocalUsage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("USAGE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            usageRow("Session", tokens: local.sessionNew, cost: local.sessionCost)
            usageRow("Today", tokens: local.todayNew, cost: local.todayCost)
            detailRow("Cache reads", "\(Self.compact(local.sessionCached)) this session")
            detailRow("Burn rate", "\(Self.compact(Int(local.newPerMinute))) new/min")
            Text("new tokens; cost at API list prices")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func usageRow(_ label: String, tokens: Int, cost: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(Self.compact(tokens))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // List prices are USD, so pin the locale. A non-US one renders "USD 12.34".
            Text(cost.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 66, alignment: .trailing)
        }
    }

    private static func compact(_ tokens: Int) -> String {
        let value = Double(tokens)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return "\(tokens)"
    }

    private var notificationsOff: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.orange)
            Text("Notifications are off")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Open Settings") {
                let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            }
            .font(.system(size: 11))
        }
    }

    private var reconnect: some View {
        HStack(spacing: 6) {
            Image(systemName: "key")
                .foregroundStyle(.orange)
            Text("Claude Code rotated its token")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Reconnect") { Task { await model.refresh(allowPrompt: true) } }
                .font(.system(size: 11))
                .disabled(model.isRefreshing)
        }
    }
}
