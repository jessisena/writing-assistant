import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelRunningRefinementTests {
    private func waitUntil(_ polisher: GatedPolisher, hasCalls count: Int) async {
        while polisher.waitingCount < count { await Task.yield() }
    }

    private func gatedPolishedModel() async -> (AppModel, GatedPolisher) {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        return (model, polisher)
    }

    @Test func noRefinementRunsAfterPolishing() async {
        let (model, _) = await gatedPolishedModel()

        #expect(model.runningRefinement == nil)
    }

    @Test func runningRefinementIsSetWhileItRunsAndClearedWhenItFinishes() async {
        let (model, polisher) = await gatedPolishedModel()

        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)
        #expect(model.runningRefinement == .preset(.shorter))

        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.runningRefinement == nil)
    }

    @Test func runningRefinementIsClearedWhenItFails() async {
        let (model, polisher) = await gatedPolishedModel()

        model.refine(.moreFormal)
        await waitUntil(polisher, hasCalls: 2)
        polisher.resume(1, with: .failure(.timeout(seconds: 120)))
        await model.requests.task?.value

        #expect(model.runningRefinement == nil)
    }

    @Test func runningRefinementIsClearedOnCancel() async {
        let (model, polisher) = await gatedPolishedModel()

        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)
        model.cancel()

        #expect(model.runningRefinement == nil)
        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.runningRefinement == nil)
    }
}
