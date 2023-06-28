//
//  StockData.swift
//  ChartInsight
//
//  Delegates fetching of stock price and fundamental data (to DataFetcher and FundamentalFetcher).
//  After DataFetcherDelegate methods are called, StockData computes ChartElements for all of the returned data
//  and notifies its delegate (ScrollChartView) that it is ready.
//  ScrollChartView calls copyChartElements() to get a thread-safe copy it can render while
//  StockData is free to update its own copy (in tmpElements) as new data loads.
//
//  Created by Eric Kennedy on 6/27/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

class StockData: NSObject, DataFetcherDelegate {
    @objc var stock: Stock
    @objc var gregorian: Calendar
    @objc weak var delegate: ScrollChartView?
    
    @objc var newestBarShown: Int {
        didSet {
            if newestBarShown < 0 {
                newestBarShown = 0
            }
        }
    }
    @objc var oldestBarShown: Int
    @objc var xFactor: CGFloat
    @objc var yFloor: CGFloat
    @objc var yFactor: CGFloat
    @objc var barUnit: CGFloat

    /// ready == true if StockData has been loaded, computed and copied into chartElements.
    @objc var ready = false
    /// busy == true if it is currently recomputing chartElements.
    /// Can be busy but ready if chartElements was previously computed.
    private var busy = false
    @objc var maxHigh: NSDecimalNumber
    @objc var minLow: NSDecimalNumber
    @objc var scaledLow: NSDecimalNumber
    @objc var lastPrice: NSDecimalNumber
    @objc var percentChange: NSDecimalNumber
    private var chartPercentChange: NSDecimalNumber

    private var oldest: Date
    private var newest: Date // newest loaded, not the newest shown
    // Fundamental reports
    @objc var oldestReportInView: Int
    @objc var newestReportInView: Int
    private var oldestReport: Int
    private var newestReport: Int
    private var fundamentalColumns: [String: [NSDecimalNumber]]
    
    @objc var chartElements: ChartElements       // public for ScrollChartView rendering
    private var tmpElements: ChartElements // private for background computation
    private var dailyData: [BarData]
    @objc var periodData: [BarData] // points to dailyData or dailyData grouped by week or month
    private var fetcher: DataFetcher?
    private var fundamentalFetcher: FundamentalFetcher?
    private var sma50:  Bool
    private var sma200: Bool
    private var bb20:   Bool
    private var pxHeight: Double
    private var sparklineHeight: Double
    private var maxVolume: Double
    private var chartBase: Double
    private var volumeBase: Double
    private var volumeHeight: Double
    private var concurrentQueue: DispatchQueue?
    
    @objc init(stock: Stock, gregorian: Calendar, delegate: ScrollChartView, oldestBarShown: Int) {
        self.stock = stock
        self.gregorian = gregorian
        self.delegate = delegate
        self.oldestBarShown = oldestBarShown
        newestBarShown = 0
        fetcher = DataFetcher()
        fundamentalFetcher = FundamentalFetcher()
        concurrentQueue = DispatchQueue(label: "com.chartinsight.\(stock.id)", attributes: .concurrent)
        tmpElements = ChartElements()
        chartElements = ChartElements()
        periodData = []
        dailyData = []
        fundamentalColumns = [:]
        (oldest, newest) = (Date.distantPast, Date.distantPast)
        (oldestReport, oldestReportInView, newestReport, newestReportInView) = (0, 0, 0, 0)
        (xFactor, yFloor, yFactor, barUnit, maxVolume) = (0, 0, 0, 0, 0)
        (pxHeight, sparklineHeight, chartBase, volumeBase, volumeHeight) = (0, 0, 0, 0, 0)
        (percentChange, chartPercentChange) = (NSDecimalNumber.one, NSDecimalNumber.one)
        (maxHigh, minLow, lastPrice, scaledLow) = (NSDecimalNumber.zero, NSDecimalNumber.zero, NSDecimalNumber.zero, NSDecimalNumber.zero)
        (ready, busy, sma50, sma200, bb20) = (false, false, false, false, false)
        super.init()
    }
    
    /// Request historical stock data price from DB and then remote server
    @objc func fetchStockData() {
        if let fetcher = fetcher {
            calculateMovingAverages()
            fetcher.requestNewest = Date()
            fetcher.setRequestOldestWith(startString: stock.startDateString)
            newest = fetcher.requestOldest // fetcher converts string to date
            
            fetcher.ticker = stock.ticker
            fetcher.stockId = stock.id
            fetcher.gregorian = gregorian
            fetcher.delegate = self
            fetcher.fetchNewerThanDate(currentNewest: Date.distantPast)
            
            if stock.fundamentalList.count > 4 {
                delegate?.showProgressIndicator()
                fundamentalFetcher = FundamentalFetcher()
                fundamentalFetcher?.getFundamentals(for: stock, withDelegate: self)
            }
        }
    }
    
    /// FundamentalFetcher calls StockData with the columns parsed out of the API
    @objc func fetcherLoadedFundamentals(_ columns: [String : [NSDecimalNumber]]) {
        fundamentalColumns = columns
        
        if busy == false && periodData.count > 0 {
            concurrentQueue?.sync(flags: .barrier) {
                updateFundamentalFetcherBarAlignment()
                computeChart()
            }
            delegate?.requestFinished(percentChange)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.stopProgressIndicator()
            }
        }
    }
    
    /// Price data for bar under user's finger during long press
    @objc func bar(at index: Int) -> BarData {
        guard index >= 0 && index < periodData.count else { return BarData() }
        let bar = periodData[index]
        bar.upClose = true
        if index < periodData.count - 2 {
            if bar.close < periodData[index + 1].close {
                bar.upClose = false
            }
        } else if periodData[index].close < periodData[index].open {
            bar.upClose = false
        }
        return bar
    }
    
    /// Update values used to scale price data: pxHeight, sparklineHeight, volumeHeight, volumeBase, chartHeight
    @objc func setPxHeight(_ h: Double, sparklineHeight s: Double) {
        sparklineHeight = s
        pxHeight = h - sparklineHeight
        volumeHeight = 40 * UIScreen.main.scale
        volumeBase = h - volumeHeight/2
        chartBase = volumeBase - volumeHeight/2 - sparklineHeight
    }
    
    /// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
    @objc func invalidateAndCancel() {
        // fundamentalFetcher uses the sharedSession so don't invalidate it
        fundamentalFetcher?.delegate = nil
        fundamentalFetcher = nil // will trigger deinit on fundamentalFetcher
        fetcher?.invalidateAndCancel() // Also sets delegate = nil
        fetcher = nil
    }
    
    func calculateMovingAverages() {
        let sma50old = sma50
        let sma200old = sma200
        sma50 = self.stock.technicalList.contains("sma50")
        sma200 = self.stock.technicalList.contains("sma200")
        
        if (sma200 && !sma200old) || (sma50 && !sma50old) {
            calculateSMA()
        }
        
        if self.stock.technicalList.contains("bollingerBand") {
            if !bb20 {
                calculateBollingerBands()
            }
            bb20 = true
        } else {
            bb20 = false
        }
    }
    
    /// Returns all fundamental metric keys or [] if fundamentals aren't loaded
    @objc func fundamentalKeys() -> [String] {
        if !fundamentalColumns.isEmpty {
            return Array(fundamentalColumns.keys)
        }
        return []
    }

    /// Metric value (or .notANumber) for a report index and metric key
    @objc func fundamentalValue(forReport report: Int, metric: String) -> NSDecimalNumber {
        if !fundamentalColumns.isEmpty {
            if let valuesForMetric = fundamentalColumns[metric], report < valuesForMetric.count {
                return valuesForMetric[report]
            }
        }
        return NSDecimalNumber.notANumber
    }
    
    /// Calculate 50 and 200 period simple moving averages starting from the last bar in periodData
    func calculateSMA() {
        let oldest50available = self.periodData.count - 50
        let oldest200available = self.periodData.count - 200
        
        if oldest50available > 0 {
            var movingSum50: Double = 0.0
            var movingSum150: Double = 0.0
            
            for i in (0..<self.periodData.count).reversed() {
                movingSum50 += self.periodData[i].close
                
                if i < oldest50available {
                    movingSum150 += self.periodData[i + 50].close
                    movingSum50 -= self.periodData[i + 50].close
                    
                    if i < oldest200available {
                        movingSum150 -= self.periodData[i + 200].close
                        // i + n - 1, so for bar zero it subtracks bar 199 (200th bar)
                        self.periodData[i].movingAvg2 = (movingSum50 + movingSum150) / 200
                    } else if i == oldest200available {
                        self.periodData[i].movingAvg2 = (movingSum50 + movingSum150) / 200
                    }
                    
                    self.periodData[i].movingAvg1 = movingSum50 / 50
                } else if i == oldest50available {
                    self.periodData[i].movingAvg1 = movingSum50 / 50
                }
            }
        }
    }
    
    /// Bollinger bands use a 20 period simple moving average with parallel bands a standard deviation above and below
    /// Upper Band = 20-day SMA + (20-day standard deviation of price x 2)
    /// Lower Band = 20-day SMA - (20-day standard deviation of price x 2)
    /// Use regular close instead of adjusted close or the bollinger bands will deviate from price for stocks or ETFs with dividends
    func calculateBollingerBands() {
        let period = 20
        let firstFullPeriod = self.periodData.count - period
        
        if firstFullPeriod > 0 {
            var movingSum: Double = 0.0
            var powerSumAvg: Double = 0.0
            
            for i in (0..<self.periodData.count).reversed() {
                movingSum += self.periodData[i].close
                
                if i < firstFullPeriod {
                    movingSum -= self.periodData[i + period].close
                    
                    self.periodData[i].mbb = movingSum / Double(period)
                    
                    powerSumAvg += (self.periodData[i].close * self.periodData[i].close - self.periodData[i + period].close * self.periodData[i + period].close) / Double(period)
                    
                    self.periodData[i].stdev = sqrt(powerSumAvg - self.periodData[i].mbb * self.periodData[i].mbb)
                    
                } else if i >= firstFullPeriod {
                    powerSumAvg += (self.periodData[i].close * self.periodData[i].close - powerSumAvg) / Double(self.periodData.count - i)
                    
                    if i == firstFullPeriod {
                        self.periodData[i].mbb = movingSum / Double(period)
                        self.periodData[i].stdev = sqrt(powerSumAvg - self.periodData[i].mbb * self.periodData[i].mbb)
                    }
                }
            }
        }
    }

    /// Align the array of fundamental data points to an offset into the self.periodData array
    func updateFundamentalFetcherBarAlignment() {
        if let fundamentalFetcher = self.fundamentalFetcher,
           !fundamentalFetcher.isLoadingData,
           fundamentalFetcher.columns.count > 0 {
            
            var i = 0
            for r in 0 ..< fundamentalFetcher.year.count {
                let lastReportYear = fundamentalFetcher.year[r]
                let lastReportMonth = fundamentalFetcher.month[r]
                
                while i < periodData.count &&
                    (periodData[i].year > lastReportYear || periodData[i].month > lastReportMonth) {
                    i += 1
                }
                
                if i < periodData.count && periodData[i].year == lastReportYear
                    && periodData[i].month == lastReportMonth {
                    fundamentalFetcher.setBarAlignment(i, report: r)
                }
            }
        }
    }
    
    /// Called after shiftRedraw shifts self.oldestBarShown and newestBarShown during scrolling
    @objc func updateHighLow() {
        if periodData.count == 0 {
            NSLog("No bars, so exiting")
            return
        }
        
        if oldestBarShown <= 0 {
            print("Resetting oldestBarShown \(oldestBarShown) to MIN(50, \(periodData.count))")
            oldestBarShown = min(50, periodData.count)
        } else if oldestBarShown >= periodData.count {
            oldestBarShown = periodData.count - 1
        }
        
        var max: Double = 0.0
        var min: Double = 0.0
        maxVolume = 0.0
        
        for a in (newestBarShown ... oldestBarShown).reversed() {
            if periodData[a].volume > maxVolume {
                maxVolume = periodData[a].volume
            }
            
            if periodData[a].low > 0.0 {
                if min == 0.0 {
                    min = periodData[a].low
                } else if min > periodData[a].low {
                    min = periodData[a].low
                }
            }
            
            if max < periodData[a].high {
                max = periodData[a].high
            }
        }
        
        maxHigh = NSDecimalNumber(floatLiteral: max)
        minLow = NSDecimalNumber(floatLiteral: min)
        scaledLow = minLow
        
        if minLow.doubleValue > 0 {
            percentChange = maxHigh.dividing(by: minLow)
            
            if percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = percentChange
            }
            scaledLow = maxHigh.dividing(by: chartPercentChange)
            
            let range = maxHigh.subtracting(scaledLow)
            if range.isEqual(to: NSDecimalNumber.zero) == false {
                yFactor = chartBase / range.doubleValue;
            } else {
                print("Avoiding divide by zero on chart with maxHigh == minLow by using default yFactor")
                yFactor = 50.0
            }
        }
        computeChart()
    }

    /// User panned chart by barsShifted
    @objc func shiftRedraw(_ barsShifted: Int, withBars screenBarWidth: Int) -> NSDecimalNumber {
         if oldestBarShown + barsShifted >= periodData.count {
             print("early return because oldestBarShown \(oldestBarShown) + barsShifted \(barsShifted) > \(periodData.count) barCount")
             return percentChange
         }
         oldestBarShown += barsShifted

         newestBarShown = (oldestBarShown - screenBarWidth) // handles negative values

         if oldestBarShown <= 0 { // nothing to show yet
             print("\(stock.ticker) oldestBarShown is less than zero at \(oldestBarShown)")
             clearChart()
         } else if busy {
             // Avoid deadlock by limiting concurrentQueue to updateHighLow and didFinishFetch*
             concurrentQueue?.sync {
                 updateHighLow()
             }
             return percentChange
         }

        if let fetcher = fetcher, 0 == newestBarShown {
             if fetcher.shouldFetchIntradayQuote() {
                 busy = true
                 fetcher.fetchIntradayQuote()
             } else if fetcher.isLoadingData == false && fetcher.nextClose.compare(Date()) == .orderedAscending {
                 // next close is in the past
                 print("api.nextClose \(fetcher.nextClose) vs now \(Date())")
                 busy = true
                 delegate?.showProgressIndicator()
                 fetcher.fetchNewerThanDate(currentNewest: newest)
             }
         }
         concurrentQueue?.sync {
             updateHighLow()
         }
         return percentChange
     }
    
    /// Determines if the percent change has increased and we need to redraw/
    @objc func recompute(_ maxPercentChange: NSDecimalNumber, forceRecompute force: Bool) {
        
        calculateMovingAverages()
        let pctDifference = maxPercentChange.subtracting(self.chartPercentChange).doubleValue
        if force || pctDifference > 0.02 {
            chartPercentChange = maxPercentChange
            scaledLow = maxHigh.dividing(by: chartPercentChange)
            
            concurrentQueue?.sync {
                computeChart()
            }
        } else {
            chartPercentChange = maxPercentChange
            scaledLow = maxHigh.dividing(by: self.chartPercentChange)
        }
    }
    
    /// DataFetcher has an active download that must be allowed to finish or fail before accepting an additional request
    func fetcherCanceled() {
        busy = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.requestFailed(withMessage: "Canceled request")
        }
    }

    /// DataFetcher failed downloading historical data or intraday data
    func fetcherFailed(_ message: String) {
        busy = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.requestFailed(withMessage: message)
        }
    }
    
    /// DataFetcher calls StockData with intraday price data
    func fetcherLoadedIntradayBar(_ intradayBar: BarData) {
        
        // Avoid deadlock by limiting concurrentQueue to updateHighLow and fetcherLoaded*
        concurrentQueue?.sync(flags: .barrier) {
            if let apiNewest = fetcher?.date(from: intradayBar) {
                let dateDiff = apiNewest.timeIntervalSince(self.newest)
                
                let dayInSeconds: TimeInterval = 84600
                if dateDiff < dayInSeconds { // Update existing intraday bar
                    dailyData[0] = intradayBar
                } else {
                    dailyData.insert(intradayBar, at: 0)
                }
                
                lastPrice = NSDecimalNumber(value: dailyData[0].close)
                newest = apiNewest
                
                // For intraday update to weekly or monthly chart, decrement self.oldestBarShown only if
                //    the intraday bar is for a different period (week or month) than the existing newest bar
                
                updatePeriodDataByDayWeekOrMonth()
                updateHighLow() // must be a separate call to handle daysAgo shifting
                busy = false
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.requestFinished(self.percentChange)
        }
    }
    
    /// Update periodData by grouping dailyData by week and advancing to older dates
    func groupByWeek() {
        var startDate = newest
        var dayIndex = 0
        var weekIndex = 0

        repeat {
            let weeklyBar = BarData()
            self.periodData.insert(weeklyBar, at: weekIndex)
            weeklyBar.close = dailyData[dayIndex].close
            weeklyBar.adjClose = dailyData[dayIndex].adjClose
            weeklyBar.high = dailyData[dayIndex].high
            weeklyBar.low = dailyData[dayIndex].low
            weeklyBar.volume = dailyData[dayIndex].volume
            weeklyBar.movingAvg1 = 0.0
            weeklyBar.movingAvg2 = 0.0
            weeklyBar.mbb = 0.0
            weeklyBar.stdev = 0.0
            
            var componentsToSubtract = DateComponents()
            let weekdayComponents = self.gregorian.component(.weekday, from: startDate)
                        
            // Get the previous Friday, convert it into an NSInteger and then group all dates LARGER than it into the current week
            // Friday is weekday 6 in Gregorian calendar, so subtract current weekday and -1 to get previous Friday
            componentsToSubtract.day = -1 - weekdayComponents
            let lastFriday = gregorian.date(byAdding: componentsToSubtract, to: startDate)!

            let lastFridayY = gregorian.component(.year, from: lastFriday)
            let lastFridayM = gregorian.component(.month, from: lastFriday)
            let lastFridayD = gregorian.component(.day, from: lastFriday)
            
            
            let lastFridayDateInt: Int = 10000 * lastFridayY + 100 * lastFridayM + lastFridayD
            
            dayIndex += 1
            while dayIndex < dailyData.count &&
                    dailyData[dayIndex].dateIntFromBar() > lastFridayDateInt {

                if dailyData[dayIndex].high > weeklyBar.high {
                    weeklyBar.high = dailyData[dayIndex].high
                }
                if dailyData[dayIndex].low < weeklyBar.low {
                    weeklyBar.low = dailyData[dayIndex].low
                }
                weeklyBar.volume += dailyData[dayIndex].volume
                dayIndex += 1
            }
            
            weeklyBar.year = dailyData[dayIndex - 1].year
            weeklyBar.month = dailyData[dayIndex - 1].month
            weeklyBar.day = dailyData[dayIndex - 1].day
            weeklyBar.open = dailyData[dayIndex - 1].open
            
            startDate = lastFriday
            weekIndex += 1
        } while dayIndex < dailyData.count // continue loop
    }

    func groupByMonth() {
        var dayIndex = 0
        var monthIndex = 0
        repeat {
            let monthlyBar = BarData()
            self.periodData.insert(monthlyBar, at: monthIndex)
            
            monthlyBar.close = dailyData[dayIndex].close
            monthlyBar.adjClose = dailyData[dayIndex].adjClose
            monthlyBar.high = dailyData[dayIndex].high
            monthlyBar.low = dailyData[dayIndex].low
            monthlyBar.volume = dailyData[dayIndex].volume
            monthlyBar.year = dailyData[dayIndex].year
            monthlyBar.month = dailyData[dayIndex].month
            monthlyBar.movingAvg1 = 0.0
            monthlyBar.movingAvg2 = 0.0
            monthlyBar.mbb = 0.0
            monthlyBar.stdev = 0.0
            
            dayIndex += 1
            while dayIndex < dailyData.count && dailyData[dayIndex].month == monthlyBar.month {
                if dailyData[dayIndex].high > monthlyBar.high {
                    monthlyBar.high = dailyData[dayIndex].high
                }
                if dailyData[dayIndex].low < monthlyBar.low {
                    monthlyBar.low = dailyData[dayIndex].low
                }
                monthlyBar.volume += dailyData[dayIndex].volume
                dayIndex += 1
            }
            
            monthlyBar.open = dailyData[dayIndex - 1].open
            monthlyBar.day = dailyData[dayIndex - 1].day
            monthIndex += 1
        } while dayIndex < dailyData.count // continue loop
    }

    /// Return the number of bars at the newBarUnit scale to check if one stock in a comparison
    /// will limit the date range that can be charted in the comparison
    @objc func maxPeriodSupported(barUnit: CGFloat) -> Int {
        return Int(floor(Double(dailyData.count) / barUnit));
    }

    /// User zoomed in or out so rescale dailyData by the updated barUnit
    @objc func updatePeriodDataByDayWeekOrMonth() {
        if barUnit == 1.0 {
            periodData = dailyData
        } else {
            periodData = []
        }
            
        if barUnit > 5 {
            groupByMonth()
        } else if barUnit > 3 {
            groupByWeek()
        }
        updateFundamentalFetcherBarAlignment()

        if sma200 || sma50 {
            calculateSMA()
        }

        if bb20 {
            calculateBollingerBands()
        }

        // Don't call updateHighLow here because summarizeByDate doesn't consider daysAgo,
        // but updateHighLow must be called AFTER shifting newestBarShown
    }
    
    /// DataFetcher calls StockData with the array of historical price data
    func fetcherLoadedHistoricalData(_ loadedData: [BarData]) {
        guard loadedData.count > 0 else { return }
        
        /* Three cases since intraday updates are a separate callback:
         1. First request: [self.dailyData addObjectsFromArray:dataAPI.dailyData];
         2. Insert newer dates (not intraday update): [self.dailyData insertObjects:dataAPI.dailyData atIndexes:indexSet];
         3. Append older dates: [self.dailyData addObjectsFromArray:dataAPI.dailyData];
         */
        
        concurrentQueue?.sync(flags: .barrier) {
            let newestBar = loadedData[0]
            if let apiNewest = fetcher?.date(from: newestBar),
               let apiOldest = fetcher?.oldestDate {
                
                if dailyData.isEmpty { // case 1: First request
                    newest = apiNewest
                    lastPrice = NSDecimalNumber(value: newestBar.close)
                    oldest = apiOldest
                    
                    print("\(stock.ticker) added \(loadedData.count) new barData.count to \(dailyData.count) exiting dailyData.count")
                    
                    dailyData.append(contentsOf: loadedData)
                    
                } else if newest.compare(apiNewest) == .orderedAscending { // case 2: Newer dates
                    print("api is newer, so inserting \(loadedData.count) bars at start of dailyData")
                    
                    for i in 0..<loadedData.count {
                        dailyData.insert(loadedData[i], at: i)
                    }
                    
                    newest = apiNewest
                    lastPrice = NSDecimalNumber(value: newestBar.close)
                    
                } else if oldest.compare(apiOldest) == .orderedDescending { // case 3: Older dates
                    dailyData.append(contentsOf: loadedData)
                    
                    print("\(stock.ticker) older dates \(loadedData.count) new barData.count to \(dailyData.count) exiting dailyData.count")
                    
                    oldest = apiOldest
                }
                
                updatePeriodDataByDayWeekOrMonth()
                
                updateHighLow()
                
                if fetcher?.shouldFetchIntradayQuote() == true {
                    busy = true
                    fetcher?.fetchIntradayQuote()
                } else {
                    busy = false
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.stopProgressIndicator()
                    }
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.requestFinished(self.percentChange)
        }
    }
    
    /// Center a stroked line in the center of a pixel.  From a point context, it can be at 0.25, 0.333, 0.5, 0.666, or 0.75
    /// bitmap graphics always use pixel context, so they always have alignTo=0.5
    @objc func pxAlign(_ input: Double, alignTo: Double) -> Double {
        var intPart = 0.0
        if modf(input, &intPart) != alignTo { // modf separates integer and fractional parts
            return intPart + alignTo
        }
        return input
    }
    
    func clearChart() {
        tmpElements.clear()
    }
    
    /// Calculate chartElements from periodData (which may point to dailyData or be a grouped version of it)
    func computeChart() {
        ready = false
        var xRaw: CGFloat = xFactor / 2
        var oldestClose: Double = 0
        var oldestValidBar: Int = 0
        
        clearChart()
        
        if oldestBarShown < 1 || periodData.count == 0 {
            ready = true
            return // No bars to draw
        } else if oldestBarShown < periodData.count {
            oldestValidBar = oldestBarShown
            if oldestValidBar < periodData.count - 1 {
                oldestClose = periodData[oldestValidBar + 1].close
            } else {
                oldestClose = periodData[oldestValidBar].open // No older data so use open in lieu of prior close
            }
        } else { // user scrolled older than dates available
            oldestValidBar = periodData.count - 1
            xRaw += xFactor * Double(oldestBarShown - oldestValidBar)
            oldestClose = periodData[oldestValidBar].open // No older data so use open in lieu of prior close
        }
        computeFundamentalBarPixelAlignments(from: oldestValidBar, xRaw: xRaw)
        computeChartElements(from: oldestValidBar, oldestClose: oldestClose, xRaw: xRaw)

        ready = true
    }
 
    /// Completes computing ChartElements after computeChart sets oldestValidBar, oldestClose and xRaw
    func computeChartElements(from oldestValidBar: Int, oldestClose: Double, xRaw: CGFloat) {
        var oldestClose = oldestClose
        var xRaw = xRaw
        let volumeFactor = maxVolume/volumeHeight
        var barCenter: CGFloat = 0
        var barHeight: CGFloat = 0
        yFloor = yFactor * maxHigh.doubleValue + sparklineHeight
        var lastMonth = periodData[oldestValidBar].month

        for a in stride(from: oldestValidBar, through: newestBarShown, by: -1) {
            barCenter = pxAlign(xRaw, alignTo: 0.5)
            
            if periodData[a].month != lastMonth {
                var label = periodData[a].monthName()
                if periodData[a].month == 1 {
                    let shortYearString = String(periodData[a].year % 100)
                    if periodData.count < dailyData.count || xFactor < 4 { // not enough room
                        label = shortYearString
                    } else {
                        label = label + shortYearString
                    }
                } else if barUnit > 5 { // only year markets
                    label = ""
                } else if periodData.count < dailyData.count || xFactor < 2 { // shorten months
                    label = String(label.prefix(1))
                }
                
                if !label.isEmpty {
                    tmpElements.monthLabels.add(label)
                    tmpElements.monthLines.add(CGPoint(x: barCenter - 2, y: sparklineHeight))
                    tmpElements.monthLines.add(CGPoint(x: barCenter - 2, y: volumeBase))
                }
            }
            lastMonth = periodData[a].month
            
            if stock.chartType == .ohlc || stock.chartType == .hlc {
                if oldestClose > periodData[a].close { // green bar
                    if stock.chartType == .ohlc { // include open
                        tmpElements.redPoints.add(CGPoint(x: barCenter - xFactor/2, y: yFloor - yFactor * periodData[a].open))
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].open))
                    }
                    
                    tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                    tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                    
                    tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].close))
                    tmpElements.redPoints.add(CGPoint(x: barCenter + xFactor/2, y: yFloor - yFactor * periodData[a].close))
                } else { // red bar
                    if stock.chartType == .ohlc { // include open
                        tmpElements.points.add(CGPoint(x: barCenter - xFactor/2, y: yFloor - yFactor * periodData[a].open))
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].open))
                    }
                    
                    tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                    tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                    
                    tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].close))
                    tmpElements.points.add(CGPoint(x: barCenter + xFactor/2, y: yFloor - yFactor * periodData[a].close))
                }
            } else if stock.chartType == .candle {
                barHeight = yFactor * (periodData[a].open - periodData[a].close)
                if abs(barHeight) < 1 {
                    barHeight = barHeight > 0 ? 1 : -1  // min 1 px height either up or down
                }
                                
                if periodData[a].open >= periodData[a].close { // filled bar (StockCharts colors closes higher > lastClose && close < open as filled black barData.count)
                    if oldestClose < periodData[a].close { // filled green bar
                        let rect = CGRect(x: barCenter - xFactor * 0.4,
                                          y: yFloor - yFactor * periodData[a].open,
                                          width: 0.8 * xFactor, height: barHeight)
                        tmpElements.filledGreenBars.add(rect)
                
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                    } else {
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                        
                        tmpElements.redBars.add(CGRect(x: barCenter - xFactor * 0.4,
                                                       y: yFloor - yFactor * periodData[a].open,
                                                       width: 0.8 * xFactor, height: barHeight))
                    }
                } else {
                    if oldestClose > periodData[a].close { // red hollow bar
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].close))
                        
                        tmpElements.hollowRedBars.add(CGRect(x: barCenter - xFactor * 0.4,
                                                             y: yFloor - yFactor * periodData[a].open,
                                                             width: 0.8 * xFactor, height: barHeight))
                        
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].open))
                        tmpElements.redPoints.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                    } else {
                        tmpElements.greenBars.add(CGRect(x: barCenter - xFactor * 0.4,
                                                         y: yFloor - yFactor * periodData[a].open,
                                                         width: 0.8 * xFactor, height: barHeight))
                        
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].high))
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].close))
                        
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].open))
                        tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].low))
                    }
                }
            } else if stock.chartType == .close {
                tmpElements.points.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].close))
            }
            if sma50 && periodData[a].movingAvg1 > 0 {
                tmpElements.movingAvg1.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].movingAvg1))
            }
            if sma200 && periodData[a].movingAvg2 > 0 {
                tmpElements.movingAvg2.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].movingAvg2))
            }
            if bb20 && periodData[a].mbb > 0 {
                tmpElements.upperBollingerBand.add(CGPoint(x: barCenter, y: yFloor - yFactor * (periodData[a].mbb + 2*periodData[a].stdev)))
                tmpElements.middleBollingerBand.add(CGPoint(x: barCenter, y: yFloor - yFactor * periodData[a].mbb))
                tmpElements.lowerBollingerBand.add(CGPoint(x: barCenter, y: yFloor - yFactor * (periodData[a].mbb - 2*periodData[a].stdev)))
            }
            if periodData[a].volume > 0 {
                let rect = CGRect(x: barCenter - xFactor/2,
                                  y: volumeBase,
                                  width: xFactor, height: -1 * periodData[a].volume/volumeFactor)
                if oldestClose > periodData[a].close {
                    tmpElements.redVolume.add(rect)
                } else {
                    tmpElements.blackVolume.add(rect)
                }
            }
            oldestClose = periodData[a].close
            xRaw += xFactor            // keep track of the unaligned value or the chart will end too soon
        }

    }
    
    /// Computes fundamental bar pixel alignment after computeChart sets oldestValidBar and xRaw
    func computeFundamentalBarPixelAlignments(from oldestValidBar: Int, xRaw: CGFloat) {
        if let fundamentalFetcher = fundamentalFetcher,
            fundamentalFetcher.isLoadingData == false && fundamentalFetcher.columns.count > 0 {
            
            oldestReport = fundamentalFetcher.year.count - 1
            
            newestReport = 0
            var lastBarAlignment = 0
            
            for r in 0...oldestReport {
                
                lastBarAlignment = fundamentalFetcher.barAlignmentFor(report: r)
                
                if newestReport > 0 && lastBarAlignment == -1 {
                    // NSLog("ran out of trading data after report \(newestReport)")
                } else if lastBarAlignment > 0 && lastBarAlignment <= newestBarShown {
                    // NSLog("lastBarAlignment \(lastBarAlignment) <= \(newestBarShown) so newestReport = \(r)")
                    newestReport = r
                }
                
                if lastBarAlignment > oldestValidBar || lastBarAlignment == -1 {
                    oldestReport = r       // first report just out of view
                    // NSLog("lastBarAlignment \(lastBarAlignment) > \(oldestValidBar) oldestValidBar or not defined")
                    break
                }
            }
            
            if oldestReport == newestReport {     // include offscreen report
                if newestReport > 0 {
                    newestReport -= 1
                } else if oldestReport == 0 {
                    oldestReport += 1
                }
            }
            
            var r = newestReport
            newestReportInView = newestReport
            
            // Avoid showing any previous pixel alignments prior to user pan or zoom
            let offscreen: Int = -1
            for i in 0 ..< tmpElements.fundamentalAlignments.count {
                tmpElements.fundamentalAlignments[i] = CGFloat(offscreen)
            }
            var barAlignment = offscreen
            lastBarAlignment = offscreen
            
            repeat {
                lastBarAlignment = barAlignment
                barAlignment = fundamentalFetcher.barAlignmentFor(report: r)
                if barAlignment < 0 {
                    break
                }
                let xPosition = Double(oldestValidBar - barAlignment + 1) * xFactor + xRaw
                tmpElements.fundamentalAlignments[r] = NSDecimalNumber(floatLiteral: xPosition)
                r += 1
            } while r <= oldestReport
            
            if barAlignment < 0 {
                let xPosition = Double(oldestValidBar - barAlignment + 1) * xFactor + xRaw
                tmpElements.fundamentalAlignments[r] = NSDecimalNumber(floatLiteral: xPosition)
            }
            oldestReportInView = r
        }
    }
    
    /// Create a readonly copy of the values mutated on a background thread by computeChart for use on the mainThread
    /// This is primarily needed for intraday updates which can return fast enough (especially in the simulator) to be ready
    /// to mutate the array values while ScrollChartView is iterating through the arrays.
    @objc func copyChartElements() {
        concurrentQueue?.sync(flags: .barrier) {
            chartElements = tmpElements.copy() as! ChartElements // copy() returns an Any
        }
    }
}
