//
//  UITests.swift
//  UITests
//
//  Created by Eric Kennedy on 8/13/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import XCTest

final class UITests: XCTestCase {
    static var launched = false
    var app: XCUIApplication!
    var comparisonTableView: XCUIElement!
    var newComparisonButton: XCUIElement!
    var addToComparisonButton: XCUIElement!
    var deleteFromComparisonButton: XCUIElement!
    var chartOptionsTableView: XCUIElement!
    var doneWithChartOptionsButton: XCUIElement!
    var addFundamentalTableView: XCUIElement!
    var navStockButtonToolbar: XCUIElement!
    var searchBar: XCUIElement!
    var searchResultsTableView: XCUIElement!
    var settingsTableView: XCUIElement!
    var settingsTabItem: XCUIElement!
    var watchlistTabItem: XCUIElement!

    override func setUpWithError() throws {
        let app = XCUIApplication()
        comparisonTableView = app.tables[AccessibilityId.Watchlist.tableView]
        navStockButtonToolbar = app.toolbars[AccessibilityId.Watchlist.navStockButtonToolbar]
        newComparisonButton = app.buttons[AccessibilityId.Watchlist.newComparisonButton]
        addToComparisonButton = app.buttons[AccessibilityId.Watchlist.addToComparisonButton]
        deleteFromComparisonButton = app.buttons[AccessibilityId.ChartOptions.deleteButton]
        chartOptionsTableView = app.tables[AccessibilityId.ChartOptions.tableView]
        doneWithChartOptionsButton = app.buttons[AccessibilityId.ChartOptions.doneButton]
        addFundamentalTableView = app.tables[AccessibilityId.AddFundamental.tableView]
        searchResultsTableView = app.tables[AccessibilityId.AddStock.tableView]
        searchBar = app.searchFields[AccessibilityId.AddStock.searchBar]
        settingsTableView = app.tables[AccessibilityId.Settings.tableView]
        settingsTabItem = app.tabBars.buttons.element(boundBy: 2)
        watchlistTabItem = app.tabBars.buttons.element(boundBy: 0)
        continueAfterFailure = false
        app.launchArguments.append("--UITests") // will disable animation
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    /// Test will tap the + button on the left, then enter the ticker in the search bar. Tap the first row to add the stock.
    func testAddNewComparisonByTappingRow() throws {
        let countBeforeAdding = comparisonTableView.cells.count
        newComparisonButton.tap()

        searchBar.tap()
        searchBar.typeText("AAPL")
        XCTAssertEqual(searchResultsTableView.cells.count, 1, "Search is not working properly")
        searchResultsTableView.cells.firstMatch.tap()   // select first match

        XCTAssert(comparisonTableView.cells.count == countBeforeAdding + 1, "Expected \(comparisonTableView.cells.count) == \(countBeforeAdding) + 1")

        try deleteLastComparison()
        XCTAssert(comparisonTableView.cells.count == countBeforeAdding, "Expected \(comparisonTableView.cells.count) == \(countBeforeAdding)")
    }

    /// Test will tap the + button on the left, then enter the ticker and '\n' to add the first match
    func testAddNewComparisonWithReturn() throws {
        let countBeforeAdding = comparisonTableView.cells.count
        newComparisonButton.tap()

        let ticker = "ZM"
        searchBar.tap()
        searchBar.typeText(ticker)
        searchBar.typeText("\n")

        XCTAssertTrue(comparisonTableView.waitForExistence(timeout: 5))

        XCTAssert(comparisonTableView.cells.count == countBeforeAdding + 1,
                  "Expected \(comparisonTableView.cells.count) == \(countBeforeAdding) + 1")

        XCTAssertTrue(navStockButtonToolbar.waitForExistence(timeout: 20))
        let chartOptionsButton = navStockButtonToolbar.buttons[ticker]
        chartOptionsButton.tap()

        let chartOptionRowsBeforeAdding = chartOptionsTableView.cells.count

        let addFundamentalRow = chartOptionsTableView.cells.staticTexts[AccessibilityId.ChartOptions.addFundamentalRow]

        if addFundamentalRow.exists == false {
            XCTFail("Expected to find other fundamental metrics to add")
        }

        addFundamentalRow.tap()

        XCTAssertTrue(addFundamentalTableView.waitForExistence(timeout: 20))
        addFundamentalTableView.cells.firstMatch.tap()

        XCTAssert(chartOptionsTableView.cells.count == 1 + chartOptionRowsBeforeAdding,
                  "Expected \(chartOptionsTableView.cells.count) == 1 + \(chartOptionRowsBeforeAdding)")

        doneWithChartOptionsButton.tap()

        try deleteLastComparison()

        XCTAssert(comparisonTableView.cells.count == countBeforeAdding,
                  "Expected \(comparisonTableView.cells.count) == \(countBeforeAdding)")
    }

    /// Delete the last comparison. This is run by other tests to remove comparisons added during testing.
    func deleteLastComparison() throws {
        settingsTabItem.tap()
        XCTAssertTrue(settingsTableView.waitForExistence(timeout: 20))
        let countBeforeDeleting = settingsTableView.cells.count
        var lastRowIndex = countBeforeDeleting - 1 // Device will show contact support row

        if settingsTableView.cells.staticTexts[AccessibilityId.Settings.contactSupport].exists {
            // Found Contact Support row so reducing last index by 1 (app must be running on a device)
            lastRowIndex -= 1
        }

        let lastRow = settingsTableView.cells.element(boundBy: lastRowIndex)
        lastRow.buttons.firstMatch.tap() // red minus button is showing in editing mode
        // Now delete button appears on the right for confirmation
        lastRow.buttons["Delete"].tap()

        let countAfterDeleting = settingsTableView.cells.count
        XCTAssert(countAfterDeleting == countBeforeDeleting - 1)
        watchlistTabItem.tap()
    }

    /// Add an ETF to the first row in the watchlist. Verify it is added to the toolbar then remove it to restore original state.
    func testAddETFtoComparisonThenRemove() throws {
        XCTAssertTrue(navStockButtonToolbar.waitForExistence(timeout: 20))
        let buttonsInToolbarBeforeAdding = navStockButtonToolbar.buttons.count

        addToComparisonButton.tap()
        let ticker = "QQQ"
        searchBar.tap()
        searchBar.typeText(ticker)
        XCTAssertEqual(searchResultsTableView.cells.count, 1, "Search is not working properly")
        searchResultsTableView.cells.firstMatch.tap()   // select first match

        XCTAssertTrue(navStockButtonToolbar.waitForExistence(timeout: 20))

        var buttonsInToolbarAfter = navStockButtonToolbar.buttons.count
        XCTAssert(buttonsInToolbarAfter == 1 + buttonsInToolbarBeforeAdding)

        let chartOptionsButton = navStockButtonToolbar.buttons[ticker]
        chartOptionsButton.tap()

        let noFundamentalsForETFs = "\(AccessibilityId.ChartOptions.unavilableMessage) \(ticker)"

        if chartOptionsTableView.cells.staticTexts[noFundamentalsForETFs].exists == false {
            XCTFail("Expected to find row showing that fundamentals are unavailable for ETFs")
        }

        XCTAssertTrue(deleteFromComparisonButton.waitForExistence(timeout: 20))
        deleteFromComparisonButton.tap() // remove ETF to restore original state
        buttonsInToolbarAfter = navStockButtonToolbar.buttons.count
        XCTAssert(buttonsInToolbarAfter == buttonsInToolbarBeforeAdding)
    }

    /// Tap the + button on the left, then enter the ticker in the search bar. Tap the first row to add the stock.
    func testSearchWithNoMatches() throws {
        newComparisonButton.tap()

        searchBar.tap()
        searchBar.typeText("XYZ")
        XCTAssertEqual(searchResultsTableView.cells.count, 1, "Expected a row with no matches message")

        XCTAssertTrue(searchResultsTableView.cells.staticTexts[AccessibilityId.AddStock.noMatches].exists)
        searchResultsTableView.cells.staticTexts[AccessibilityId.AddStock.noMatches].tap()
        XCTAssertEqual(searchResultsTableView.cells.count, 0, "Should clear search")
    }
}
