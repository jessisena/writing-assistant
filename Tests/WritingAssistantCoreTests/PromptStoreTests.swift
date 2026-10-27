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

        #expect(PromptFile.allCases.count == 10)
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
        (PromptFile.global, "No placeholder here", PromptValidationError.missingPlaceholder),
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

    @Test(arguments: Channel.allCases)
    func assembleInsertsTheChannelGuidelines(channel: Channel) throws {
        try store.seedMissingDefaults()
        let guidelines = try bundledText(.channel(channel))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prompt = try store.assemble(for: channel)

        #expect(prompt.contains(guidelines))
        #expect(!prompt.contains("{{"))
    }

    @Test(arguments: Channel.allCases)
    func assembledDefaultPromptHasNoEmDash(channel: Channel) throws {
        try store.seedMissingDefaults()

        #expect(!(try store.assemble(for: channel)).contains("\u{2014}"))
    }

    @Test func assembleTrimsBothFiles() throws {
        try store.write("  Before\n\(PromptFile.channelPlaceholder)\nAfter\n\n", to: .global)
        try store.write("\n  Guidelines  \n", to: .channel(.slack))

        #expect(try store.assemble(for: .slack) == "Before\nGuidelines\nAfter")
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
}
