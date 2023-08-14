//
//  WatchlistViewControllerTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import XCTest

@MainActor final class WatchlistViewControllerTests: XCTestCase {

    var scrollChartViewModel: ScrollChartViewModel!
    var watchlistViewModel: WatchlistViewModel!
    var watchlistViewController: WatchlistViewController!

    /// Initialize fresh viewModels
    override func setUpWithError() throws {
        scrollChartViewModel = ScrollChartViewModel(contentsScale: 2.0)
        watchlistViewModel = WatchlistViewModel(scrollChartViewModel: scrollChartViewModel)
        watchlistViewController = WatchlistViewController(watchlistViewModel: watchlistViewModel)

        watchlistViewController.triggerLifecycleIfNeeded()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// DBActor.shared.moveIfNeeded provides the comparisonList to the MainActor so this test needs to use it
    @MainActor func testUpdateWithList() async throws {
        XCTAssert(0 == watchlistViewController.tableView(watchlistViewController.tableView, numberOfRowsInSection: 0))

        await DBActor.shared.moveIfNeeded(delegate: watchlistViewModel)

        // MainActor should have received rows from the DBActor
        XCTAssert(0 < watchlistViewController.tableView(watchlistViewController.tableView, numberOfRowsInSection: 0))
    }

}
