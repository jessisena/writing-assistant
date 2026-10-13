import SwiftUI
import WritingAssistantCore

// Stub from Phase 0 — W5 replaces the body. Keep `init(store:)`.
struct PromptEditorView: View {
    let store: any PromptStoring

    init(store: any PromptStoring) {
        self.store = store
    }

    var body: some View {
        Text("Prompt editor")
    }
}
