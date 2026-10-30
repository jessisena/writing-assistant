import SwiftUI

/// A capsule button on the paper: the channel chips and the refine buttons. It presses in to 97%
/// and lifts a point on hover. A selected chip draws the ink pill; pass the namespace of a chip
/// group so the pill slides from the old selection to the new one.
struct ChipStyle: ButtonStyle {
    var isSelected = false
    var selectionNamespace: Namespace.ID?

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            selectionNamespace: selectionNamespace
        ) {
            configuration.label
        }
    }
}

private struct ChipBody<Label: View>: View {
    let isSelected: Bool
    let isPressed: Bool
    let selectionNamespace: Namespace.ID?
    @ViewBuilder let label: Label
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isLifted: Bool { isHovered && isEnabled && !isPressed }

    var body: some View {
        label
            .font(.callout)
            .foregroundStyle(isSelected ? theme.ink : Color.primary)
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background { background }
            .contentShape(Capsule())
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1)
            .offset(y: isLifted ? -1 : 0)
            .shadow(color: .black.opacity(isLifted ? 0.08 : 0), radius: 2, y: 1)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isSelected)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isLifted)
    }

    private var background: some View {
        ZStack {
            Capsule().fill(fill)
            Capsule().strokeBorder(theme.rule, lineWidth: 1)
            if isSelected {
                selectionPill
            }
        }
    }

    @ViewBuilder private var selectionPill: some View {
        let pill = Capsule()
            .fill(theme.ink.opacity(0.15))
            .overlay(Capsule().strokeBorder(theme.ink, lineWidth: 1))
        if let selectionNamespace {
            pill.matchedGeometryEffect(id: "chip-selection", in: selectionNamespace)
        } else {
            pill
        }
    }

    private var fill: Color {
        guard isEnabled, !isSelected else { return .clear }
        if isPressed { return Color.primary.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }
}
