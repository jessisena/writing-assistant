import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct ServiceProviderTests {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeProvider(
        _ polisher: any Polishing, activations: @escaping @MainActor () -> Void = {}
    ) -> (ServiceProvider, AppModel) {
        let model = AppModel.testing(polisher: polisher)
        return (ServiceProvider(model: model, activate: activations), model)
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    private func rtfData(_ text: NSAttributedString) throws -> Data {
        try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    @Test func readsPlainText() {
        let pasteboard = makePasteboard()
        pasteboard.setString("I will to review the doc", forType: .string)

        let text = ServiceProvider.text(from: pasteboard)

        #expect(text?.string == "I will to review the doc")
    }

    @Test func readsRichTextNormalizedKeepingBoldAndDroppingColors() throws {
        let source = NSMutableAttributedString(
            string: "Hello ",
            attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.red])
        source.append(
            NSAttributedString(
                string: "world",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: NSColor.blue,
                ]))
        let pasteboard = makePasteboard()
        pasteboard.setData(try rtfData(source), forType: .rtf)
        pasteboard.setString("plain fallback", forType: .string)

        let text = try #require(ServiceProvider.text(from: pasteboard))

        #expect(markdown(text) == "Hello **world**")
        let baseColor = RichTextBridge.baseAttributes[.foregroundColor] as? NSColor
        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: range) { value, _, _ in
            #expect(value as? NSColor == baseColor)
        }
    }

    @Test(arguments: ["", "  \n\t "])
    func blankOrEmptyPasteboardReadsNothing(content: String) {
        let pasteboard = makePasteboard()
        if !content.isEmpty {
            pasteboard.setString(content, forType: .string)
        }

        #expect(ServiceProvider.text(from: pasteboard) == nil)
    }

    @Test func polishLoadsTextStartsProcessingAndActivates() async {
        let polisher = GatedPolisher()
        var activations = 0
        let (provider, model) = makeProvider(polisher) { activations += 1 }
        let pasteboard = makePasteboard()
        pasteboard.setString("Hello there", forType: .string)

        let failure = provider.handle(pasteboard)

        #expect(failure == nil)
        #expect(model.input.string == "Hello there")
        #expect(model.isLoading)
        #expect(activations == 1)
        while polisher.waitingCount == 0 { await Task.yield() }
        polisher.resume(0, with: .success(.sample))
        await model.requestTask?.value
        #expect(model.result == .sample)
    }

    @Test func emptyPasteboardReportsAnErrorAndLeavesTheModelAlone() {
        var activations = 0
        let (provider, model) = makeProvider(FakePolisher()) { activations += 1 }

        let failure = provider.handle(makePasteboard())

        #expect(failure == ServiceProvider.emptySelectionMessage)
        #expect(model.input.length == 0)
        #expect(!model.isLoading)
        #expect(activations == 0)
    }

    @Test func busyModelShowsBannerAndKeepsInput() async {
        let polisher = GatedPolisher()
        var activations = 0
        let (provider, model) = makeProvider(polisher) { activations += 1 }
        model.input = NSAttributedString(string: "First text")
        model.startProcessing()
        let pasteboard = makePasteboard()
        pasteboard.setString("Second text", forType: .string)

        let failure = provider.handle(pasteboard)

        #expect(failure == nil)
        #expect(model.input.string == "First text")
        #expect(model.errorMessage == ServiceProvider.busyMessage)
        #expect(model.isLoading)
        #expect(activations == 1)
        while polisher.waitingCount == 0 { await Task.yield() }
        polisher.resume(0, with: .success(.sample))
        await model.requestTask?.value
    }

    private func makeWindow(identifier: String) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        return window
    }

    @Test func opensTheMainWindowWhenItIsClosed() {
        var opens = 0
        let settings = makeWindow(identifier: "com_apple_SwiftUI_Settings_window")

        ServiceProvider.showMainWindow(in: [settings]) { opens += 1 }

        #expect(opens == 1)
    }

    @Test func missingOpenerLeavesTheWindowsAlone() {
        let settings = makeWindow(identifier: "com_apple_SwiftUI_Settings_window")

        ServiceProvider.showMainWindow(in: [settings], openMainWindow: nil)

        #expect(!settings.isVisible)
    }

    @Test func reusesTheOpenMainWindowInsteadOfOpeningAnother() {
        var opens = 0
        let main = makeWindow(identifier: ServiceProvider.mainWindowID)
        defer { main.close() }

        ServiceProvider.showMainWindow(in: [main]) { opens += 1 }

        #expect(opens == 0)
        #expect(main.isVisible)
    }
}
