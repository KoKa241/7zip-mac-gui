//
//  __Zip_GUIUITests.swift
//  7-Zip GUIUITests
//
//  Created by Vlad on 01.11.2026.
//

import XCTest

final class __Zip_GUIUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndRuns() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
