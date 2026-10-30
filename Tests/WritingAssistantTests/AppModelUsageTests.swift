import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelUsageTests {
    private let directory = makeTemporaryDirectory()

    private var store: UsageStore {
        UsageStore(fileURL: directory.appending(path: "usage.json"))
    }

    private static let tokens = TokenUsage(input: 10, output: 20, cacheCreation: 30, cacheRead: 40)

    private func makeModel(_ polisher: any Polishing) -> AppModel {
        AppModel.testing(polisher: polisher, directory: directory)
    }

    /// Starts polishing, records `tokens` as the polisher would, then answers with `outcome`.
    private func polish(
        _ model: AppModel, _ polisher: GatedPolisher,
        answer outcome: Result<PolishResult, PolishError>
    ) async throws {
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        while polisher.waitingCount == 0 { await Task.yield() }
        try store.record(Self.tokens, costUSD: 0.25)
        polisher.resume(0, with: outcome)
        await model.requests.task?.value
    }

    @Test func isZeroWithoutAUsageFile() {
        #expect(makeModel(FakePolisher()).monthlyUsage == .zero)
    }

    @Test func isReadAtLaunch() throws {
        try store.record(Self.tokens, costUSD: 0.25)

        let model = makeModel(FakePolisher())

        #expect(model.monthlyUsage == MonthlyUsage(tokens: Self.tokens, requests: 1, costUSD: 0.25))
    }

    @Test func isReadAgainAfterAPolish() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)

        try await polish(model, polisher, answer: .success(.sample))

        #expect(model.monthlyUsage == MonthlyUsage(tokens: Self.tokens, requests: 1, costUSD: 0.25))
    }

    @Test func isReadAgainAfterAFailureAndKeepsItsBanner() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)

        try await polish(model, polisher, answer: .failure(.badFormat(detail: "x")))

        #expect(model.monthlyUsage.requests == 1)
        #expect(model.errorMessage == PolishError.badFormat(detail: "x").errorDescription)
    }

    @Test func isReadAgainWhenACancelledRequestEnds() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        while polisher.waitingCount == 0 { await Task.yield() }
        let cancelled = model.requests.task
        model.cancel()

        try store.record(Self.tokens, costUSD: 0.25)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value

        #expect(model.monthlyUsage.requests == 1)
    }

    @Test func isReadAgainAfterARefinement() async throws {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        try store.record(Self.tokens, costUSD: 0.25)

        model.refine(.shorter)
        await model.requests.task?.value

        #expect(model.monthlyUsage.requests == 1)
    }

    @Test func damagedFileAtLaunchShowsAStartupErrorAndCountsFromZero() throws {
        try Data("not json".utf8).write(to: store.fileURL)

        let model = makeModel(FakePolisher())

        #expect(model.monthlyUsage == .zero)
        let expected = UsageStoreError.corrupted(backup: store.backupURL).errorDescription
        #expect(model.errorMessage == expected)
    }

    @Test func damagedFileAfterARequestGoesToTheBannerAndCountsFromZero() async throws {
        try store.record(Self.tokens, costUSD: 0.25)
        let model = makeModel(FakePolisher())
        try Data("not json".utf8).write(to: store.fileURL)
        model.input = NSAttributedString(string: "Hello")

        await model.process()

        #expect(model.monthlyUsage == .zero)
        let expected = UsageStoreError.corrupted(backup: store.backupURL).errorDescription
        #expect(model.errorMessage == expected)
    }
}

@Suite struct MonthlyUsageDisplayTests {
    private let locale = Locale(identifier: "en_US")

    private func usage(total input: Int, requests: Int = 1, cost: Double = 0) -> MonthlyUsage {
        MonthlyUsage(
            tokens: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0),
            requests: requests, costUSD: cost)
    }

    @Test func compactSummaryAbbreviatesLargeTotalsAndShowsTheCost() {
        #expect(
            usage(total: 48_234, cost: 0.4213).compactSummary(locale: locale)
                == "48.2K tokens · $0.42 this month")
        #expect(
            usage(total: 512, cost: 0.02).compactSummary(locale: locale)
                == "512 tokens · $0.02 this month")
        #expect(
            usage(total: 0, requests: 0).compactSummary(locale: locale)
                == "0 tokens · $0.00 this month")
    }

    @Test func oneTokenIsSingular() {
        #expect(usage(total: 1).compactSummary(locale: locale) == "1 token · $0.00 this month")
    }

    @Test func fullSummaryShowsTheExactTotalAndTheCost() {
        #expect(
            usage(total: 48_234, cost: 0.4213).fullSummary(locale: locale)
                == "48,234 tokens, about $0.42 at API prices, this month")
    }

    @Test func breakdownListsEachKindTheRequestsAndTheCost() {
        let usage = MonthlyUsage(
            tokens: TokenUsage(input: 1_200, output: 300, cacheCreation: 4_000, cacheRead: 50_000),
            requests: 7, costUSD: 0.4213)

        #expect(
            usage.breakdown(locale: locale)
                == "Input: 1,200\nOutput: 300\nCache write: 4,000\nCache read: 50,000\nRequests: 7"
                + "\nCost at API prices: $0.4213")
    }

    @Test(arguments: [
        (0.0, 2, "$0.00"),
        (0.004, 2, "<$0.01"),
        (0.009, 2, "<$0.01"),
        (0.01, 2, "$0.01"),
        (0.4213, 2, "$0.42"),
        (12.5, 2, "$12.50"),
        (0.00004, 4, "<$0.0001"),
        (0.0219465, 4, "$0.0219"),
    ])
    func costIsInDollarsAndNeverReadsAsFreeWhenSomethingWasSpent(
        cost: Double, fractionDigits: Int, expected: String
    ) {
        let usage = usage(total: 1, cost: cost)

        #expect(usage.formattedCost(fractionDigits: fractionDigits, locale: locale) == expected)
    }
}
