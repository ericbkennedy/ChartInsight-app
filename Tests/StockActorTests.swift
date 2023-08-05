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

    private var stock = Stock()
    private var stockActor: StockActor!
    private var scrollChartViewModel = ScrollChartViewModel(contentsScale: 3.0)
    private let dayBarUnit = 1.0
    private let defaultXFactor = 7.5

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        stock = Stock.testAAPL()
        let calendar = Calendar(identifier: .gregorian)

        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: scrollChartViewModel,
                                oldestBarShown: 13,
                                barUnit: dayBarUnit,
                                xFactor: defaultXFactor)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        Task {
            await stockActor.invalidateAndCancel()
        }
    }

    /// Verify that the 2nd call to stockActor.serviceLoadedHistoricalData() inserts all new bars.
    /// This simulates loading from the DB and then loading additional dates from the HistoricalDataService API.
    func testInsertingNewBarsAfterInitialLoad() async throws {
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
}
