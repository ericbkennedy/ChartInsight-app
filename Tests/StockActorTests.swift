//
//  StockActorTests.swift
//  ChartInsightTests
//
//  Test sequential updates of price data since it is loaded from the DB
//  and then updated by the HistoricalDataService with closing and intraday data.
//
//  Created by Eric Kennedy on 7/25/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import XCTest

extension DBActor {
    /// Test helper filters out newer bars for consistent counts
    public func loadBarData(for stockId: Int, startDateInt: Int, beforeDateInt: Int) -> [BarData] {
        return self.loadBarData(for: stockId, startDateInt: startDateInt)
            .filter({
                $0.dateIntFromBar() < beforeDateInt
            })
    }
}

final class StockActorTests: XCTestCase {

    private var stock = Stock.testStock()
    private var stockActor: StockActor!
    private var scrollChartViewModel = ScrollChartViewModel(contentsScale: 3.0)
    private var mockStockDelegate = MockStockDelegate()
    private let calendar = Calendar(identifier: .gregorian)
    private let dayBarUnit = 1.0
    private let defaultXFactor = 7.5

    /// DBActor will delete the history after a stock split. This creates a fake stock split to clear cached price data.
    private func deleteHistory(for stock: Stock) async {
        let stockChange = StockChangeService.StockChange(stockId: stock.id,
                                                         ticker: stock.ticker,
                                                         action: .split,
                                                         name: stock.name,
                                                         startDateInt: 0,
                                                         hasFundamentals: 0)

        await DBActor.shared.update(stockChanges: [stockChange], delegate: mockStockDelegate)
    }

    override func setUpWithError() throws {
        // stockActor varies with each test
    }

    override func tearDownWithError() throws {
        Task {
            await stockActor.invalidateAndCancel()
        }
    }

    /// Verify that the 2nd call to stockActor.serviceLoadedHistoricalData() inserts all new bars.
    /// This simulates loading from the DB and then loading additional dates from the HistoricalDataService API.
    func testInsertingNewBarsAfterInitialLoad() async throws {
        stock = Stock.testAAPL() // use AAPL because historical data exists in charts.db
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: 13,
                                barUnit: dayBarUnit,
                                xFactor: defaultXFactor)

        var barDataArray = await DBActor.shared.loadBarData(for: 1, startDateInt: 20090102, beforeDateInt: 20230715)
        await stockActor.serviceLoadedHistoricalData(barDataArray)

        var (periodCount, _) = await stockActor.maxPeriodSupported(newBarUnit: dayBarUnit, newXFactor: defaultXFactor)

        XCTAssert(periodCount == 3656)

        // Now simulate loading additional dates via the HistoricalDataService
        barDataArray = await DBActor.shared.loadBarData(for: 1, startDateInt: 20090102, beforeDateInt: 20230723)
        await stockActor.serviceLoadedHistoricalData(barDataArray)

        (periodCount, _) = await stockActor.maxPeriodSupported(newBarUnit: dayBarUnit, newXFactor: defaultXFactor)

        XCTAssert(periodCount == 3661)
    }

    /// Tell the DBActor that a stock split occurred for the testStock so it deletes any cached history
    func testStockWithNoCachedHistory() async throws {
        stock = Stock.testStock()
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: 13,
                                barUnit: dayBarUnit,
                                xFactor: defaultXFactor)

        await deleteHistory(for: stock)

        var (periodCount, _) = await stockActor.maxPeriodSupported(newBarUnit: dayBarUnit, newXFactor: defaultXFactor)

        XCTAssert(periodCount == -1) // the max period is count - 1 so when maxPeriod == -1 when count == 0

        XCTAssertFalse(mockStockDelegate.didRequestStart)

        // fetch all stock history
        await stockActor.fetchPriceAndFundamentals()

        XCTAssertTrue(mockStockDelegate.didRequestStart)

        (periodCount, _) = await stockActor.maxPeriodSupported(newBarUnit: dayBarUnit, newXFactor: defaultXFactor)

        XCTAssert(periodCount > 40)

        XCTAssertTrue(mockStockDelegate.didRequestFinish)
    }
}
