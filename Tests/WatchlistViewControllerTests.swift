//
//  WatchlistViewControllerTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import XCTest

final class WatchlistViewControllerTests: XCTestCase {

    var watchlistVC = WatchlistViewController()

    /// Ensure db is available and have it provide the stock list to the watchlistVC
    override func setUpWithError() throws {
        watchlistVC.triggerLifecycleIfNeeded()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// DBActor.shared.moveIfNeeded provides the comparisonList to the MainActor so this test needs to use it
    @MainActor func testUpdateWithList() async throws {
        XCTAssert(0 == watchlistVC.tableView(watchlistVC.tableView, numberOfRowsInSection: 0))

        await DBActor.shared.moveIfNeeded(delegate: watchlistVC)

        // MainActor should have received rows from the DBActor
        XCTAssert(0 < watchlistVC.tableView(watchlistVC.tableView, numberOfRowsInSection: 0))
    }

}
