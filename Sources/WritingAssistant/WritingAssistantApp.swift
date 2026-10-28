import AppKit
import SwiftUI
import WritingAssistantCore

@main
struct WritingAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    private let store: PromptStore
    private let newerDefaults: Set<PromptFile>

    init() {
        let store = PromptStore.standard()
        let model = AppModel(polisher: PolishService(runner: ClaudeCLI(), prompts: store))
        var newerDefaults: Set<PromptFile> = []
        do {
            try store.seedMissingDefaults()
            newerDefaults = try store.syncDefaults()
        } catch {
            model.showStartupError(error)
        }
        self.store = store
        self.newerDefaults = newerDefaults
        _model = State(initialValue: model)
        appDelegate.model = model
    }

    var body: some Scene {
        Window("Writing Assistant", id: ServiceProvider.mainWindowID) {
            MainWindowView(model: model)
                .frame(minWidth: 600, minHeight: 500)
                .tint(Theme.ink)
                .task { await model.checkReadiness() }
                .handsMainWindowOpener(to: appDelegate)
        }
        .defaultSize(width: 820, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            FormatCommands()
            LearningLogCommands(model: model)
        }

        Settings {
            PromptEditorView(store: store, newerDefaults: newerDefaults)
                .handsMainWindowOpener(to: appDelegate)
        }
    }
}

/// Gives the app delegate a way to open the main window. Only SwiftUI views can open a scene,
/// and the service needs it after the main window was closed.
private struct MainWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate

    func body(content: Content) -> some View {
        content.onAppear {
            let openWindow = openWindow
            appDelegate.openMainWindow = { openWindow(id: ServiceProvider.mainWindowID) }
        }
    }
}

extension View {
    fileprivate func handsMainWindowOpener(to appDelegate: AppDelegate) -> some View {
        modifier(MainWindowOpener(appDelegate: appDelegate))
    }
}

/// "Open Learning Log" in the app menu, below Settings.
struct LearningLogCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Open Learning Log") { model.openLearningLog() }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Model the Services menu sends selected text to. Set by `WritingAssistantApp.init`.
    var model: AppModel?
    /// Opens the main window. Set by the main window and the Settings window when they appear.
    var openMainWindow: (@MainActor () -> Void)?
    private var serviceProvider: ServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        registerServiceProvider()
    }

    private func registerServiceProvider() {
        guard let model else {
            assertionFailure("AppDelegate.model must be set before the app finishes launching")
            return
        }
        let provider = ServiceProvider(model: model) { [weak self] in
            ServiceProvider.bringMainWindowForward(openMainWindow: self?.openMainWindow)
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClaudeCLI.terminateRunningProcesses()
    }
}

/// The single stacked column: composer, error banner, results, on the desk.
struct MainWindowView: View {
    let model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ComposerView(model: model)
                    if let message = model.errorMessage {
                        ErrorBanner(message: message)
                    }
                    ResultsView(model: model)
                        .id(Self.resultsID)
                }
                .frame(maxWidth: 720)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.result) { _, newValue in
                guard newValue != nil else { return }
                withAnimation { proxy.scrollTo(Self.resultsID, anchor: .bottom) }
            }
        }
        .background(Theme.desk)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { HistoryButton(model: model) }
        }
    }

    private static let resultsID = "results"
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.red.opacity(0.35)))
            .accessibilityLabel("Error: \(message)")
            .onAppear { announce(message) }
            .onChange(of: message) { _, newValue in announce(newValue) }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
