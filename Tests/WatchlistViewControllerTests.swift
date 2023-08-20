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
    func testComparisonListLoaded() throws {
        XCTAssertNotNil(watchlistViewController.childTableViewController)

        guard let tableView = watchlistViewController.childTableViewController.tableView else {
            return XCTFail("Missing childTableViewController.tableView")
        }

        XCTAssert(0 < watchlistViewController.childTableViewController.tableView(tableView, numberOfRowsInSection: 0))
    }

    /// Verify that a comparison has loaded and the navigationItem contains 4+ buttons (left toggle, 1+ stock(s), compare button, right menu)
    func testNavButtonToolbarContainsAStock() throws {
        guard let navigationToolbar = watchlistViewController.navigationItem.titleView as? UIToolbar else {
            return XCTFail("Missing navigationToolbar")
        }

        guard let navigationItemButtons = navigationToolbar.items else {
            return XCTFail("Missing navigationToolbar.items")
        }
        XCTAssert(navigationItemButtons.count >= 4, "Expected >= 4 buttons, found \(navigationItemButtons.count)")

        var stockButtonCount = 0, compareButtonCount = 0

        for barButtonItem in navigationItemButtons {
            if let buttonTitle = barButtonItem.title, buttonTitle.isEmpty == false {
                print(buttonTitle)
                if buttonTitle == "+ compare" {
                    compareButtonCount += 1
                } else if buttonTitle.prefixMatch(of: /\w+\s?/) != nil {
                    stockButtonCount += 1
                }
            }
        }
        XCTAssert(stockButtonCount > 0, "Expected at least one stock, found \(stockButtonCount)")
        XCTAssert(compareButtonCount == 1, "Expected one comparison button")
    }
}
