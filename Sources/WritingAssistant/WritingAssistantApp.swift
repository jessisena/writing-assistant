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
    }

    var body: some Scene {
        Window("Writing Assistant", id: "main") {
            MainWindowView(model: model)
                .frame(minWidth: 600, minHeight: 500)
                .task { await model.checkReadiness() }
        }
        .defaultSize(width: 820, height: 780)
        .windowResizability(.contentMinSize)
        .commands { FormatCommands() }

        Settings {
            PromptEditorView(store: store, newerDefaults: newerDefaults)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClaudeCLI.terminateRunningProcesses()
    }
}

/// The single stacked column: header, composer, error banner, results.
struct MainWindowView: View {
    let model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Header()
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
    }

    private static let resultsID = "results"
}

private struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Writing Assistant")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Paste your text, choose a channel, and get polished English.")
                .foregroundStyle(.secondary)
        }
    }
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
