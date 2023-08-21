//
//  Mocks.swift
//  ChartInsightTests
//
//  Mock objects to test WatchlistViewController without including other Views in Test target
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import Foundation
import UIKit

@testable import ChartInsight

final class SceneDelegate {
    public func showWebView(urlString: String) { }
}

extension Stock {
    static func testAAPL() -> Stock {
        var stock = Stock()
        stock.id = 1
        stock.name = "Apple"
        stock.ticker = "AAPL"
        return stock
    }

    /// Returns the stock with the least history for faster integration tests
    static func testStock() -> Stock {
        var stock = Stock()
        stock.id = 3855
        stock.name = "Cibus"
        stock.ticker = "CBUS"
        stock.startDateString = "20230601" // actual start date
        return stock
    }
}

extension ComparisonStock {
    /// Creates a new comparisonStock for AAPL. Caller will need to add it to a comparison.
    static func testAAPL(context: NSManagedObjectContext) -> ComparisonStock {
        return ComparisonStock(context: context).setValues(with: Stock.testAAPL())
    }

    /// Creates a comparisonStock with the least history for faster integration tests. Caller will need to add it to a comparison.
    static func testStock(context: NSManagedObjectContext) -> ComparisonStock {
        return ComparisonStock(context: context).setValues(with: Stock.testStock())
    }

    /// DBActor will delete the history after a stock split. This creates a fake stock split to clear cached price data.
    internal func deleteHistory(delegate: MockStockDelegate) async {
        let stockChange = StockChangeService.StockChange(stockId: Int(self.stockId),
                                                         ticker: self.ticker,
                                                         action: .split,
                                                         name: self.name,
                                                         startDateInt: 0,
                                                         hasFundamentals: 0)

        await DBActor.shared.update(stockChanges: [stockChange], delegate: delegate)
    }
}

class MockStockDelegate: StockActorDelegate, DBActorDelegate {
    func update(list newList: [Comparison], reloadComparison: Bool) {
    }

    var requestFinishedCompletion: ((NSDecimalNumber) async -> Void)?

    var didRequestStart = false, didRequestCancel = false, didRequestFail = false, didRequestFinish = false

    func requestStarted() {
        didRequestStart = true
    }

    func requestCanceled() {
        didRequestCancel = true
    }

    func requestFailed(message: String) {
        didRequestFail = true
    }

    func requestFinished(newPercentChange: NSDecimalNumber) async {
        didRequestFinish = true
    }
}
