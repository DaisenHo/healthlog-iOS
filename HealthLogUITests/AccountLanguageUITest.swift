import XCTest

@MainActor
final class AccountLanguageUITest: XCTestCase {
    func testLiveAccountLanguageSurvivesRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["T02_SERVER_URL"],
              let email = environment["T02_EMAIL"],
              let password = environment["T02_PASSWORD"] else
        {
            throw XCTSkip("Requires an isolated local service and synthetic account")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-disable-biometric-lock", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        loginIfNeeded(app, server: server, email: email, password: password)
        finishSetup(app)
        app.terminate()
        app.launch()
        openAccount(app)
        choose("English", app: app)
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 15))
        choose("简体中文", app: app)
        XCTAssertTrue(app.staticTexts["语言"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        openAccount(app)
        XCTAssertTrue(app.staticTexts["语言"].waitForExistence(timeout: 15))
    }

    private func loginIfNeeded(_ app: XCUIApplication, server: String, email: String, password: String) {
        if app.buttons["onboarding.welcome.cta"].waitForExistence(timeout: 5) {
            app.buttons["onboarding.welcome.cta"].tap()
        }
        let mode = element(app, "onboarding.modeServer")
        if mode.waitForExistence(timeout: 2) { mode.tap() }
        let address = app.textFields["onboarding.serverCustom"]
        if address.waitForExistence(timeout: 5) {
            address.tap()
            if let previous = address.value as? String, previous.hasPrefix("http") {
                address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            }
            address.typeText(server + "\n")
            app.buttons["onboarding.serverURLContinue"].tap()
            if app.buttons["onboarding.trustboundary.confirm"].waitForExistence(timeout: 3) {
                app.buttons["onboarding.trustboundary.confirm"].tap()
            }
            if app.buttons["onboarding.serverURLContinueAnyway"].waitForExistence(timeout: 3) {
                app.buttons["onboarding.serverURLContinueAnyway"].tap()
            }
        }
        let passwordFallback = app.buttons["onboarding.webLoginFallback"]
        if passwordFallback.waitForExistence(timeout: 5) { passwordFallback.tap() }
        let login = app.buttons["onboarding.passwordLoginCTA"]
        if login.waitForExistence(timeout: 10) {
            app.textFields.firstMatch.tap()
            app.textFields.firstMatch.typeText(email)
            app.secureTextFields.firstMatch.tap()
            app.secureTextFields.firstMatch.typeText(password + "\n")
            login.tap()
        }
    }

    private func finishSetup(_ app: XCUIApplication) {
        let skipIDs = ["healthKit", "notifications", "aiSource", "anamnesis", "baselineProfile"]
        let deadline = Date().addingTimeInterval(90)
        while !app.tabBars.firstMatch.exists, Date() < deadline {
            let disclaimer = app.buttons["disclaimer.ack.confirm"]
            if disclaimer.exists, disclaimer.isHittable { disclaimer.tap() }
            for step in skipIDs {
                let skip = app.buttons["onboarding.\(step).skip"]
                if skip.exists, skip.isHittable { skip.tap() }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    private func openAccount(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60))
        let disclaimer = app.buttons["disclaimer.ack.confirm"]
        if disclaimer.waitForExistence(timeout: 3) { disclaimer.tap() }
        let more = app.tabBars.buttons.containing(.image, identifier: "ellipsis").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let gear = app.buttons["more.toolbar.gear"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()
        element(app, "settings.hub.account").tap()
        let picker = element(app, "settings.account.language.picker")
        for _ in 0 ..< 5 where !picker.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
    }

    private func choose(_ name: String, app: XCUIApplication) {
        element(app, "settings.account.language.picker").tap()
        let option = app.buttons[name].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
