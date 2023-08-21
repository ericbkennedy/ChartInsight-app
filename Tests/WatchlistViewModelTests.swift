//
//  WatchlistViewModelTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/13/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import XCTest

@testable import ChartInsight

@MainActor final class WatchlistViewModelTests: XCTestCase {

    var scrollChartViewModel: ScrollChartViewModel!
    var watchlistViewModel: WatchlistViewModel!

    /// Initialize fresh viewModels
    override func setUpWithError() throws {
        scrollChartViewModel = ScrollChartViewModel(contentsScale: 2.0)
        watchlistViewModel = WatchlistViewModel(container: CoreDataStack.shared.container, scrollChartViewModel: scrollChartViewModel)
    }

    /// CoreData implementation of WatchlistViewModel.init(container, scrollChartModel:) fetches comparisonList so listCount > 0
    func testDidUpdateAfterDbFetch() async throws {

        let expectation = XCTestExpectation(description: "Expect didUpdate(_) closure to be called")

        watchlistViewModel.didUpdate = { selectedIndex in
            XCTAssert(0 == selectedIndex) // load the first item by default
            expectation.fulfill()
        }

        await DBActor.shared.moveIfNeeded(delegate: watchlistViewModel)

        XCTAssert(0 < watchlistViewModel.listCount)
    }

}
