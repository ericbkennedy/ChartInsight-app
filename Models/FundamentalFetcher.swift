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

let offscreen: Int = -1

struct FundamentalAlignment {
    var x = CGFloat(offscreen)
    var bar: Int = offscreen
    var year: Int = 0
    var month: Int = 0
    var day: Int = 0
}

class FundamentalFetcher: NSObject {
    var ticker: String = ""
    weak var delegate: StockActor?

    func getFundamentals(for stock: Stock, delegate: StockActor) {
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
        var metricKeys = [String]() // in the order received from API
        var columns = [String: [NSDecimalNumber]]()
        var alignments = [FundamentalAlignment]()

        // stream is a URLSession.AsyncBytes. Ignore URLResponse with _ param name
        let (stream, _) = try await URLSession.shared.bytes(from: url)

        for try await line in stream.lines {
            let cols = line.components(separatedBy: "\t")
            if cols.count > datePartsCount {
                if cols[0] == "y" { // header contains dateParts (y m d q) followed by metricKeys
                    for index in (datePartsCount ..< cols.count) {
                        let metricKey = cols[index]
                        metricKeys.append(metricKey)
                        columns[metricKey] = []
                    }
                } else {
                    if let year = Int(cols[0]),
                       let month = Int(cols[1]),
                       let day = Int(cols[2]) { // cols[3] is quarter and can be null (RDFN)

                        alignments.append(FundamentalAlignment(year: year, month: month, day: day))

                        // Append metric values to columns
                        for index in (datePartsCount ..< cols.count) { // metric
                            let metricKey = metricKeys[index - datePartsCount]

                            if cols[index].isEmpty {
                                columns[metricKey]?.append(NSDecimalNumber.notANumber)
                            } else {
                                columns[metricKey]?.append(NSDecimalNumber(string: cols[index]))
                            }
                        }
                    }
                }
            }
        }

        if columns.count > 0 {
            await delegate?.fetcherLoadedFundamentals(columns: columns, alignments: alignments)
        } else {
            print("FundamentalFetcher failed")
        }
    }
}
