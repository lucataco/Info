import XCTest

@MainActor
final class InfoUITests: XCTestCase {
    func testOnboardingLaunchesWithAccessibleActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Info"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip onboarding"].exists)
        XCTAssertTrue(app.buttons["Continue"].exists)
    }
}
