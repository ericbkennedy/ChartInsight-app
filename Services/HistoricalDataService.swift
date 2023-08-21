//
//  HistoricalDataService.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/15/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.

import Foundation

protocol ServiceDelegate: AnyObject {
    func serviceLoadedFundamentals(columns: [String: [NSDecimalNumber]], alignments: [FundamentalAlignment]) async
    func serviceLoadedHistoricalData(_ loadedData: [BarData]) async
    func serviceLoadedIntradayBar(_ intradayBar: BarData) async
    func serviceFailed(_ message: String) async
    func serviceCanceled() async
}

public let apiKey = "placeholderToken"
public let dayInSeconds: TimeInterval = 84600

public enum ServiceError: Error {
    case network(reason: String)
    case http(statusCode: Int)
    case parsing
    case general(reason: String)
}

final class HistoricalDataService {
    public weak var delegate: ServiceDelegate?
    public var requestNewest: Date
    public var requestOldest: Date
    public var lastClose: Date {
        didSet {
            nextClose = getNextTradingDateAfter(date: lastClose)
        }
    }
    public var oldestDate: Date
    private var nextClose: Date
    private var gregorian: Calendar?
    private var ticker: String
    private var stockId: Int64
    private var dateFormatter: DateFormatter

    /// True during an API request for price data (historical or intraday)
    private (set) var isRequestingRemoteData: Bool
    private var countBars: Int
    private var barsFromDB: Int
    private var fetchedData: [BarData]
    private var lastIntradayFetch: Date
    private var hasIntradayData: Bool
    private var lastOfflineError: Date
    private var ephemeralSession: URLSession = URLSession(configuration: .ephemeral) // skip web cache

    public init(for stock: ComparisonStock, calendar: Calendar) {
        fetchedData = []
        isRequestingRemoteData = false
        stockId = stock.stockId
        ticker = stock.ticker
        gregorian = calendar
        (countBars, barsFromDB) = (0, 0)
        requestNewest = Date()
        requestOldest = Date(timeIntervalSinceReferenceDate: 0)
        nextClose = Date(timeIntervalSinceReferenceDate: 0)
        lastClose = Date(timeIntervalSinceReferenceDate: 0)
        oldestDate = Date(timeIntervalSinceReferenceDate: 0)
        lastIntradayFetch = Date(timeIntervalSinceReferenceDate: 0)
        lastOfflineError = Date(timeIntervalSinceReferenceDate: 0)
        hasIntradayData = true // will be set to false if a DecodingError occurs on intraday response
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // 1996-12-19T16:39:57-08:00
        dateFormatter.dateFormat = "yyyyMMdd'T'HH':'mm':'ss'Z'"  // Z means UTC time
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    /// Full text search is much faster if startDates are kept as strings until the user selects a stock
    public func setRequestOldestWith(startString: String) {
        if let date = dateFormatter.date(from: "\(startString)T20:00:00Z") {
            requestOldest = date
        } else {
            print("Error converting \(ticker) \(startString) to date")
        }
    }

    /// Returns true if the last intraday fetch was more than a minute ago and it is after the market open but before closing data is available
    public func shouldFetchIntradayQuote() -> Bool {
        let beforeOpen: TimeInterval = 23000.0
        let afterClose: TimeInterval = -3600.0 // Current API provider has closing data an hour after close
        let secondsUntilClose = nextClose.timeIntervalSinceNow

        if hasIntradayData && !isRecent(lastIntradayFetch) && secondsUntilClose < beforeOpen && secondsUntilClose > afterClose {
            // current time in NYC is between 9:30am and 5pm of nextClose so only intraday data is available
            return true
        }
        return false
    }

    /// Returns true if closing data should be available
    public func shouldFetchNextClose() -> Bool {
        let afterClose: TimeInterval = 3600.0
        let secondsAfterClose = Date().timeIntervalSince(nextClose)

        if !isRequestingRemoteData && secondsAfterClose > afterClose {
            return true
        }
        return false // either wait a minute to refetch intraday data or wait until an hour after close
    }

    public func fetchIntradayQuote() async {
        if isRequestingRemoteData {
            return
        } else if isRecent(lastOfflineError) {
            print("last offline error \(lastOfflineError) was too recent to try again %f",
                  Date().timeIntervalSince(lastOfflineError))
            await cancelDownload()
            return
        }

        let urlString = "https://chartinsight.com/api/intraday/\(ticker)?token=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        isRequestingRemoteData = true

        do {
            try await fetchIntraday(from: url)

        } catch DecodingError.keyNotFound(let key, let context) {
            print("error decoding intraday for \(ticker): \(key.stringValue) was not found, \(context.debugDescription)")
            hasIntradayData = false
            await cancelDownload()
        } catch {
            lastOfflineError = Date()
            print("ERROR on fetchIntradayQuote \(ticker) \(error.localizedDescription) from \(urlString)")
            await delegate?.serviceFailed(error.localizedDescription)
        }
    }

    /// Intraday API has different format than BarData since it adds prevClose and the date parts start with "lastSale"
    internal struct IntradayResponse: Decodable {
        let ticker: String
        let lastSaleYear: Int
        let lastSaleMonth: Int
        let lastSaleDay: Int
        let open: Double
        let high: Double
        let low: Double
        let last: Double
        let prevClose: Double
        let volume: Int
    }

    private func fetchIntraday(from url: URL) async throws {

        let (data, response) = try await ephemeralSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.network(reason: "Response to \(url) wasn't expected HTTPURLResponse")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.http(statusCode: httpResponse.statusCode)
        }

        let intradayData = try JSONDecoder().decode(IntradayResponse.self, from: data)
        let intradayBar = BarData()
        intradayBar.year = intradayData.lastSaleYear
        intradayBar.month = intradayData.lastSaleMonth
        intradayBar.day = intradayData.lastSaleDay
        intradayBar.open = intradayData.open
        intradayBar.high = intradayData.high
        intradayBar.low = intradayData.low
        intradayBar.close = intradayData.last
        intradayBar.adjClose = intradayData.last // only different for historical API
        intradayBar.volume = Double(intradayData.volume) // floating point for CoreGraphics

        let previousClose = intradayData.prevClose

        let lastSaleDate = date(from: intradayBar)

        if lastSaleDate.compare(lastClose) == .orderedDescending {
            await delegate?.serviceLoadedIntradayBar(intradayBar)
            self.lastIntradayFetch = Date()
        } else if !fetchedData.isEmpty && fabs(fetchedData[0].close - previousClose) > 0.02 {
            // Intraday API uses IEX data and may not have intraday data even when the market is open
            let message = "\(self.ticker) intraday prevClose \(previousClose) doesn't match (self.fetchedData[0].close)"
            await delegate?.serviceFailed(message)
        }
    }

    private func formatRequestURL() -> URL? {
        if let startY = gregorian?.component(.year, from: requestOldest),
           let startM = gregorian?.component(.month, from: requestOldest),
           let startD = gregorian?.component(.day, from: requestOldest),
           let endY = gregorian?.component(.year, from: requestNewest),
           let endM = gregorian?.component(.month, from: requestNewest),
           let endD = gregorian?.component(.day, from: requestNewest) {

            var urlString = "https://chartinsight.com/api/ohlcv/\(ticker)?"
            urlString += "startDate=\(startY)-\(startM)-\(startD)"
            urlString += "&endDate=\(endY)-\(endM)-\(endD)&token=\(apiKey)"

            return URL(string: urlString)
        }
        return nil
    }

    /// StockActor will call this with currentNewest date (or .distantPast) if self.nextClose is today or in the past
    public func fetchNewerThanDate(currentNewest: Date) async {

        if currentNewest.compare(.distantPast) == .orderedDescending {
            requestOldest = getNextTradingDateAfter(date: currentNewest)
        }

        requestNewest = Date()

        if isRequestingRemoteData {
            return // since another request is in progress let it call the delegate methods when it finishes or fails
        }

        barsFromDB = 0
        countBars = 0
        fetchedData.removeAll()

        let oldestDateInt = dateInt(from: requestOldest)

        fetchedData = await DBActor.shared.loadBarData(for: stockId, startDateInt: oldestDateInt)

        barsFromDB = fetchedData.count
        if barsFromDB > 0 {
            lastClose = date(from: fetchedData[0])
            requestOldest = lastClose

            if requestNewest.timeIntervalSince(nextClose) >= dayInSeconds { // need to contact server
                requestOldest = nextClose // skip dates loaded from DB
                requestNewest = Date()
            }
            // send values loaded from DB
            await historicalDataLoaded(barDataArray: fetchedData)
        }

        if isRecent(lastOfflineError) {
            print("lastOfflineError \(lastOfflineError) was too recent to try again")
            await cancelDownload()
        } else if Date().compare(nextClose) == .orderedDescending {
            isRequestingRemoteData = true
            guard let url = formatRequestURL() else { return }

            do {
                try await fetchDailyData(from: url)
            } catch {
                lastOfflineError = Date()
                print("Error occurred: \(error.localizedDescription)")
                if fetchedData.isEmpty == false { // send what we have
                    await historicalDataLoaded(barDataArray: fetchedData)
                }
            }
        }
    }

    /// Fetch historical price data via API and parse CSV lines into BarData
    private func fetchDailyData(from url: URL) async throws {

        // stream is a URLSession.AsyncBytes. Ignore URLResponse with _ param name
        let (stream, _) = try await URLSession.shared.bytes(from: url)

        // API returns newest dates first so for multiple lines we need to reverse it before inserting
        var newBarData: [BarData] = []

        for try await line in stream.lines {
            if let barData = BarData.parse(from: line) {
                newBarData.append(barData)
            }
        }

        if fetchedData.isEmpty {
            fetchedData.append(contentsOf: newBarData)
        } else {
            // Reverse the order of newBarData so newest is inserted at index 0 after older dates
            for barData in newBarData.reversed() where barData.dateIntFromBar() > fetchedData[0].dateIntFromBar() {
                fetchedData.insert(barData, at: 0)
            }
        }

        isRequestingRemoteData = false // allows StockActor to request intraday data if needed
        await historicalDataLoaded(barDataArray: fetchedData)

        // save to DB after updating UI with historicalDataLoaded()
        await DBActor.shared.save(fetchedData, stockId: Int64(stockId))
    }

    /// Call StockActor delegate and have it update the bar data on a background thread
    private func historicalDataLoaded(barDataArray: [BarData]) async {
        guard barDataArray.count > 0 else {
            // should be a failure condition
            print("\(ticker) empty historicalDataLoaded \(barDataArray)")
            await delegate?.serviceFailed("Empty response")
            return
        }
        lastClose = date(from: fetchedData[0])
        if let lastBar = fetchedData.last {
            oldestDate = date(from: lastBar)
        }
        await self.delegate?.serviceLoadedHistoricalData(barDataArray)
    }

    public func date(from bar: BarData) -> Date {
        let dateString = String(format: "%ld%02ld%02ldT20:00:00Z", bar.year, bar.month, bar.day)
        let date = dateFormatter.date(from: dateString)
        return date!
    }

    private func dateInt(from date: Date) -> Int {
        guard gregorian != nil else { return 0 }

        let year = gregorian?.component(.year, from: date) ?? 0
        let month = gregorian?.component(.month, from: date) ?? 0
        let day = gregorian?.component(.day, from: date) ?? 0

        return year * 10000 + month * 100 + day
    }

    private func isHoliday(date: Date) -> Bool {
        let dateIntValue = dateInt(from: date)
        let holidays = [20230904, 20231123, 20231225,
         20240101, 20240115, 20240219, 20240329, 20240527, 20240619, 20240704, 20240902, 20241128, 20241225,
         20250101, 20250120, 20250217, 20250418, 20250526, 20250619, 20250704, 20250901, 20251127, 20251225]

        return holidays.contains(dateIntValue)
    }

    private func getNextTradingDateAfter(date: Date) -> Date {
        guard gregorian != nil else { return date }

        let oneDay = DateComponents(day: 1), sunday = 1, saturday = 7
        var weekday = 0
        var nextTradingDate = date

        repeat {
            if let nextDate = gregorian?.date(byAdding: oneDay, to: nextTradingDate) {
                nextTradingDate = nextDate
                weekday = gregorian?.component(.weekday, from: nextTradingDate) ?? 0
            } else {
                print("Error adding so exiting")
                return date
            }

        } while (self.isHoliday(date: nextTradingDate) || weekday == saturday || weekday == sunday)

        return nextTradingDate
    }

    private func isRecent(_ date: Date) -> Bool {
        return date.timeIntervalSinceNow > -60.0
    }

    /// Called BEFORE creating a URLSessionTask if there was a recent offline error or it was too soon to try again
    private func cancelDownload() async {
        if isRequestingRemoteData {
            isRequestingRemoteData = false
        }
        await delegate?.serviceCanceled()
    }

    /// called by StockActor when a stock is removed or the chart is cleared before switching stocks
    public func invalidateAndCancel() {
        ephemeralSession.invalidateAndCancel()
        delegate = nil
    }
}
