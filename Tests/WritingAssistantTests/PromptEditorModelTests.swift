import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct PromptEditorModelTests {
    private let defaultGlobal = "Rules\n\(PromptFile.channelPlaceholder)"

    private func makeModel(_ store: FakePromptStore = FakePromptStore()) -> PromptEditorModel {
        let model = PromptEditorModel(store: store)
        model.reload()
        return model
    }

    @Test func startsOnGlobalRulesWithItsText() {
        let model = makeModel()
        #expect(model.selection == .global)
        #expect(model.draft == defaultGlobal)
        #expect(!model.isDirty(.global))
        #expect(model.errorMessage == nil)
        #expect(model.fileURL.path == "/tmp/fake-prompts/polish.txt")
    }

    @Test func editingMarksDirtyAndRevertCleans() {
        let model = makeModel()
        model.draft = "edited \(PromptFile.channelPlaceholder)"
        #expect(model.isDirty(.global))
        #expect(model.isCurrentFileDirty)

        model.revert()
        #expect(!model.isDirty(.global))
        #expect(model.draft == defaultGlobal)
    }

    @Test func editingBackToSavedTextIsClean() {
        let model = makeModel()
        model.draft = "something else"
        model.draft = defaultGlobal
        #expect(!model.isDirty(.global))
    }

    @Test func draftsSurviveSwitchingFiles() {
        let model = makeModel()
        model.selection = .channel(.slack)
        model.draft = "new slack rules"
        model.selection = .channel(.formal)
        #expect(model.draft == "formal guidelines")
        #expect(!model.isDirty(.channel(.formal)))

        model.selection = .channel(.slack)
        #expect(model.draft == "new slack rules")
        #expect(model.isDirty(.channel(.slack)))
    }

    @Test func savePersistsAndClearsDirty() throws {
        let store = FakePromptStore()
        let model = makeModel(store)
        model.selection = .channel(.slack)
        model.draft = "new slack rules"

        model.save()

        #expect(try store.read(.channel(.slack)) == "new slack rules")
        #expect(!model.isDirty(.channel(.slack)))
        #expect(model.errorMessage == nil)
        #expect(model.draft == "new slack rules")
    }

    @Test func savingGlobalWithoutPlaceholderIsRejected() throws {
        let store = FakePromptStore()
        let model = makeModel(store)
        model.draft = "Rules without the placeholder"

        model.save()

        #expect(model.errorMessage == PromptValidationError.missingPlaceholder.errorDescription)
        #expect(model.draft == "Rules without the placeholder")
        #expect(model.isDirty(.global))
        #expect(try store.read(.global) == defaultGlobal)
    }

    @Test func savingEmptyTextIsRejected() throws {
        let store = FakePromptStore()
        let model = makeModel(store)
        model.selection = .channel(.other)
        model.draft = "  \n "

        model.save()

        #expect(model.errorMessage == PromptValidationError.empty.errorDescription)
        #expect(model.isDirty(.channel(.other)))
        #expect(try store.read(.channel(.other)) == "other guidelines")
    }

    @Test func successfulSaveClearsPreviousError() {
        let model = makeModel()
        model.draft = "no placeholder"
        model.save()
        #expect(model.errorMessage != nil)

        model.draft = "fixed \(PromptFile.channelPlaceholder)"
        model.save()
        #expect(model.errorMessage == nil)
        #expect(!model.isDirty(.global))
    }

    @Test func errorsAreShownOnlyForTheirFile() {
        let model = makeModel()
        model.draft = "no placeholder"
        model.save()
        model.selection = .channel(.slack)
        #expect(model.errorMessage == nil)
        model.selection = .global
        #expect(model.errorMessage != nil)
    }

    @Test func cancellingRestoreLeavesTextAlone() throws {
        let store = FakePromptStore()
        try store.write("custom slack", to: .channel(.slack))
        let model = makeModel(store)
        model.selection = .channel(.slack)
        model.draft = "unsaved edit"

        model.requestRestore()
        #expect(model.isConfirmingRestore)
        model.cancelRestore()

        #expect(!model.isConfirmingRestore)
        #expect(model.draft == "unsaved edit")
        #expect(try store.read(.channel(.slack)) == "custom slack")
    }

    @Test func confirmingRestoreBringsBackDefaultAndClearsDirty() throws {
        let store = FakePromptStore()
        try store.write("custom slack", to: .channel(.slack))
        let model = makeModel(store)
        model.selection = .channel(.slack)
        model.draft = "unsaved edit"

        model.requestRestore()
        model.confirmRestore()

        #expect(!model.isConfirmingRestore)
        #expect(model.draft == "slack guidelines")
        #expect(!model.isDirty(.channel(.slack)))
        #expect(try store.read(.channel(.slack)) == "slack guidelines")
    }

    @Test func switchingFilesDismissesRestoreConfirmation() {
        let model = makeModel()
        model.requestRestore()
        model.selection = .channel(.slack)
        #expect(!model.isConfirmingRestore)
    }

    @Test func reloadPicksUpExternalChangesForCleanFiles() throws {
        let store = FakePromptStore()
        let model = makeModel(store)
        try store.write("edited elsewhere", to: .channel(.formal))

        model.reload()

        model.selection = .channel(.formal)
        #expect(model.draft == "edited elsewhere")
        #expect(!model.isDirty(.channel(.formal)))
    }

    @Test func reloadKeepsUnsavedDrafts() throws {
        let store = FakePromptStore()
        let model = makeModel(store)
        model.selection = .channel(.formal)
        model.draft = "my draft"
        try store.write("edited elsewhere", to: .channel(.formal))

        model.reload()

        #expect(model.draft == "my draft")
        #expect(model.isDirty(.channel(.formal)))
    }

    @Test func readErrorIsShownWithFileName() throws {
        let model = makeModel(FakePromptStore(files: [.global: defaultGlobal]))

        #expect(model.errorMessage == nil)
        model.selection = .channel(.slack)
        let message = try #require(model.errorMessage)
        #expect(message.contains(Channel.slack.displayName))
        #expect(model.draft.isEmpty)
        #expect(!model.isCurrentFileEditable)
    }

    @Test func unreadableFileCannotBeEditedOrSaved() throws {
        let store = FakePromptStore(files: [.global: defaultGlobal])
        let model = makeModel(store)
        model.selection = .channel(.slack)
        let readError = try #require(model.errorMessage)

        model.draft = "typed into the unreadable file"
        model.save()

        #expect(model.draft.isEmpty)
        #expect(!model.isDirty(.channel(.slack)))
        #expect(model.errorMessage == readError)
        #expect(throws: (any Error).self) { try store.read(.channel(.slack)) }
    }

    @Test func restoringAnUnreadableFileRecovers() throws {
        let store = FakePromptStore(files: [.global: defaultGlobal])
        let model = makeModel(store)
        model.selection = .channel(.slack)

        model.requestRestore()
        model.confirmRestore()

        #expect(model.errorMessage == nil)
        #expect(model.isCurrentFileEditable)
        #expect(model.draft == "slack guidelines")
        #expect(try store.read(.channel(.slack)) == "slack guidelines")
    }

    @Test func editingClearsAnEarlierValidationError() {
        let model = makeModel()
        model.draft = "no placeholder"
        model.save()
        #expect(model.errorMessage != nil)

        model.draft = "no placeholder, still editing"

        #expect(model.errorMessage == nil)
        #expect(model.isDirty(.global))
    }
}
