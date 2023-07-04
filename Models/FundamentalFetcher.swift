//
//  FundamentalFetcher.swift
//  ChartInsight
//
//  Loads fundamental metrics for a company as arrays of objects:
//      Quarter end date stored as year, month and day in 3 arrays of equal length (report count)
//      Columns dictionary with metric keys (e.g. EarningsPerShareBasic) and array of NSDecimalNumbers
//
//  Unlike the DataFetcher, the FundamentalFetcher will be called once until a metric is added or removed
//
//  Created by Eric Kennedy on 6/22/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class FundamentalFetcher: NSObject {
    var isLoadingData: Bool = false
    var ticker: String = ""
    weak var delegate: StockData?
    var year: [Int] = []
    var month: [Int] = []
    var day: [Int] = []
    var columns: [String: [NSDecimalNumber]] = [:]
    var barAlignments: [Int] = [] // set later by StockData to align dates

    func getFundamentals(for stock: Stock, delegate: StockData) {
        guard isLoadingData == false else { return }
        isLoadingData = true
        ticker = stock.ticker
        self.delegate = delegate

        if let url = formatRequestURL(keys: stock.fundamentalList) {
            Task { [weak self] in
                do {
                    try await self?.fetch(from: url)
                } catch {
                    print("Error \(error)")
                }
            }
        }
    }

    func formatRequestURL(keys: String) -> URL? {
        let urlString = "https://chartinsight.com/api/fundamentalTSV/\(ticker)/\(keys)?&token=\(apiKey)"
        return URL(string: urlString)
    }

    func fetch(from url: URL) async throws {

        let datePartsCount = 4
        var metricKeys: [String] = [] // in the order received from API

        // stream is a URLSession.AsyncBytes. Ignore URLResponse with _ param name
        let (stream, _) = try await URLSession.shared.bytes(from: url)

        for try await line in stream.lines {
            let cols = line.components(separatedBy: "\t")
            if cols.count > datePartsCount {
                if cols[0] == "y" { // header contains dateParts (y m d q) followed by metricKeys
                    for index in (datePartsCount ..< cols.count) {
                        let metricKey = cols[index]
                        metricKeys.append(metricKey)
                        self.columns[metricKey] = []
                    }
                } else {
                    if let year = Int(cols[0]),
                       let month = Int(cols[1]),
                       let day = Int(cols[2]) { // cols[3] is quarter and can be null (RDFN)

                        self.year.append(year)
                        self.month.append(month)
                        self.day.append(day)
                        self.barAlignments.append(-1) // for consistent row count

                        // Append metric values to columns
                        for index in (datePartsCount ..< cols.count) { // metric
                            let metricKey = metricKeys[index - datePartsCount]

                            if cols[index].isEmpty {
                                self.columns[metricKey]?.append(NSDecimalNumber.notANumber)
                            } else {
                                self.columns[metricKey]?.append(NSDecimalNumber(string: cols[index]))
                            }
                        }
                    }
                }
            }
        }

        if self.columns.count > 0 {
            await MainActor.run {
                self.isLoadingData = false
                delegate?.fetcherLoadedFundamentals(self.columns)
            }
        } else {
            print("FundamentalFetcher failed")
        }
    }

    // The year, month and day arrays all have the same count
    func reportCount() -> Int {
        return year.count
    }

    func setBarAlignment(_ barIndex: Int, report: Int) {
        if report < barAlignments.count {
            barAlignments[report] = barIndex
        }
    }

    func barAlignmentFor(report: Int) -> Int {
        if report < barAlignments.count {
            return barAlignments[report]
        }
        return -1
    }

    func valueFor(report: Int, key: String) -> NSDecimalNumber {
        if let metricValues = self.columns[key],
           report < metricValues.count {
            return metricValues[report]
        }
        return NSDecimalNumber.notANumber // ScrollChartView will skip it
    }
}
