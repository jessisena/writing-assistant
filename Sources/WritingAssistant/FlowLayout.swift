import SwiftUI

/// Places subviews left to right and wraps to a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placement = placement(for: subviews, width: proposal.width ?? .infinity)
        return placement.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let placement = placement(for: subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, placement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func placement(for subviews: Subviews, width: CGFloat) -> FlowPlacement {
        FlowPlacement(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: width,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
    }
}

/// Where `FlowLayout` puts items of the given sizes in a row width. An item wider than the
/// width gets a row of its own.
struct FlowPlacement: Equatable {
    /// The top-left corner of each item, in the order of the sizes.
    private(set) var origins: [CGPoint] = []
    /// The bounding size of all rows.
    private(set) var size: CGSize = .zero

    init(sizes: [CGSize], width: CGFloat, horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for itemSize in sizes {
            if x > 0 && x + itemSize.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += itemSize.width
            usedWidth = max(usedWidth, x)
            x += horizontalSpacing
            rowHeight = max(rowHeight, itemSize.height)
        }
        size = CGSize(width: usedWidth, height: sizes.isEmpty ? 0 : y + rowHeight)
    }
}
