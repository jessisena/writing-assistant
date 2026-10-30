import AppKit
import SwiftUI
import WritingAssistantCore

/// The `Work | Personal` toolbar control. Disabled while a request runs (see
/// `AppModel.canSwitchMode`).
struct ModePicker: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Picker("Mode", selection: selection) {
            ForEach(Mode.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(!model.canSwitchMode)
        .help("Switch between Work and Personal (⌘⇧M)")
    }

    private var selection: Binding<Mode> {
        Binding(
            get: { model.mode },
            set: { mode in
                ModeSwitchAnimation.perform(reduceMotion: reduceMotion) {
                    model.switchMode(to: mode)
                }
            })
    }
}

/// The crossfade of the chips and the shift of the tint when the mode changes.
enum ModeSwitchAnimation {
    static let animation = Animation.easeInOut(duration: 0.3)

    @MainActor static func perform(reduceMotion: Bool, _ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(animation, change)
        }
    }
}

/// "Switch to Personal/Work Mode" (⌘⇧M) in the View menu.
struct ModeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Switch to \(model.mode.toggled.displayName) Mode") {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ModeSwitchAnimation.perform(reduceMotion: reduceMotion) { model.toggleMode() }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!model.canSwitchMode)
            Divider()
        }
    }
}
