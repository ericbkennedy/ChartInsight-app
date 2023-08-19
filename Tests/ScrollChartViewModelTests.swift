//
//  ScrollChartViewModelTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/11/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import XCTest

@testable import ChartInsight

final class ScrollChartViewModelTests: XCTestCase {
    var container: NSPersistentContainer = CoreDataStack.shared.container
    var scrollChartViewModel: ScrollChartViewModel!
    private let pxWidth = 320.0, pxHeight = 568.0

    @MainActor override func setUpWithError() throws {
        scrollChartViewModel = ScrollChartViewModel(contentsScale: 2.0)
        scrollChartViewModel.resize(pxWidth: pxWidth, pxHeight: pxHeight)
    }

    override func tearDownWithError() throws {
    }

    /// Creates and returns a comparison with a non-zero id so ScrollChartViewModel assumes it has already been saved and fetches data
    func testEphemeralComparison() -> Comparison {
        let comparison = Comparison(context: container.viewContext)
        comparison.title = "AAPL"
        let comparisonStock = ComparisonStock(context: container.viewContext)
        comparisonStock.stockId = Int64(1)
        comparisonStock.ticker = "AAPL"
        comparison.addToStockSet(comparisonStock)
        comparisonStock.comparison = comparison
        return comparison
    }

    /// Verify that the didUpdate: (@MainActor ([ChartElements]) -> Void) closure is called
    @MainActor func testGetChartElementsForNewStock() async throws {
        let expectation = XCTestExpectation(description: "Expect didUpdate(_) closure to be called")

        scrollChartViewModel.didUpdate = { [expectation] chartElements in
            if chartElements.count > 1 {
                expectation.fulfill()
            }
        }

        let comparison = testEphemeralComparison()
        await scrollChartViewModel.updateComparison(newComparison: comparison) // will trigger didUpdate(_)
    }

    /// Simulate the zoom out scaling that happens with a pinch gesture to show weekly and monthly views. Then zoom back in to daily.
    @MainActor func testScaleChart() async throws {
        let comparison = testEphemeralComparison()
        await scrollChartViewModel.updateComparison(newComparison: comparison) // will trigger didUpdate(_)

        let initialXFactor = scrollChartViewModel.xFactor

        let zoomOutScale = 0.4
        scrollChartViewModel.scaleChart(newScale: zoomOutScale, pxShift: 0)

        XCTAssert(scrollChartViewModel.xFactor == zoomOutScale * initialXFactor)

        // still daily view after initial zoom out
        XCTAssert(.daily == scrollChartViewModel.barUnit)

        // Another pinch by zoomOutScale will switch to weekly view
        scrollChartViewModel.scaleChart(newScale: zoomOutScale, pxShift: 0)

        XCTAssert(.weekly == scrollChartViewModel.barUnit)
        XCTAssert(scrollChartViewModel.xFactor == zoomOutScale * zoomOutScale * initialXFactor)

        // Another pinch by zoomOutScale will switch to monthly view
        scrollChartViewModel.scaleChart(newScale: zoomOutScale, pxShift: 0)

        XCTAssert(.monthly == scrollChartViewModel.barUnit)
        XCTAssert(scrollChartViewModel.xFactor == zoomOutScale * zoomOutScale * zoomOutScale * initialXFactor)

        let zoomInScale = 1 / zoomOutScale

        // zoom back in to weekly view
        scrollChartViewModel.scaleChart(newScale: zoomInScale, pxShift: 0)
        XCTAssert(.weekly == scrollChartViewModel.barUnit)
        XCTAssert(scrollChartViewModel.xFactor == zoomOutScale * zoomOutScale * initialXFactor)

        // zoom back in to daily view
        scrollChartViewModel.scaleChart(newScale: zoomInScale, pxShift: 0)
        XCTAssert(.daily == scrollChartViewModel.barUnit)
        XCTAssert(round(scrollChartViewModel.xFactor) == zoomOutScale * initialXFactor)
    }

    /// Create a new comparison, ensure it loads data, then delete it
    @MainActor func testSaveAndDeleteNewComparison() async throws {

        let initialComparisonList = Comparison.fetchAll()

        // Start with an empty comparison
        let comparison = Comparison(context: container.viewContext)

        let expectation = XCTestExpectation(description: "Expect didUpdate(_) closure to be called")

        scrollChartViewModel.didUpdate = { [expectation] chartElements in
            if chartElements.count > 1 {
                expectation.fulfill()
            }
        }

        await scrollChartViewModel.updateComparison(newComparison: comparison)

        // addToComparison(stock:) will also cause the comparison to be saved and the comparison.id updated
        await scrollChartViewModel.addToComparison(stock: ComparisonStock.testStock(context: container.viewContext))

        let updatedComparisonList = Comparison.fetchAll()

        XCTAssert(updatedComparisonList.count == 1 + initialComparisonList.count,
                  "Expected \(updatedComparisonList.count) == 1 + \(initialComparisonList.count)")

        // Delete this test comparison
        container.viewContext.delete(comparison)

        let comparisonListAfterDelete = Comparison.fetchAll()

        XCTAssert(comparisonListAfterDelete.count == initialComparisonList.count)
    }
}
