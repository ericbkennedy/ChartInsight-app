//
//  DataFetcher.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/15/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

let API_KEY = "placeholderToken";

enum ServiceError: Error {
    case network(reason: String)
    case http(statusCode: Int)
    case parsing
    case general(reason: String)
}

class DataFetcher: NSObject {
    var fetchedData: [BarData] = []
    var loadingData: Bool = false
    var countBars: Int = 0
    var barsFromDB: Int = 0
    @objc var delegate: DataFetcherDelegate? = nil
    @objc var symbol: String = ""
    @objc var stockId: Int = 0
    @objc var requestNewest: Date = Date()
    @objc var requestOldest: Date = Date(timeIntervalSinceReferenceDate: 0)
    @objc var lastClose:     Date = Date(timeIntervalSinceReferenceDate: 0)
    @objc var nextClose:     Date = Date(timeIntervalSinceReferenceDate: 0)
    @objc var oldestDate:    Date = Date(timeIntervalSinceReferenceDate: 0)
    var lastIntradayFetch: Date = Date(timeIntervalSinceReferenceDate: 0)
    var lastOfflineError:  Date = Date(timeIntervalSinceReferenceDate: 0)
    var dateFormatter:     DateFormatter = DateFormatter()
    @objc var gregorian: Calendar? = nil
    var ephemeralSession: URLSession = URLSession(configuration: .ephemeral) // skip web cache

    @objc override init() {
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // 1996-12-19T16:39:57-08:00
        dateFormatter.dateFormat = "yyyyMMdd'T'HH':'mm':'ss'Z'";  // Z means UTC time
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        super.init()
    }

    /// Full text search is much faster if startDates are kept as strings until the user selects a stock
    @objc func setRequestOldestWith(startString: String) {
        if let date = dateFormatter.date(from: "\(startString)T20:00:00Z") {
            requestOldest = date
        } else {
            print("Error converting \(symbol) \(startString) to date")
        }
    }
    
    @objc func shouldFetchIntradayQuote() -> Bool {
        let BEFORE_OPEN: TimeInterval = 23000.0
        let AFTER_CLOSE: TimeInterval = -3600.0
        let secondsUntilClose = nextClose.timeIntervalSinceNow
        
        if !isRecent(lastIntradayFetch) && secondsUntilClose < BEFORE_OPEN && secondsUntilClose > AFTER_CLOSE {
            // current time in NYC is between 9:30am and 5pm of nextClose so only intraday data is available
            return true
        }
        return false
    }
    
    @objc func fetchIntradayQuote() {
        if (loadingData) {
            print("loadingData = true so skipping Intraday fetch")
        } else if (isRecent(lastOfflineError)) {
            print("last offline error \(lastOfflineError) was too recent to try again %f",
                  Date().timeIntervalSince(lastOfflineError))
            cancelDownload()
            return
        }
        
        let urlString = "https://chartinsight.com/api/intraday/\(symbol)?token=\(API_KEY)"
        guard let url = URL(string: urlString) else { return }
        loadingData = true
        
        Task {
            do {
                try await fetchIntraday(from: url)
            } catch {
                self.handleError(error)
            }
        }
    }
    
    func handleError(_ error: Error) {
        print("ERROR for \(symbol) \(error.localizedDescription)")
        
        // TODO: check connection
        lastOfflineError = Date()
        
        if (barsFromDB > 0) { // send delegate the bars loaded from DB
            cancelDownload()
        }
        
        delegate?.fetcherFailed(error.localizedDescription)
    }
    
    func fetchIntraday(from url: URL) async throws {

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
            self.delegate?.fetcherLoadedIntradayBar(intradayBar)
            self.lastIntradayFetch = Date()
        } else if (!fetchedData.isEmpty && fabs(fetchedData[0].close - previousClose) > 0.02) {
            // Intraday API uses IEX data and may not have intraday data even when the market is open
            let message = "\(self.symbol) intraday prevClose \(previousClose) doesn't match (self.fetchedData[0].close)"
            self.delegate?.fetcherFailed(message)
        }
    }
    
    func formatRequestURL() -> URL? {
        if let startY = gregorian?.component(.year, from: requestOldest),
           let startM = gregorian?.component(.month, from: requestOldest),
           let startD = gregorian?.component(.day, from: requestOldest),
           let endY = gregorian?.component(.year, from: requestNewest),
           let endM = gregorian?.component(.month, from: requestNewest),
           let endD = gregorian?.component(.day, from: requestNewest) {

            var urlString = "https://chartinsight.com/api/ohlcv/\(symbol)?"
            urlString += "startDate=\(startY)-\(startM)-\(startD)"
            urlString += "&endDate=\(endY)-\(endM)-\(endD)&token=\(API_KEY)"

            return URL(string: urlString)
        }
        return nil
    }
    
    /// StockData will call this with the currentNewest date (or .distantPast) if self.nextClose is today or in the past.
    @objc(fetchNewerThanDate:)
    func fetchNewerThanDate(currentNewest: Date) {
        
        if currentNewest.compare(.distantPast) == .orderedDescending {
            requestOldest = getNextTradingDateAfter(date: currentNewest)
        }
        
        requestNewest = Date()
        
        if loadingData {
            print("load in progress, returning")
        }
        loadingData = true
        
        barsFromDB = 0
        countBars = 0
        fetchedData.removeAll()
        
        let oldestDateInt = dateInt(from: requestOldest)
        
        fetchedData = DB().loadBarData(for: stockId, startDateInt: oldestDateInt)
        
        barsFromDB = fetchedData.count
        if barsFromDB > 0 {
            lastClose = date(from: fetchedData[0])
            nextClose = getNextTradingDateAfter(date: lastClose)
            
            if requestNewest.timeIntervalSince(nextClose) >= 0.0 { // need to contact server
                requestOldest = nextClose // skip dates loaded from DB
                requestNewest = Date()
            }
            // send values loaded from DB
            historicalDataLoaded(barDataArray: fetchedData)
        }
        
        if isRecent(lastOfflineError) {
            print("lastOfflineError \(lastOfflineError) was too recent to try again")
            cancelDownload()
        } else {
            guard let url = formatRequestURL() else { return }
            
            Task {
                do {
                    try await fetchDailyData(from: url)
                } catch {
                    print("error occurred")
                    if fetchedData.isEmpty == false { // send what we have
                        historicalDataLoaded(barDataArray: fetchedData)
                    }
                }
            }
        }
    }
    
    /// Fetch historical price data via API and parse CSV lines into BarData
    func fetchDailyData(from url: URL) async throws {
        
        // stream is a URLSession.AsyncBytes. Ignore URLResponse with _ param name
        let (stream, _) = try await URLSession.shared.bytes(from: url)
       
        for try await line in stream.lines {
            if let barData = BarData.parse(from: line) {
                fetchedData.append(barData)
            }
        }
        
        DB().save(fetchedData, stockId: stockId)
        
        historicalDataLoaded(barDataArray: fetchedData)
    }
    
    func historicalDataLoaded(barDataArray: [BarData]) {
        guard barDataArray.count > 0 else {
            // should be a failure condition
            print("barDataArray \(barDataArray)")
            return
        }
        
        DispatchQueue.main.async {
            self.delegate?.fetcherLoadedHistoricalData(barDataArray)
        }
    }
    
    @objc(dateFromBar:)
    func date(from bar: BarData) -> Date {
        let dateString = String(format: "%ld%02ld%02ldT20:00:00Z", bar.year, bar.month, bar.day)
        let date = dateFormatter.date(from: dateString);
        return date!
    }
    
    func dateInt(from date: Date) -> Int {
        guard gregorian != nil else {
            print("Gregorian calendar missing")
            return 0
        }
        
        let year = gregorian?.component(.year, from: date) ?? 0;
        let month = gregorian?.component(.month, from: date) ?? 0;
        let day = gregorian?.component(.day, from: date) ?? 0;
        
        return year * 10000 + month * 100 + day
    }
    
    func isHoliday(date: Date) -> Bool {
        let dateIntValue = dateInt(from: date)
        let holidays = [20230619, 20230704, 20230904, 20231123, 20231225,
         20240101, 20240115, 20240219, 20240329, 20240527, 20240619, 20240704, 20240902, 20241128, 20241225,
         20250101, 20250120, 20250217, 20250418, 20250526, 20250619, 20250704, 20250901, 20251127, 20251225]
        
        return holidays.contains(dateIntValue)
    }
    
    func getNextTradingDateAfter(date: Date) -> Date {
        guard gregorian != nil else { return date }
                
        let oneDay = DateComponents(day: 1), Sunday = 1, Saturday = 7
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
            
        } while (self.isHoliday(date: nextTradingDate) || weekday == Saturday || weekday == Sunday)

        return nextTradingDate
    }
    
    func isRecent(_ date: Date) -> Bool {
        return date.timeIntervalSinceNow > -60.0
    }
    
    /// Called BEFORE creating a URLSessionTask if there was a recent offline error or it was too soon to try again
    func cancelDownload() {
        if (loadingData) {
            loadingData = false
        }
        delegate?.fetcherCanceled()
    }
    
    /// called by StockData when a stock is removed or the chart is cleared before switching stocks
    @objc func invalidateAndCancel() {
        ephemeralSession.invalidateAndCancel()
        delegate = nil
    }
}

/// Intraday API has different format than BarData since it adds prevClose and the date parts start with "lastSale"
/// {"ticker":"MPW","lastSaleYear":2023,"lastSaleMonth":5,"lastSaleDay":8,"open":8.6,"high":8.64,"low":8.49,"last":8.57,"prevClose":8.61,"volume":7885132}
struct IntradayResponse: Decodable {
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
