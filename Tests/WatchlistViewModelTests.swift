//
//  WatchlistViewModelTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/13/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import XCTest

@MainActor final class WatchlistViewModelTests: XCTestCase {

    var scrollChartViewModel: ScrollChartViewModel!
    var watchlistViewModel: WatchlistViewModel!

    /// Initialize fresh viewModels
    override func setUpWithError() throws {
        scrollChartViewModel = ScrollChartViewModel(contentsScale: 2.0)
        watchlistViewModel = WatchlistViewModel(scrollChartViewModel: scrollChartViewModel)
    }

    func testDidUpdateAfterDbFetch() async throws {

        XCTAssert(0 == watchlistViewModel.listCount)

        let expectation = XCTestExpectation(description: "Expect didUpdate(_) closure to be called")

        watchlistViewModel.didUpdate = { selectedIndex in
            XCTAssert(0 == selectedIndex) // load the first item by default
            expectation.fulfill()
        }

        await DBActor.shared.moveIfNeeded(delegate: watchlistViewModel)

        XCTAssert(0 < watchlistViewModel.listCount)
    }

}
