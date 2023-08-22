//
//  HistoricalDataServiceTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/21/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import XCTest

@testable import ChartInsight

final class HistoricalDataServiceTests: XCTestCase {

    var historicalDataService: HistoricalDataService!
    /// Use AAPL as the comparisonStock since testStock CBUS rarely has intraday data
    var comparisonStock = ComparisonStock.testAAPL(context: CoreDataStack.shared.viewContext)
    var serviceLoadedHistoricalDataCompletion: ((_ loadedData: [ChartInsight.BarData]) async -> Void)?
    var serviceLoadedIntradayBarCompletion: ((_ intradayBar: ChartInsight.BarData) async -> Void)?

    override func setUpWithError() throws {
        historicalDataService = HistoricalDataService(for: comparisonStock, calendar: Calendar.current)
    }

    override func tearDownWithError() throws {
        historicalDataService.invalidateAndCancel()
    }

    /// Verify that historicalDataService calls delegate method serviceLoadedHistoricalData(_:)
    /// If during market hours, it should also call serviceLoadedIntradayBar(_:)
    func testHistoricalAndIntradayFetch() async throws {
        XCTAssertFalse(historicalDataService.shouldFetchIntradayQuote(), "Wait to request intraday until after historical data")

        historicalDataService.delegate = self
        historicalDataService.setRequestOldestWith(startString: comparisonStock.startDateString)

        XCTAssert(historicalDataService.shouldFetchNextClose(), "Should fetch next close when no data is loaded")

        let expectHistoricalData = XCTestExpectation(description: "Expect serviceLoadedHistoricalData(_:) to be called")
        serviceLoadedHistoricalDataCompletion = { loadedData in
            XCTAssert(loadedData.count > 50, "Expected loadedData.count > 50, got \(loadedData.count)")
            expectHistoricalData.fulfill()
        }

        await historicalDataService.fetchNewerThanDate(currentNewest: .distantPast)

        XCTAssertFalse(historicalDataService.isRequestingRemoteData, "isRequestingRemoteData should be false after historical API request")

        await fulfillment(of: [expectHistoricalData], timeout: 60)

        if historicalDataService.shouldFetchIntradayQuote() {
            print("Within intraday window so should fetch intraday quote")
            let expectIntradayData = XCTestExpectation(description: "Expect serviceLoadedIntradayBar(_:) to be called")
            serviceLoadedIntradayBarCompletion = { intradayBar in
                XCTAssert(intradayBar.year >= 2023)
                expectIntradayData.fulfill()
            }

            // Use async let so we can await the unfulfilled expectation
            async let _ = historicalDataService.fetchIntradayQuote()

            await fulfillment(of: [expectIntradayData], timeout: 60)
        } else {
            print("Outside intraday window so no need to fetch intraday data")
        }
    }
}

extension HistoricalDataServiceTests: ServiceDelegate {
    func serviceLoadedHistoricalData(_ loadedData: [ChartInsight.BarData]) async {
        await serviceLoadedHistoricalDataCompletion?(loadedData)
    }

    func serviceLoadedIntradayBar(_ intradayBar: ChartInsight.BarData) async {
        await serviceLoadedIntradayBarCompletion?(intradayBar)
    }

    func serviceFailed(_ message: String) async {

    }

    func serviceCanceled() async {

    }

    func serviceLoadedFundamentals(columns: [String: [NSDecimalNumber]], alignments: [ChartInsight.FundamentalAlignment]) async {
        // Only FundamentalService calls this (not the HistoricalDataService tested in this file)
    }

}
