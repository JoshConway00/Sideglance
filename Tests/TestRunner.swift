import Foundation

@main struct TestRunner {
    @MainActor static func main() async {
        // Offline fixtures must never pollute the user's live quality log.
        UserDefaults.standard.setVolatileDomain(["qualityLogging": false], forName: UserDefaults.argumentDomain)
        runRegressionTests()
        runStateRegressionTests()
        runPortabilityTests()
        runQualityLogTests()
        runNarrativeBatchTests()
        runNotificationUpdateTests()
        runQualityReviewTests()
        await runProcessRegressionTests()
    }
}
