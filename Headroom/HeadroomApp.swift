import SwiftUI

@main
struct HeadroomApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPanel(model: model)
        }
    }
}

private struct MenuBarLabel: View {
    let snapshot: UsageSnapshot?

    var body: some View {
        if let worst = snapshot?.worst {
            // One font on the stack so the symbol shares the text baseline and scale.
            HStack(spacing: 3) {
                Image(systemName: worst.severity == .normal ? "circle.fill" : "exclamationmark.circle.fill")
                    .imageScale(.small)
                // Remaining rather than consumed, matching the app's name.
                Text("\(100 - worst.percent)% left")
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 12, weight: .medium))
        }
    }
}
