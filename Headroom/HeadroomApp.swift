import SwiftUI

@main
struct HeadroomApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(bucket: model.snapshot?.limit(model.menuBarLimit),
                         display: model.percentDisplay)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPanel(model: model)
        }
    }
}

private struct MenuBarLabel: View {
    let bucket: UsageBucket?
    let display: PercentDisplay

    var body: some View {
        if let bucket {
            // One font on the stack so the symbol shares the text baseline and scale.
            HStack(spacing: 3) {
                Image(systemName: bucket.severity == .normal ? "circle.fill" : "exclamationmark.circle.fill")
                    .imageScale(.small)
                Text(bucket.shownText(display))
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 12, weight: .medium))
        }
    }
}
