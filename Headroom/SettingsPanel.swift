import SwiftUI

/// The Settings window, reached from the gear in the panel or with Cmd+comma. Anything that is
/// set once and then forgotten belongs here rather than in the popover.
struct SettingsPanel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            form
            // The popover dismisses the moment this window takes focus, so the choice has to
            // be previewable here or it cannot be seen while it is being made.
            preview
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            SpriteView(kind: model.spriteKind, fill: model.worstFill,
                       motion: model.spriteMotion, cell: 7)
            Text(model.spriteMotion == .follow
                 ? "\(Int(model.worstFill * 100))% used"
                 : "sweeping")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 98)
        .padding(.vertical, 20)
        .padding(.trailing, 20)
    }

    private var form: some View {
        Form {
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
        .frame(width: 400)
    }
}
