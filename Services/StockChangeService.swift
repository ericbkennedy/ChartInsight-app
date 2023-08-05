//
//  StockChangeService.swift
//  ChartInsight
//
//  Check for stock additions (IPOs), splits, ticker changes, name changes or delistings.
//
//  Created by Eric Kennedy on 7/5/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

struct StockChangeService {
    let defaultsSyncTimestampKey = "syncStockChangeTimestamp"
    let bundleDBTimestamp = 710306200.0 // charts.db includes stocks through 2023-7-6

    enum CorpAction: String, Decodable {
        case added, split, tickerChange, nameChange, delisted
    }

    struct StockChange: Decodable {
        let stockId: Int
        let ticker: String
        let action: CorpAction
        let name: String?
        let startDateInt: Int?
        let hasFundamentals: Int?
    }

    private func formatRequestURL() -> URL? {
        var lastSyncTimestamp = bundleDBTimestamp
        let postInstallSync = UserDefaults.standard.double(forKey: defaultsSyncTimestampKey)

        if postInstallSync > 0 {
            lastSyncTimestamp = postInstallSync
        }
        let lastSyncDate = Date(timeIntervalSinceReferenceDate: lastSyncTimestamp)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let lastSync = dateFormatter.string(from: lastSyncDate)
        let urlString = "https://chartinsight.com/api/stockChanges?startDate=\(lastSync)&token=\(apiKey)"
        return URL(string: urlString)
    }

    /// Return a list of stock changes (new IPOs, ticker/name changes, splits, delistings) or nil if none since last fetch
    func fetchChanges() async -> [StockChange]? {
        guard let url = formatRequestURL() else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.network(reason: "Response to \(url) wasn't expected HTTPURLResponse")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.http(statusCode: httpResponse.statusCode)
            }
            let changes = try JSONDecoder().decode([StockChange].self, from: data)
            UserDefaults.standard.set(Date.timeIntervalSinceReferenceDate, forKey: defaultsSyncTimestampKey)
            return changes
        } catch {
            print("error is \(error.localizedDescription)")
        }
        return nil
    }
}
