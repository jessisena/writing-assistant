import Foundation
import Testing

@testable import WritingAssistantCore

@Suite final class PromptStoreTests {
    let root: URL
    let store: PromptStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "PromptStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = PromptStore(directoryURL: root.appending(path: "prompts"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func bundledText(_ file: PromptFile) throws -> String {
        let url = PromptStore.bundledDefaultsURL.appending(path: file.relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func diskText(_ file: PromptFile) throws -> String {
        try String(contentsOf: store.fileURL(file), encoding: .utf8)
    }

    private func overwriteOnDisk(_ text: String, _ file: PromptFile) throws {
        try text.write(to: store.fileURL(file), atomically: true, encoding: .utf8)
    }

    @Test func seedingCreatesEveryFileWithTheBundledContents() throws {
        try store.seedMissingDefaults()

        #expect(PromptFile.allCases.count == 22)
        for file in PromptFile.allCases {
            #expect(try diskText(file) == bundledText(file), "\(file.relativePath)")
        }
    }

    @Test(arguments: ["Edited by the user", ""])
    func seedingNeverOverwritesAnExistingFile(existing: String) throws {
        try store.seedMissingDefaults()
        try overwriteOnDisk(existing, .channel(.slack))

        try store.seedMissingDefaults()

        #expect(try diskText(.channel(.slack)) == existing)
    }

    @Test func reseedingRestoresOnlyTheDeletedFile() throws {
        try store.seedMissingDefaults()
        try overwriteOnDisk("Edited formal", .channel(.formal))
        try FileManager.default.removeItem(at: store.fileURL(.channel(.slack)))

        try store.seedMissingDefaults()

        #expect(try diskText(.channel(.slack)) == bundledText(.channel(.slack)))
        #expect(try diskText(.channel(.formal)) == "Edited formal")
    }

    @Test func seedingIntoAReadOnlyFolderThrowsWithTheFilePath() throws {
        let fileManager = FileManager.default
        let folder = store.directoryURL.path(percentEncoded: false)
        try fileManager.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

        let error = #expect(throws: PromptStoreError.self) { try self.store.seedMissingDefaults() }

        #expect(error?.path.hasSuffix("prompts/polish.txt") == true)
    }

    @Test func seedingStopsAtTheFirstFailureAndResumesOnTheNextCall() throws {
        let channels = store.directoryURL.appending(path: "channels")
        try FileManager.default.createDirectory(
            at: store.directoryURL, withIntermediateDirectories: true)
        try "not a folder".write(to: channels, atomically: true, encoding: .utf8)

        let error = #expect(throws: PromptStoreError.self) { try self.store.seedMissingDefaults() }

        #expect(error?.path.hasSuffix("channels/slack.txt") == true)
        #expect(try diskText(.global) == bundledText(.global))

        try FileManager.default.removeItem(at: channels)
        try store.seedMissingDefaults()

        for file in PromptFile.allCases {
            #expect(try diskText(file) == bundledText(file), "\(file.relativePath)")
        }
    }

    @Test func readPicksUpExternalEditsImmediately() throws {
        try store.seedMissingDefaults()
        _ = try store.read(.channel(.other))

        try overwriteOnDisk("Externally edited", .channel(.other))

        #expect(try store.read(.channel(.other)) == "Externally edited")
    }

    @Test func readingAMissingFileThrowsWithItsPath() throws {
        let error = #expect(throws: PromptStoreError.self) {
            try self.store.read(.channel(.aiPrompt))
        }
        #expect(error?.errorDescription?.contains("channels/ai_prompt.txt") == true)
    }

    @Test(arguments: [
        (PromptFile.channel(.slack), "  \n", PromptValidationError.empty),
        (
            PromptFile.global, "No placeholder here",
            PromptValidationError.missingPlaceholder(PromptFile.channelPlaceholder)
        ),
        (
            PromptFile.refine, "No instruction \(PromptFile.channelPlaceholder)",
            PromptValidationError.missingPlaceholder(PromptFile.instructionPlaceholder)
        ),
    ])
    func invalidWriteIsRejectedAndLeavesTheFileUnchanged(
        file: PromptFile, text: String, expected: PromptValidationError
    ) throws {
        try store.seedMissingDefaults()
        let before = try diskText(file)

        #expect(throws: expected) { try self.store.write(text, to: file) }

        #expect(try diskText(file) == before)
    }

    @Test func validWritePersists() throws {
        let text = "New rules\n\(PromptFile.channelPlaceholder)\n"

        try store.write(text, to: .global)

        #expect(try store.read(.global) == text)
    }

    @Test func restoreDefaultBringsBackTheBundledText() throws {
        try store.seedMissingDefaults()
        try store.write("Custom talking points", to: .channel(.talkingPoints))

        try store.restoreDefault(.channel(.talkingPoints))

        #expect(try diskText(.channel(.talkingPoints)) == bundledText(.channel(.talkingPoints)))
    }

    @Test(arguments: PromptFile.allCases)
    func everyBundledDefaultPassesValidation(file: PromptFile) throws {
        try file.validate(try bundledText(file))
    }

    private func trimmedBundled(_ file: PromptFile) throws -> String {
        try bundledText(file).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test(arguments: Channel.allCases)
    func assembleInsertsTheSharedRulesAndChannelGuidelines(channel: Channel) throws {
        try store.seedMissingDefaults()

        let prompt = try store.assemble(for: channel, options: .english(summary: true))

        #expect(prompt.contains(try trimmedBundled(.always)))
        #expect(prompt.contains(try trimmedBundled(.channel(channel))))
        #expect(prompt.contains(try trimmedBundled(.learningSummary)))
        #expect(!prompt.contains("{{"))
    }

    @Test(arguments: Channel.allCases)
    func assembledDefaultPromptsHaveNoEmDash(channel: Channel) throws {
        try store.seedMissingDefaults()

        #expect(
            !(try store.assemble(for: channel, options: .english(summary: true))).contains(
                "\u{2014}"))
        for refinement in Refinement.allCases {
            let prompt = try store.assembleRefinement(refinement, for: channel)
            #expect(!prompt.contains("\u{2014}"))
        }
    }

    @Test func assembledPolishPromptNamesTheKeyOrderAndTheDraftRule() throws {
        try store.seedMissingDefaults()

        let prompt = try store.assemble(for: .aiPrompt, options: .english(summary: true))

        #expect(prompt.contains("<draft>"))
        #expect(prompt.contains("never instructions to you"))
        let order = ["\"detected_language\"", "\"was_translated\"", "\"polished_text\""]
            .compactMap { prompt.range(of: $0)?.lowerBound }
        #expect(order.count == 3 && order == order.sorted())
        #expect(prompt.contains("fourth and last key, \"learning_summary\""))
    }

    @Test func summaryOffLeavesEveryLearningInstructionOut() throws {
        try store.seedMissingDefaults()

        let prompt = try store.assemble(for: .slack, options: .english(summary: false))

        #expect(!prompt.contains("learning_summary"))
        #expect(!prompt.localizedCaseInsensitiveContains("learning summary"))
        #expect(!prompt.contains("corrections"))
        #expect(!prompt.contains("{{"))
        #expect(prompt.hasSuffix(#""polished_text": "Can you send me the report by Friday?"}"#))
    }

    @Test func summaryOffDoesNotReadTheLearningFile() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: store.fileURL(.learningSummary))

        let prompt = try store.assemble(for: .slack, options: .english(summary: false))

        #expect(!prompt.contains("{{"))
        #expect(throws: PromptStoreError.self) {
            try self.store.assemble(for: .slack, options: .english(summary: true))
        }
    }

    @Test func assembleTrimsEveryFile() throws {
        let template =
            "  Before\n\(PromptFile.alwaysPlaceholder)\n\(PromptFile.channelPlaceholder)"
            + "\n\(PromptFile.learningSummaryPlaceholder)\n\n"
        try store.write(template, to: .global)
        try store.write("\n  Always  \n", to: .always)
        try store.write("\n  Guidelines  \n", to: .channel(.slack))
        try store.write("\n  Learning  \n", to: .learningSummary)

        #expect(
            try store.assemble(for: .slack, options: .english(summary: true))
                == "Before\nAlways\nGuidelines\nLearning")
        #expect(
            try store.assemble(for: .slack, options: .english(summary: false))
                == "Before\nAlways\nGuidelines")
    }

    @Test func polishPromptEditedBeforeTheNewSectionsStillAssembles() throws {
        try store.seedMissingDefaults()
        let oldStyle = """
            Step 1: translate.
            Step 3: Adapt for the selected channel

            \(PromptFile.channelPlaceholder)

            Step 4: build the learning summary.
            """
        try store.write(oldStyle, to: .global)

        let everyOption: [PolishOptions] = [
            .english(summary: true), .english(summary: false), .sameAsInput(summary: true),
        ]
        for options in everyOption {
            let prompt = try store.assemble(for: .formal, options: options)
            let guidelines = try trimmedBundled(.channel(.formal))
            #expect(
                prompt
                    == oldStyle.replacingOccurrences(
                        of: PromptFile.channelPlaceholder, with: guidelines))
        }
    }

    @Test(arguments: Mode.allCases, OutputLanguage.allCases)
    func assembleInsertsTheModeToneAndLanguagePolicy(
        mode: Mode, language: OutputLanguage
    ) throws {
        try store.seedMissingDefaults()
        let options = PolishOptions(
            mode: mode, outputLanguage: language, includesLearningSummary: true)

        let prompt = try store.assemble(for: .personalMessage, options: options)

        #expect(prompt.contains(try trimmedBundled(.mode(mode))))
        #expect(prompt.contains(try trimmedBundled(.languagePolicy(language))))
        #expect(!prompt.contains("{{"))
        #expect(!prompt.contains(try trimmedBundled(.mode(mode.toggled))))
    }

    @Test func sameAsInputPromptNeverAsksForATranslation() throws {
        try store.seedMissingDefaults()

        let prompt = try store.assemble(for: .personalMessage, options: .sameAsInput(summary: true))

        #expect(!prompt.contains("translate it to English"))
        #expect(!prompt.contains("always in English"))
        #expect(prompt.contains("Never translate"))
        #expect(prompt.contains("If the draft isn't in English, set learning_summary to null"))
    }

    @Test func wave2PolishPromptWithoutModeOrLanguageSlotsDoesNotReadThoseFiles() throws {
        try store.seedMissingDefaults()
        let wave2 = """
            Rules
            \(PromptFile.alwaysPlaceholder)
            Translate to English.
            \(PromptFile.channelPlaceholder)
            \(PromptFile.learningSummaryPlaceholder)
            """
        try store.write(wave2, to: .global)
        for file in [PromptFile.mode(.personal), .languagePolicy(.sameAsInput)] {
            try FileManager.default.removeItem(at: store.fileURL(file))
        }

        let prompt = try store.assemble(for: .slack, options: .sameAsInput(summary: false))

        #expect(prompt.hasPrefix("Rules\n\(try trimmedBundled(.always))\nTranslate to English."))
        #expect(prompt.hasSuffix(try trimmedBundled(.channel(.slack))))
    }

    @Test(arguments: Refinement.allCases)
    func refinePromptHoldsTheSharedRulesChannelAndInstruction(refinement: Refinement) throws {
        try store.seedMissingDefaults()

        let prompt = try store.assembleRefinement(refinement, for: .slack)

        #expect(prompt.contains(try trimmedBundled(.always)))
        #expect(prompt.contains(try trimmedBundled(.channel(.slack))))
        #expect(prompt.contains(try trimmedBundled(.refinement(refinement))))
        #expect(prompt.contains(#"{"polished_text": "#))
        #expect(!prompt.contains("{{"))
        #expect(!prompt.contains("learning_summary"))
        #expect(!prompt.contains("detected_language"))
        #expect(!prompt.contains("## Language"))
    }

    @Test func standardStoreLivesInApplicationSupport() {
        let url = PromptStore.standard().directoryURL

        #expect(url.lastPathComponent == "prompts")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Writing Assistant")
        #expect(url.path(percentEncoded: false).contains("/Library/Application Support/"))
    }

    @Test func packagedAppBundleTakesPrecedenceOverTheModuleBundle() throws {
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let packaged = resources.appending(path: PromptStore.resourceBundleName)
            .appending(path: "Prompts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)

        let resolved = PromptStore.resolveDefaultsURL(mainResourcesURL: resources) {
            PromptStore.bundledDefaultsURL
        }

        #expect(resolved?.standardizedFileURL == packaged.standardizedFileURL)
    }

    @Test func moduleBundleIsUsedWhenTheAppBundleHasNoPrompts() throws {
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let emptyBundle = resources.appending(path: PromptStore.resourceBundleName)
        try FileManager.default.createDirectory(at: emptyBundle, withIntermediateDirectories: true)
        let module = PromptStore.bundledDefaultsURL

        #expect(PromptStore.resolveDefaultsURL(mainResourcesURL: resources) { module } == module)
        #expect(PromptStore.resolveDefaultsURL(mainResourcesURL: nil) { module } == module)
        #expect(PromptStore.resolveDefaultsURL(mainResourcesURL: nil) { nil } == nil)
    }

    // MARK: - Default sync

    private var manifestURL: URL { store.directoryURL.appending(path: ".defaults.json") }

    private func readManifest() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifestURL))
    }

    /// A store whose bundled defaults are a writable copy, so a test can "ship" a new default.
    private func makeStoreWithEditableDefaults() throws -> (store: PromptStore, defaults: URL) {
        let defaults = root.appending(path: "defaults", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: PromptStore.bundledDefaultsURL, to: defaults)
        return (PromptStore(directoryURL: store.directoryURL, defaultsURL: defaults), defaults)
    }

    private func shipNewDefault(_ text: String, _ file: PromptFile, in defaults: URL) throws {
        try text.write(
            to: defaults.appending(path: file.relativePath), atomically: true, encoding: .utf8)
    }

    @Test func seedingRecordsTheHashOfEverySeededDefault() throws {
        try store.seedMissingDefaults()

        let manifest = try readManifest()
        #expect(Set(manifest.keys) == Set(PromptFile.allCases.map(\.relativePath)))
        #expect(manifest["polish.txt"]?.count == 64)
    }

    @Test func syncWithUnchangedDefaultsReportsNothingAndKeepsFiles() throws {
        try store.seedMissingDefaults()

        #expect(try store.syncDefaults().isEmpty)

        for file in PromptFile.allCases {
            #expect(try diskText(file) == bundledText(file), "\(file.relativePath)")
        }
    }

    @Test func syncSilentlyUpdatesAnUneditedFileWhenTheDefaultChanges() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        let before = try readManifest()
        try shipNewDefault("New slack default", .channel(.slack), in: defaults)

        let newer = try store.syncDefaults()

        #expect(newer.isEmpty)
        #expect(try diskText(.channel(.slack)) == "New slack default")
        #expect(try readManifest()["channels/slack.txt"] != before["channels/slack.txt"])

        #expect(try store.syncDefaults().isEmpty)
    }

    @Test func syncKeepsAnEditedFileAndReportsTheNewerDefault() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        try overwriteOnDisk("My own slack rules", .channel(.slack))
        try shipNewDefault("New slack default", .channel(.slack), in: defaults)

        #expect(try store.syncDefaults() == [.channel(.slack)])
        #expect(try diskText(.channel(.slack)) == "My own slack rules")

        #expect(try store.syncDefaults() == [.channel(.slack)])
    }

    @Test func syncLeavesAnEditedFileAloneWhileTheDefaultIsUnchanged() throws {
        try store.seedMissingDefaults()
        try overwriteOnDisk("My own formal rules", .channel(.formal))

        #expect(try store.syncDefaults().isEmpty)
        #expect(try diskText(.channel(.formal)) == "My own formal rules")
    }

    @Test func syncRecordsAMatchingFileWhenThereIsNoManifest() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: manifestURL)

        #expect(try store.syncDefaults().isEmpty)

        #expect(Set(try readManifest().keys) == Set(PromptFile.allCases.map(\.relativePath)))
    }

    @Test func syncReportsADifferingFileWhenThereIsNoManifest() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: manifestURL)
        try overwriteOnDisk("Edited before the manifest existed", .channel(.aiPrompt))

        #expect(try store.syncDefaults() == [.channel(.aiPrompt)])

        #expect(try diskText(.channel(.aiPrompt)) == "Edited before the manifest existed")
        #expect(try readManifest()["channels/ai_prompt.txt"] == nil)
    }

    @Test(arguments: ["{not json", "[1, 2, 3]", ""])
    func corruptManifestIsTreatedAsMissingAndRewritten(contents: String) throws {
        try store.seedMissingDefaults()
        try overwriteOnDisk("Edited by the user", .channel(.other))
        try contents.write(to: manifestURL, atomically: true, encoding: .utf8)

        #expect(try store.syncDefaults() == [.channel(.other)])

        let manifest = try readManifest()
        #expect(manifest["polish.txt"] != nil)
        #expect(manifest["channels/other.txt"] == nil)
    }

    @Test func seedingRecoversFromACorruptManifest() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: store.fileURL(.channel(.slack)))
        try "{not json".write(to: manifestURL, atomically: true, encoding: .utf8)

        try store.seedMissingDefaults()

        #expect(try diskText(.channel(.slack)) == bundledText(.channel(.slack)))
        #expect(try readManifest()["channels/slack.txt"]?.count == 64)
    }

    /// Makes `url` read-only until the returned closure runs.
    private func makeReadOnly(_ url: URL) throws -> () -> Void {
        let path = url.path(percentEncoded: false)
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        return { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    }

    @Test func syncKeepsGoingPastAnUnreadableFileAndThrowsAfterSavingTheManifest() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        let formal = store.fileURL(.channel(.formal))
        try FileManager.default.removeItem(at: formal)
        try FileManager.default.createDirectory(at: formal, withIntermediateDirectories: true)
        try shipNewDefault("New formal default", .channel(.formal), in: defaults)
        try shipNewDefault("New other default", .channel(.other), in: defaults)
        try overwriteOnDisk("My own shorter rules", .refinement(.shorter))
        try shipNewDefault("New shorter default", .refinement(.shorter), in: defaults)
        let before = try readManifest()

        let error = #expect(throws: PromptStoreError.self) { try store.syncDefaults() }

        #expect(error?.path.hasSuffix("prompts/channels/formal.txt") == true)
        #expect(try diskText(.channel(.other)) == "New other default")
        #expect(try readManifest()["channels/other.txt"] != before["channels/other.txt"])
        try FileManager.default.removeItem(at: formal)
        #expect(try store.syncDefaults() == [.refinement(.shorter)])
    }

    @Test func syncKeepsGoingPastAFailedUpdate() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        try shipNewDefault("New slack default", .channel(.slack), in: defaults)
        try shipNewDefault("New global default", .global, in: defaults)
        let before = try readManifest()
        let restorePermissions = try makeReadOnly(store.directoryURL.appending(path: "channels"))
        defer { restorePermissions() }

        let error = #expect(throws: PromptStoreError.self) { try store.syncDefaults() }

        #expect(error?.operation == "update")
        #expect(error?.path.hasSuffix("prompts/channels/slack.txt") == true)
        #expect(try diskText(.global) == "New global default")
        let manifest = try readManifest()
        #expect(manifest["polish.txt"] != before["polish.txt"])
        #expect(manifest["channels/slack.txt"] == before["channels/slack.txt"])

        restorePermissions()
        #expect(try store.syncDefaults().isEmpty)
        #expect(try diskText(.channel(.slack)) == "New slack default")
    }

    @Test func seedingThrowsWithTheManifestPathWhenTheManifestCannotBeSaved() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: store.fileURL(.channel(.slack)))
        let restorePermissions = try makeReadOnly(store.directoryURL)
        defer { restorePermissions() }

        let error = #expect(throws: PromptStoreError.self) { try self.store.seedMissingDefaults() }

        #expect(error?.path.hasSuffix("prompts/.defaults.json") == true)
        #expect(try diskText(.channel(.slack)) == bundledText(.channel(.slack)))
    }

    @Test func restoringThrowsWithTheManifestPathWhenTheManifestCannotBeSaved() throws {
        try store.seedMissingDefaults()
        try overwriteOnDisk("My own slack rules", .channel(.slack))
        let restorePermissions = try makeReadOnly(store.directoryURL)
        defer { restorePermissions() }

        let error = #expect(throws: PromptStoreError.self) {
            try self.store.restoreDefault(.channel(.slack))
        }

        #expect(error?.path.hasSuffix("prompts/.defaults.json") == true)
        #expect(try diskText(.channel(.slack)) == bundledText(.channel(.slack)))
    }

    @Test func syncSkipsFilesThatDoNotExist() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: store.fileURL(.channel(.slack)))

        #expect(try store.syncDefaults().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(.channel(.slack)).path))
    }

    @Test func syncThrowsWithThePathWhenAPromptFileCannotBeRead() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: manifestURL)
        let url = store.fileURL(.global)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let error = #expect(throws: PromptStoreError.self) { try self.store.syncDefaults() }

        #expect(error?.path.hasSuffix("prompts/polish.txt") == true)
    }

    @Test func acknowledgingStopsReportingWithoutTouchingTheFile() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        try overwriteOnDisk("My own slack rules", .channel(.slack))
        try shipNewDefault("New slack default", .channel(.slack), in: defaults)
        #expect(try store.syncDefaults() == [.channel(.slack)])

        try store.acknowledgeDefault(.channel(.slack))

        #expect(try store.syncDefaults().isEmpty)
        #expect(try diskText(.channel(.slack)) == "My own slack rules")
    }

    @Test func acknowledgingThrowsWhenTheManifestCannotBeWritten() throws {
        try store.seedMissingDefaults()
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: true)

        let error = #expect(throws: PromptStoreError.self) {
            try self.store.acknowledgeDefault(.channel(.slack))
        }

        #expect(error?.path.hasSuffix("prompts/.defaults.json") == true)
    }

    @Test func restoreDefaultRecordsTheRestoredHash() throws {
        let (store, defaults) = try makeStoreWithEditableDefaults()
        try store.seedMissingDefaults()
        try overwriteOnDisk("My own slack rules", .channel(.slack))
        try shipNewDefault("New slack default", .channel(.slack), in: defaults)

        try store.restoreDefault(.channel(.slack))

        #expect(try diskText(.channel(.slack)) == "New slack default")
        #expect(try store.syncDefaults().isEmpty)
        try shipNewDefault("Newest slack default", .channel(.slack), in: defaults)
        #expect(try store.syncDefaults().isEmpty)
        #expect(try diskText(.channel(.slack)) == "Newest slack default")
    }
}
