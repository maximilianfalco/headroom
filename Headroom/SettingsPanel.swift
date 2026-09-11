import SwiftUI

/// The Settings window, reached from the gear in the panel or with Cmd+comma. Anything that is
/// set once and then forgotten belongs here rather than in the popover.
struct SettingsPanel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                form
                // The popover dismisses the moment this window takes focus, so the choice has
                // to be previewable here or it cannot be seen while it is being made.
                preview
            }
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preview: some View {
        VStack(spacing: 8) {
            SpriteView(kind: model.spriteKind, fill: model.worstFill,
                       danger: model.worstDanger, motion: model.spriteMotion, cell: 7)
            Text(model.spriteMotion == .follow
                 ? "\(Int(model.worstFill * 100))\(model.percentDisplay == .used ? "% used" : "% left")"
                 : "sweeping")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 98)
        .padding(.vertical, 20)
        .padding(.trailing, 20)
    }

    private var buckets: [UsageBucket] { model.snapshot?.buckets ?? [] }

    /// A picked limit that is not in the snapshot reads as highest, which is what it shows.
    private var menuBarLimit: Binding<String> {
        Binding(
            get: { buckets.contains { $0.key == model.menuBarLimit } ? model.menuBarLimit : "" },
            set: { model.menuBarLimit = $0 }
        )
    }

    private var form: some View {
        Form {
            Section("Percentages") {
                Picker("Show", selection: $model.percentDisplay) {
                    ForEach(PercentDisplay.allCases) { Text($0.label).tag($0) }
                }
                Text(model.percentDisplay == .used
                     ? "How much of each limit you have spent."
                     : "How much of each limit you have left. Colours still warn near the cap.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Show", selection: menuBarLimit) {
                    Text("Highest limit").tag("")
                    ForEach(buckets) { Text($0.label).tag($0.key) }
                }
                Text(menuBarLimit.wrappedValue.isEmpty
                     ? "Whichever limit is closest to its cap."
                     : "Always this limit, even when another is closer to its cap.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Sprite") {
                Picker("Show", selection: $model.spriteKind) {
                    ForEach(SpriteKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Level", selection: $model.spriteMotion) {
                    ForEach(SpriteMotion.allCases) { Text($0.label).tag($0) }
                }
                Text(model.spriteMotion == .follow
                     ? "Tracks whichever limit is closest to its cap."
                     : "Sweeps the whole range on a loop, ignoring your usage.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify me at 80%, 95% and 100%", isOn: $model.notificationsEnabled)
                if model.notificationsDenied {
                    HStack(spacing: 6) {
                        Text("Turned off in System Settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Open") {
                            let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                            if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 400)
    }
}
