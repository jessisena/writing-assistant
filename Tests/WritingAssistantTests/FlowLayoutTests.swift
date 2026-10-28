import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct FlowPlacementTests {
    private func place(_ widths: [CGFloat], in width: CGFloat) -> FlowPlacement {
        FlowPlacement(
            sizes: widths.map { CGSize(width: $0, height: 20) },
            width: width,
            horizontalSpacing: 8,
            verticalSpacing: 6
        )
    }

    @Test func itemsThatFitStayOnOneRow() {
        let placement = place([50, 60, 70], in: 300)

        #expect(
            placement.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 58, y: 0), CGPoint(x: 126, y: 0)])
        #expect(placement.size == CGSize(width: 196, height: 20))
    }

    @Test func itemWrapsWhenItWouldCrossTheWidth() {
        let placement = place([100, 100, 100], in: 220)

        #expect(
            placement.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0), CGPoint(x: 0, y: 26)])
        #expect(placement.size == CGSize(width: 208, height: 46))
    }

    @Test func itemExactlyFillingTheRowStaysOnIt() {
        let placement = place([96, 96], in: 200)

        #expect(placement.origins[1] == CGPoint(x: 104, y: 0))
    }

    @Test func itemWiderThanTheWidthGetsItsOwnRow() {
        let placement = place([50, 400, 50], in: 200)

        #expect(
            placement.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 26), CGPoint(x: 0, y: 52)])
    }

    @Test func emptyInputHasNoSize() {
        #expect(place([], in: 200).size == .zero)
    }

    @Test func unboundedWidthKeepsEverythingOnOneRow() {
        let placement = place([100, 100, 100], in: .infinity)

        #expect(placement.origins.allSatisfy { $0.y == 0 })
    }
}

@Suite struct InputLengthTests {
    @Test func shortInputCountsItsCharacters() {
        #expect(InputLength.scalars(in: NSAttributedString(string: "hello")) == 5)
    }

    @Test func formattedInputCountsItsMarkdownNotItsPlainText() {
        let source = String(repeating: "**bold** [link](https://example.com/a) ", count: 50)
        let input = RichTextBridge.nsAttributedString(
            from: RichText.attributedString(fromMarkdown: source))
        let pipelineInput = RichText.markdown(from: RichTextBridge.attributedString(from: input))
        let expected = pipelineInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.count

        #expect(InputLength.scalars(in: input) == expected)
        #expect(expected > input.length)
    }

    @Test func longInputIsTrimmedLikeThePipelineDoes() {
        let text = String(repeating: "a", count: 9_000) + "   \n"

        #expect(InputLength.scalars(in: NSAttributedString(string: text)) == 9_000)
    }
}
