//
//  MockDBActor.swift
//  ChartInsightTests
//
//  Simulate loading and saving data to database without depedency on sqlite
//
//  Created by Eric Kennedy on 7/25/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

@globalActor actor DBActor {
    static let shared = DBActor()

    public func save(_ barDataArray: [BarData], stockId: Int) {

    }

    /// Load price data for the stock with the fewest days available (CBUS)
    public func loadTestData(beforeDateInt: Int) -> [BarData] {
        var barDataArray = [BarData]()
        let lines = ["2023-07-25,16.2200,19.4800,16.2000,18.5500,36740",
                     "2023-07-24,18.1900,18.7000,16.2900,16.5400,68259",
                     "2023-07-21,19.5800,19.7800,17.5300,18.1900,84765",
                     "2023-07-20,20.7400,21.2800,18.1900,18.9000,40814",
                     "2023-07-19,22.9800,22.9800,20.1500,20.3300,81225",
                     "2023-07-18,23.6900,24.6107,21.1200,22.1100,60358",
                     "2023-07-17,20.6600,24.3100,20.2500,23.8700,97585",
                     "2023-07-14,21.3700,22.2796,20.4100,20.5200,29594",
                     "2023-07-13,20.4000,22.0000,19.5600,21.5200,65075",
                     "2023-07-12,20.2800,21.0000,19.0895,20.1300,94286",
                     "2023-07-11,18.2000,20.5800,17.9740,20.3100,110014",
                     "2023-07-10,18.8800,19.5800,17.8200,18.6300,99939",
                     "2023-07-07,15.5000,18.7900,15.3000,18.3000,280173",
                     "2023-07-06,12.4900,15.9700,11.7200,15.5100,168982",
                     "2023-07-05,10.5000,13.9900,10.2907,12.6800,266026",
                     "2023-07-03,10.2500,10.4300,9.5650,9.9900,50763",
                     "2023-06-30,11.0000,11.2500,10.2500,10.5000,44069",
                     "2023-06-29,10.4000,11.4800,10.1600,11.1000,162743",
                     "2023-06-28,10.4400,10.7000,8.9000,10.5100,301409",
                     "2023-06-27,12.7600,13.1408,9.9900,10.0000,265774",
                     "2023-06-26,13.5000,13.5100,12.5335,12.9800,80232",
                     "2023-06-23,14.3800,14.8215,13.3000,13.4000,333002",
                     "2023-06-22,16.4899,16.4899,14.7600,14.8200,70779",
                     "2023-06-21,16.5000,17.2300,15.0100,15.8600,86548",
                     "2023-06-20,16.0100,17.8700,15.6900,16.2800,91492",
                     "2023-06-16,17.9900,18.2380,16.4450,16.9300,102224",
                     "2023-06-15,17.0000,18.8550,16.0000,17.9900,92560",
                     "2023-06-14,16.5100,18.0100,15.8300,16.2400,88856",
                     "2023-06-13,22.7500,22.8000,15.5100,16.4100,204991",
                     "2023-06-12,24.0000,24.2500,22.5001,23.2000,48711",
                     "2023-06-09,25.3000,26.6250,22.6719,24.3500,96292",
                     "2023-06-08,22.9300,25.9397,22.9300,25.6900,186979",
                     "2023-06-07,24.6700,25.6650,23.1300,24.2200,163138",
                     "2023-06-06,20.8900,25.5000,20.5500,24.6700,55769",
                     "2023-06-05,21.2400,21.6666,20.0000,21.1200,59841",
                     "2023-06-02,26.0600,29.1799,23.2500,24.4000,25951",
                     "2023-06-01,31.5000,32.7100,25.7700,26.0501,81632"]

        for line in lines {
            if let barData = BarData.parse(from: line) {
                if barData.dateIntFromBar() < beforeDateInt {
                    barDataArray.append(barData)
                }
            }
        }
        return barDataArray
    }

    public func loadBarData(for stockId: Int, startDateInt: Int) -> [BarData] {
        return self.loadTestData(beforeDateInt: 20230715)
    }

    /// Save a stock as part of a new comparison (if comparison.id == 0) or add to an existing comparison
    /// Returns a tuple with the list of all comparisons and the comparisonStockId if a new stock (with comparisonStockId=0) was inserted
    public func save(comparison: Comparison) -> ([Comparison], Int) {
        let updatedList = [Comparison]()
        let insertedComparisonStockId = 13
        return (updatedList, insertedComparisonStockId)
    }

    /// Delete all stock from a comparison and the comparison row itself
    public func delete(comparison: Comparison) -> [Comparison] {
        return [Comparison]()
    }

    /// Delete stock from a comparison. Call delete(comparison:) to delete the last stock in a comparison
    public func delete(stock: Stock) -> [Comparison] {
        return [Comparison]()
    }
}
