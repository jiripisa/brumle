import Testing
@testable import BrumleCore

@Suite("BrumleCore")
struct BrumleCoreTests {

    @Test("Greeting names the app")
    func greetingNamesTheApp() {
        #expect(BrumleCore.greeting(appName: "Brumle") == "Welcome to Brumle")
    }
}
