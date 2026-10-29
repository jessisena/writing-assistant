import AppKit

/// Handles the "Polish with Writing Assistant" service, which other apps offer for selected text
/// in their Services menu.
///
/// The service sends the selection to the app and doesn't return a replacement: a request takes
/// longer than the calling app waits for a service.
@MainActor final class ServiceProvider: NSObject {
    static let busyMessage =
        "A request is already running. Wait for it to finish or cancel it, then try again."
    static let emptySelectionMessage =
        "Select some text before choosing Polish with Writing Assistant."
    static let mainWindowID = "main"

    private let model: AppModel
    private let activate: @MainActor () -> Void

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - model: Model that receives the selected text.
    ///   - activate: Brings the app and its main window forward, usually by calling
    ///     `bringMainWindowForward(openMainWindow:)`.
    init(model: AppModel, activate: @escaping @MainActor () -> Void) {
        self.model = model
        self.activate = activate
    }

    /// Entry point for the service, named by `NSMessage` in Info.plist.
    ///
    /// - Parameters:
    ///   - pboard: Pasteboard holding the selection.
    ///   - userData: The `NSUserData` value from Info.plist; unused.
    ///   - error: Receives a message for the calling app when there is no text.
    @objc func polish(
        _ pboard: NSPasteboard, userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        if let failure = handle(pboard) {
            error.pointee = failure as NSString
        }
    }

    /// Loads the pasteboard's text into the model (see `AppModel.loadInput(_:)`) without
    /// polishing it: the user reviews the text and the channel, then clicks Polish. While a
    /// request is running, the input is kept and a banner explains why nothing was loaded.
    ///
    /// - Parameter pboard: Pasteboard holding the selection.
    /// - Returns: A message for the calling app when the pasteboard has no text, otherwise nil.
    func handle(_ pboard: NSPasteboard) -> String? {
        guard let text = Self.text(from: pboard) else { return Self.emptySelectionMessage }
        if model.isLoading {
            model.showBanner(Self.busyMessage)
        } else {
            model.loadInput(text)
        }
        activate()
        return nil
    }

    /// Reads the selection from a pasteboard, preferring rich text, which is normalized to the
    /// formatting the editor supports.
    ///
    /// - Parameter pboard: Pasteboard holding the selection.
    /// - Returns: The text, or nil when the pasteboard has no text or only whitespace.
    static func text(from pboard: NSPasteboard) -> NSAttributedString? {
        let text: NSAttributedString
        if let data = pboard.data(forType: .rtf),
            let rich = NSAttributedString(rtf: data, documentAttributes: nil)
        {
            text = RichTextBridge.normalized(rich)
        } else if let plain = pboard.string(forType: .string) {
            text = NSAttributedString(string: plain, attributes: RichTextBridge.baseAttributes)
        } else {
            return nil
        }
        let isBlank = text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isBlank ? nil : text
    }

    /// Activates the app and brings the main window to the front, reopening it when it was closed
    /// (for example while the Settings window kept the app running). When the service launched
    /// the app, SwiftUI opens the main window on its own.
    ///
    /// - Parameter openMainWindow: Opens the main window; nil until a SwiftUI view has handed
    ///   one over.
    static func bringMainWindowForward(openMainWindow: (@MainActor () -> Void)?) {
        NSApp.activate()
        showMainWindow(in: NSApp.windows, openMainWindow: openMainWindow)
    }

    /// Brings the main window to the front when it is among `windows`, otherwise opens it.
    ///
    /// SwiftUI gives the NSWindow of `Window(id:)` that id as its identifier.
    ///
    /// - Parameters:
    ///   - windows: The app's windows.
    ///   - openMainWindow: Opens the main window when it isn't among `windows`.
    static func showMainWindow(in windows: [NSWindow], openMainWindow: (@MainActor () -> Void)?) {
        if let window = windows.first(where: { $0.identifier?.rawValue == mainWindowID }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}
