//
//  WatchlistViewControllerTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import XCTest

@testable import ChartInsight

@MainActor final class WatchlistViewControllerTests: XCTestCase {

    var container: NSPersistentContainer!
    var scrollChartViewModel: ScrollChartViewModel!
    var watchlistViewModel: WatchlistViewModel!
    var watchlistViewController: WatchlistViewController!

    /// Initialize fresh viewModels
    override func setUpWithError() throws {
        container = NSPersistentContainer(name: "CoreDataModel")
        container.loadPersistentStores { _, error in
            if let error {
                print("Unresolved error \(error)")
            }
        }
        scrollChartViewModel = ScrollChartViewModel(contentsScale: 2.0)
        watchlistViewModel = WatchlistViewModel(container: CoreDataStack.shared.container, scrollChartViewModel: scrollChartViewModel)

        watchlistViewController = WatchlistViewController(watchlistViewModel: watchlistViewModel)

        watchlistViewController.triggerLifecycleIfNeeded()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// CoreData implementation of WatchlistViewModel.init(container, scrollChartModel:) fetches comparisonList so listCount > 0
    @MainActor func testUpdateWithList() async throws {
        // MainActor should have received rows from the DBActor
        XCTAssert(0 < watchlistViewController.tableView(watchlistViewController.tableView, numberOfRowsInSection: 0))
    }

}
