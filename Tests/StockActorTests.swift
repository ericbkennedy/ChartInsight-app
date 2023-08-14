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
    private var mockStockDelegate = MockStockDelegate()
    private let calendar = Calendar(identifier: .gregorian)
    private let initialOldestBarShown = 13
    private let screenBarWidth = 100
    private let pxHeight = 568.0
    private let sparklineHeight = 200.0
    private let retinaScale = 2.0
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
                                oldestBarShown: initialOldestBarShown,
                                barUnit: .daily,
                                xFactor: defaultXFactor)

        var barDataArray = await DBActor.shared.loadBarData(for: 1, startDateInt: 20090102, beforeDateInt: 20230715)
        await stockActor.serviceLoadedHistoricalData(barDataArray)

        var (maxPeriod, _) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod == 3656)

        // Now simulate loading additional dates via the HistoricalDataService
        barDataArray = await DBActor.shared.loadBarData(for: 1, startDateInt: 20090102, beforeDateInt: 20230723)
        await stockActor.serviceLoadedHistoricalData(barDataArray)

        (maxPeriod, _) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod == 3661)
    }

    /// Tell the DBActor that a stock split occurred for the testStock so it deletes any cached history
    func testStockWithNoCachedHistory() async throws {
        stock = Stock.testStock()
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: initialOldestBarShown,
                                barUnit: .daily,
                                xFactor: defaultXFactor)

        await deleteHistory(for: stock)

        var (maxPeriod, _) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod == -1) // maxPeriod is count - 1 so maxPeriod == -1 when count == 0 for stock prior to fetch

        XCTAssertFalse(mockStockDelegate.didRequestStart)

        // fetch all stock history
        await stockActor.fetchPriceAndFundamentals()

        XCTAssertTrue(mockStockDelegate.didRequestStart)

        (maxPeriod, _) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod > 40)

        XCTAssertTrue(mockStockDelegate.didRequestFinish)
    }

    /// Verify that panning (which uses shiftRedraw) increases the oldestBarShown by amount of pan
    func testShiftRedraw() async throws {
        stock = Stock.testStock()
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: initialOldestBarShown,
                                barUnit: .daily, xFactor: defaultXFactor)

        await stockActor.fetchPriceAndFundamentals()

        let (maxPeriod, oldestBarShown) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(oldestBarShown == initialOldestBarShown)

        let barsShifted = 5
        let percentRange = await stockActor.shiftRedraw(barsShifted, screenBarWidth: screenBarWidth)

        XCTAssert(percentRange.compare(NSDecimalNumber.one) == .orderedDescending, "Range should be larger than minimum")

        let (shiftedMaxPeriod, shiftedOldestBarShown) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod == shiftedMaxPeriod)

        XCTAssert(barsShifted + oldestBarShown == shiftedOldestBarShown)
    }

    /// Try shifting by -2 x initialOldestBarShown which would result in a negative (off-screen) chart if StockActor doesn't prevent that
    func testShiftToNegativeBars() async throws {
        stock = Stock.testStock()
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: initialOldestBarShown,
                                barUnit: .daily, xFactor: defaultXFactor)

        await stockActor.fetchPriceAndFundamentals()

        let (maxPeriod, _) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        let toOffscreenValue = -2 * initialOldestBarShown

        _ = await stockActor.shiftRedraw(toOffscreenValue, screenBarWidth: screenBarWidth)

        let (shiftedMaxPeriod, shiftedOldestBarShown) = await stockActor.maxPeriodSupported(newBarUnit: .daily, newXFactor: defaultXFactor)

        XCTAssert(maxPeriod == shiftedMaxPeriod, "maxPeriod only changes if the user zooms out to weekly or monthly")

        XCTAssert(shiftedOldestBarShown >= 0, "StockActor should reset oldestBarShown to non-negative value")
    }

    /// Verify StockActor combines historical and fundamental data into ChartElements for rendering (by ChartRenderer).
    /// Then change the chart type from candlestick to a close-only line chart and compare the old and new ChartElements.
    func testCopyChartElements() async throws {
        stock = Stock.testAAPL()
        stock.chartType = .candle
        stockActor = StockActor(stock: stock,
                                gregorian: calendar,
                                delegate: mockStockDelegate,
                                oldestBarShown: initialOldestBarShown,
                                barUnit: .daily,
                                xFactor: defaultXFactor)

        // StockActor uses pxHeight, sparklineHeight and the scale to compute chartElements
        await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: retinaScale)
        await stockActor.fetchPriceAndFundamentals()

        let candleChartElements = await stockActor.copyChartElements()

        XCTAssert(candleChartElements.monthLabels.count > 0)
        XCTAssert(candleChartElements.monthLines.count > 0)
        XCTAssert(candleChartElements.oldestReportInView > 0)
        XCTAssert(candleChartElements.newestReportInView >= 0)

        let fundamentalMetrics = stock.fundamentalList.split(separator: ",")

        XCTAssert(candleChartElements.fundamentalColumns.count == fundamentalMetrics.count)
        XCTAssert(candleChartElements.fundamentalAlignments.count >= 55) // report count as of August 2023
        XCTAssert(candleChartElements.points.count > 0)
        XCTAssert(candleChartElements.redPoints.count > 0)
        XCTAssert(candleChartElements.yFactor > 0.0)
        XCTAssert(candleChartElements.yFactor > 0.0)
        XCTAssert(candleChartElements.maxHigh.compare(NSDecimalNumber.one) == .orderedDescending)
        XCTAssert(candleChartElements.minLow.compare(NSDecimalNumber.zero) == .orderedDescending)
        XCTAssert(candleChartElements.scaledLow.compare(NSDecimalNumber.zero) == .orderedDescending)
        XCTAssert(candleChartElements.lastPrice.compare(NSDecimalNumber.one) == .orderedDescending)
        XCTAssert(candleChartElements.movingAvg1.count == 0, "50 day moving average not enabled")
        XCTAssert(candleChartElements.movingAvg2.count > 0, "200 day moving average enabled by default")
        XCTAssert(candleChartElements.upperBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(candleChartElements.middleBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(candleChartElements.lowerBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(candleChartElements.redVolume.count > 0)
        XCTAssert(candleChartElements.blackVolume.count > 0)
        XCTAssert(candleChartElements.greenBars.count > 0)
        XCTAssert(candleChartElements.redBars.count > 0)

        let chartPercentChange = await stockActor.percentChangeAfterUpdateHighLow()

        // Change the chart type to a close-only line and verify the changed values
        stock.chartType = .close
        await stockActor.update(updatedStock: stock)
        await stockActor.recompute(chartPercentChange, forceRecompute: true)

        let closeChartElements = await stockActor.copyChartElements()

        XCTAssert(closeChartElements.points.count > 0)
        XCTAssert(closeChartElements.redPoints.count == 0, "No redPoints on a close-only line chart")
        XCTAssert(closeChartElements.greenBars.count == 0, "No green bars on a close-only line chart")
        XCTAssert(closeChartElements.redBars.count == 0, "No red bars on a close-only line chart")

        XCTAssert(candleChartElements.monthLabels.count == closeChartElements.monthLabels.count)
        XCTAssert(candleChartElements.monthLines.count == closeChartElements.monthLines.count)
        XCTAssert(candleChartElements.oldestReportInView == closeChartElements.oldestReportInView)
        XCTAssert(candleChartElements.newestReportInView == closeChartElements.newestReportInView)

        XCTAssert(candleChartElements.fundamentalColumns.count == closeChartElements.fundamentalColumns.count)
        XCTAssert(candleChartElements.fundamentalAlignments.count == closeChartElements.fundamentalAlignments.count)

        XCTAssert(candleChartElements.yFactor == closeChartElements.yFactor)
        XCTAssert(candleChartElements.yFloor == closeChartElements.yFloor)
        XCTAssert(candleChartElements.maxHigh == closeChartElements.maxHigh)
        XCTAssert(candleChartElements.minLow == closeChartElements.minLow)
        XCTAssert(candleChartElements.scaledLow == closeChartElements.scaledLow)
        XCTAssert(candleChartElements.lastPrice == closeChartElements.lastPrice)
        XCTAssert(closeChartElements.movingAvg1.count == 0, "50 day moving average not enabled")
        XCTAssert(closeChartElements.movingAvg2.count > 0, "200 day moving average enabled by default")
        XCTAssert(closeChartElements.upperBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(closeChartElements.middleBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(closeChartElements.lowerBollingerBand.count == 0, "Bolling Bands not enabled by default")
        XCTAssert(candleChartElements.redVolume.count == closeChartElements.redVolume.count)
        XCTAssert(candleChartElements.blackVolume.count == closeChartElements.blackVolume.count)
    }

}
