import SwiftUI

extension Severity {
    var tint: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Circular gauge used as the hero element in the small widget.
struct UsageRing: View {
    let bucket: UsageBucket
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(bucket.severity.tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, Double(bucket.percent) / 100))
                .stroke(bucket.severity.tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(bucket.percent)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Horizontal bar row used in the medium widget and the menu bar panel.
struct UsageBar: View {
    let bucket: UsageBucket

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(bucket.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if let resets = bucket.resetsIn {
                    Text(resets)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Text("\(bucket.percent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(bucket.severity.tint)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(bucket.severity.tint.opacity(0.18))
                    Capsule()
                        .fill(bucket.severity.tint)
                        .frame(width: geo.size.width * min(1, Double(bucket.percent) / 100))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Timestamp, or the error standing in for it. Shared so the panel and the large widget
/// annotate a stale snapshot the same way.
struct UsageFooter: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 4) {
            if let error = snapshot.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error)
            } else {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }
}

struct UsageUnavailable: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}
