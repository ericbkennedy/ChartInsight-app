//
//  StockActor.swift
//  ChartInsight
//
//  Delegates fetching of stock price and fundamental data (to DataFetcher and FundamentalFetcher).
//  After DataFetcherDelegate methods are called, StockActor computes ChartElements for all of the returned data
//  and notifies its delegate (ScrollChartView) that it is ready.
//  ScrollChartView calls copyChartElements() to get a thread-safe copy it can render while
//  StockActor is free to update its own copy (in tmp) as new data loads.
//
//  Created by Eric Kennedy on 6/27/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

protocol StockActorDelegate: AnyObject {
    func showProgressIndicator()
    func stopProgressIndicator()
    func requestFailed(message: String)
    func requestFinished(newPercentChange: NSDecimalNumber)
}

actor StockActor: DataFetcherDelegate {
    var stock: Stock
    private let gregorian: Calendar
    weak var delegate: ScrollChartView?

    var newestBarShown: Int
    var oldestBarShown: Int
    private var xFactor: CGFloat // yFactor and yFloor are on chartElements
    private var barUnit: CGFloat

    var ready = false // true if StockActor has been loaded, computed and copied into chartElements.
    private var tmp: ChartElements // caller must request a copy with copyChartElements()
    private var busy = false // true if it is currently recomputing tmp chart elements.

    private var percentChange: NSDecimalNumber
    private var chartPercentChange: NSDecimalNumber

    private var oldest: Date
    private var newest: Date // newest loaded, not the newest shown
    private var dailyData: [BarData]
    private var periodData: [BarData] // points to dailyData or dailyData grouped by week or month
    private var fetcher: DataFetcher?
    private var fundamentalFetcher: FundamentalFetcher?
    private var sma50: Bool
    private var sma200: Bool
    private var bb20: Bool
    private var pxHeight: Double
    private var sparklineHeight: Double
    private var maxVolume: Double
    private var chartBase: Double
    private var volumeBase: Double
    private var volumeHeight: Double

    init(stock: Stock, gregorian: Calendar, delegate: ScrollChartView, oldestBarShown: Int, barUnit: CGFloat, xFactor: CGFloat) {
        self.stock = stock
        self.gregorian = gregorian
        self.delegate = delegate
        self.oldestBarShown = oldestBarShown
        self.barUnit = barUnit
        self.xFactor = xFactor * barUnit
        newestBarShown = 0
        fetcher = DataFetcher()
        fundamentalFetcher = FundamentalFetcher()
        tmp = ChartElements(stock: stock)
        periodData = []
        dailyData = []
        (oldest, newest) = (Date.distantPast, Date.distantPast)
        (pxHeight, sparklineHeight, chartBase, volumeBase, volumeHeight, maxVolume) = (0, 0, 0, 0, 0, 0)
        (percentChange, chartPercentChange) = (NSDecimalNumber.one, NSDecimalNumber.one)
        (ready, busy, sma50, sma200, bb20) = (false, false, false, false, false)
    }

    func setNewestBarShown(_ calculatedNewestBarShown: Int) {
        newestBarShown = max(0, calculatedNewestBarShown)
    }

    func setOldestBarShown(_ calculatedOldestBarShown: Int) {
        oldestBarShown = max(0, calculatedOldestBarShown)
    }

    /// Request historical stock data price from DB and then remote server
    func fetchStockActor() {
        if let fetcher = fetcher {
            fetcher.requestNewest = Date()
            fetcher.setRequestOldestWith(startString: stock.startDateString)
            newest = fetcher.requestOldest // fetcher converts string to date

            fetcher.ticker = stock.ticker
            fetcher.stockId = stock.id
            fetcher.gregorian = gregorian
            fetcher.delegate = self
            fetcher.fetchNewerThanDate(currentNewest: Date.distantPast)

            if stock.fundamentalList.count > 4 {
                fundamentalFetcher = FundamentalFetcher()
                fundamentalFetcher?.getFundamentals(for: stock, delegate: self)
            }
        }
    }

    /// FundamentalFetcher calls StockActor with the columns parsed out of the API
    func fetcherLoadedFundamentals(columns: [String: [NSDecimalNumber]], alignments: [FundamentalAlignment]) async {
        tmp.fundamentalColumns = columns
        tmp.fundamentalAlignments = alignments
        updateFundamentalFetcherBarAlignment()
        computeChart()
        await delegate?.requestFinished(newPercentChange: percentChange)
    }

    /// Returns (BarData, monthName) for bar under user's finger during long press
    func bar(at index: Int) -> (BarData, String)? {
        guard index >= 0 && index < periodData.count else { return nil }
        let bar = periodData[index]
        bar.upClose = true
        if index < periodData.count - 2 {
            if bar.close < periodData[index + 1].close {
                bar.upClose = false
            }
        } else if periodData[index].close < periodData[index].open {
            bar.upClose = false
        }
        return (bar, bar.monthName(calendar: gregorian))
    }

    /// Update values used to scale price data: pxHeight, sparklineHeight, volumeHeight, volumeBase, chartHeight
    public func setPxHeight(_ height: Double, sparklineHeight: Double, scale: CGFloat) {
        self.sparklineHeight = sparklineHeight
        pxHeight = height - sparklineHeight
        volumeHeight = 40 * scale
        volumeBase = height - volumeHeight/2
        chartBase = volumeBase - volumeHeight/2 - sparklineHeight
    }

    /// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
    func invalidateAndCancel() {
        // fundamentalFetcher uses the sharedSession so don't invalidate it
        fundamentalFetcher?.delegate = nil
        fundamentalFetcher = nil // will trigger deinit on fundamentalFetcher
        fetcher?.invalidateAndCancel() // Also sets delegate = nil
        fetcher = nil
        delegate = nil
    }

    /// Determine if moving averages are in the technicalList and if so compute them
    func calculateMovingAverages() {
        sma50 = stock.technicalList.contains("sma50")
        sma200 = stock.technicalList.contains("sma200")
        bb20 = stock.technicalList.contains("bollingerBand")

        if sma200 || sma50 {
            BarData.calculateSMA(periodData: periodData)
        }
        if bb20 {
            BarData.calculateBollingerBands(periodData: periodData)
        }
    }

    /// Align the array of fundamental data points to an offset into the self.periodData array
    private func updateFundamentalFetcherBarAlignment() {
        if tmp.fundamentalAlignments.isEmpty == false {
            var index = 0
            for reportIndex in 0 ..< tmp.fundamentalAlignments.count {
                let lastReportYear = tmp.fundamentalAlignments[reportIndex].year
                let lastReportMonth = tmp.fundamentalAlignments[reportIndex].month

                while index < periodData.count &&
                    (periodData[index].year > lastReportYear || periodData[index].month > lastReportMonth) {
                    index += 1
                }

                if index < periodData.count && periodData[index].year == lastReportYear
                    && periodData[index].month == lastReportMonth {
                    tmp.setBarAlignment(index, report: reportIndex)
                }
            }
        }
    }

    /// Called after shiftRedraw shifts self.oldestBarShown and newestBarShown during scrolling
    func updateHighLow() {
        if periodData.count == 0 {
            return
        }

        if oldestBarShown <= 0 {
            print("Resetting oldestBarShown \(oldestBarShown) to MIN(50, \(periodData.count))")
            oldestBarShown = min(50, periodData.count)
            newestBarShown = 0 // ensures newestBarShown < oldestBarShown in for loop
        } else if oldestBarShown >= periodData.count {
            oldestBarShown = periodData.count - 1
        }

        var max: Double = 0.0, min: Double = 0.0
        maxVolume = 0.0

        for index in (newestBarShown ... oldestBarShown).reversed() {
            if periodData[index].volume > maxVolume {
                maxVolume = periodData[index].volume
            }
            if periodData[index].low > 0.0 {
                if min == 0.0 {
                    min = periodData[index].low
                } else if min > periodData[index].low {
                    min = periodData[index].low
                }
            }
            if max < periodData[index].high {
                max = periodData[index].high
            }
        }

        tmp.maxHigh = NSDecimalNumber(value: max)
        tmp.minLow = NSDecimalNumber(value: min)
        tmp.scaledLow = tmp.minLow

        if tmp.minLow.doubleValue > 0 {
            percentChange = tmp.maxHigh.dividing(by: tmp.minLow)

            if percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = percentChange
            }
            tmp.scaledLow = tmp.maxHigh.dividing(by: chartPercentChange)

            let range = tmp.maxHigh.subtracting(tmp.scaledLow)
            if range.isEqual(to: NSDecimalNumber.zero) == false {
                tmp.yFactor = chartBase / range.doubleValue
            } else {
                print("Avoiding divide by zero on chart with tmp.maxHigh == tmp.minLow by using default tmp.yFactor")
                tmp.yFactor = 50.0
            }
        }
        computeChart()
    }

    /// User panned ScrollChartView by barsShifted
    func shiftRedraw(_ barsShifted: Int, screenBarWidth: Int) async -> NSDecimalNumber {
        if oldestBarShown + barsShifted >= periodData.count {
            print("oldestBarShown \(oldestBarShown) + barsShifted \(barsShifted) > \(periodData.count) barCount")
            return percentChange
        }
        oldestBarShown += barsShifted
        newestBarShown = max(0, oldestBarShown - screenBarWidth) // avoid negative values

        if oldestBarShown <= 0 { // nothing to show yet
            print("\(stock.ticker) oldestBarShown is less than zero at \(oldestBarShown)")
            tmp.clear()
        }

        if let fetcher = fetcher, 0 == newestBarShown && busy == false {
            if fetcher.shouldFetchIntradayQuote() {
                busy = true
                await fetcher.fetchIntradayQuote()
            } else if fetcher.isLoadingData == false && fetcher.nextClose.compare(Date()) == .orderedAscending {
                // next close is in the past
                print("api.nextClose \(fetcher.nextClose) vs now \(Date())")
                busy = true
                await delegate?.showProgressIndicator()
                fetcher.fetchNewerThanDate(currentNewest: newest)
            }
        }
        return percentChangeAfterUpdateHighLow()
    }

    public func percentChangeAfterUpdateHighLow() -> NSDecimalNumber {
        ready = false
        updateHighLow()
        ready = true
        return percentChange
    }

    /// Determines if the percent change has increased and we need to redraw/
    public func recompute(_ maxPercentChange: NSDecimalNumber, forceRecompute: Bool) {
        if forceRecompute {
            calculateMovingAverages()
        }

        let pctDifference = maxPercentChange.subtracting(chartPercentChange).doubleValue
        if forceRecompute || pctDifference > 0.02 {
            if maxPercentChange.compare(NSDecimalNumber.zero) == .orderedDescending {
                chartPercentChange = maxPercentChange
            }
            tmp.scaledLow = tmp.maxHigh.dividing(by: chartPercentChange)
            ready = false
            computeChart()
            ready = true
        } else {
            chartPercentChange = maxPercentChange
            tmp.scaledLow = tmp.maxHigh.dividing(by: chartPercentChange)
        }
    }

    /// DataFetcher has an active download that must be allowed to finish or fail before accepting an additional request
    public func fetcherCanceled() async {
        busy = false
        await delegate?.requestFailed(message: "Canceled request")
    }

    /// DataFetcher failed downloading historical data or intraday data
    public func fetcherFailed(_ message: String) async {
        busy = false
        await delegate?.requestFailed(message: message)
    }

    /// DataFetcher calls StockActor with intraday price data
    func fetcherLoadedIntradayBar(_ intradayBar: BarData) async {
        if let apiNewest = fetcher?.date(from: intradayBar) {
            let dateDiff = apiNewest.timeIntervalSince(newest)

            if dateDiff < dayInSeconds { // Update existing intraday bar
                dailyData[0] = intradayBar
            } else {
                dailyData.insert(intradayBar, at: 0)
            }

            tmp.lastPrice = NSDecimalNumber(value: dailyData[0].close)
            newest = apiNewest

            updatePeriodDataByDayWeekOrMonth()
            updateHighLow()
            busy = false
            await delegate?.requestFinished(newPercentChange: percentChange)
        }
    }

    /// Return the number of bars at the newBarUnit scale to check if one stock in a comparison
    /// will limit the date range that can be charted in the comparison
    public func maxPeriodSupported(newBarUnit: CGFloat) -> Int {
        return Int(floor(Double(dailyData.count) / newBarUnit))
    }

    /// Update data if necessary
    public func updatePeriodData(barUnit: CGFloat, xFactor: CGFloat, maxPeriods: Int) {
        if barUnit != self.barUnit {
            self.newestBarShown = Int(floor(CGFloat(self.newestBarShown) * self.barUnit / barUnit))
            self.oldestBarShown = Int(floor(CGFloat(self.oldestBarShown) * self.barUnit / barUnit))
            self.barUnit = barUnit
        }
        self.xFactor = xFactor * barUnit // caller tracks them separately to determine minimize bar width

        self.updatePeriodDataByDayWeekOrMonth()

        if self.oldestBarShown > maxPeriods {
            self.oldestBarShown = maxPeriods
        }
        self.updateHighLow() // must be a separate call to handle shifting
    }

    /// User zoomed in or out so rescale dailyData by the updated barUnit
    private func updatePeriodDataByDayWeekOrMonth() {
        if barUnit == 1.0 {
            periodData = dailyData
        } else if barUnit > 5 { // monthly
            periodData = BarData.groupByMonth(dailyData)
        } else {
            periodData = BarData.groupByWeek(dailyData, calendar: gregorian, startDate: newest)
        }

        updateFundamentalFetcherBarAlignment()
        calculateMovingAverages()
    }

    /// DataFetcher calls StockActor with the array of historical price data
    func fetcherLoadedHistoricalData(_ loadedData: [BarData]) async {
        guard loadedData.count > 0 else { return }
        let newestBar = loadedData[0]
        if let apiNewest = fetcher?.date(from: newestBar),
           let apiOldest = fetcher?.oldestDate {

            if dailyData.isEmpty { // case 1: First request
                newest = apiNewest
                tmp.lastPrice = NSDecimalNumber(value: newestBar.close)
                oldest = apiOldest
                dailyData.append(contentsOf: loadedData)

            } else if newest.compare(apiNewest) == .orderedAscending { // case 2: Newer dates
                newest = apiNewest
                tmp.lastPrice = NSDecimalNumber(value: newestBar.close)
                if loadedData.count > dailyData.count {
                    print("api is newer AND \(loadedData.count) > \(dailyData.count) so replacing dailyData with loadedData")
                    dailyData = loadedData
                } else {
                    print("api is newer, so inserting \(loadedData.count) bars at start of dailyData")
                    for index in 0 ..< loadedData.count {
                        dailyData.insert(loadedData[index], at: index)
                    }
                }
            } else if oldest.compare(apiOldest) == .orderedDescending { // case 3: Older dates
                oldest = apiOldest
                dailyData.append(contentsOf: loadedData)
                print("\(stock.ticker) older dates \(loadedData.count) new barData.count")
            }

            updatePeriodDataByDayWeekOrMonth()
            updateHighLow()

            if fetcher?.shouldFetchIntradayQuote() == true {
                busy = true
                await fetcher?.fetchIntradayQuote()
            } else {
                busy = false
            }
            await self.delegate?.requestFinished(newPercentChange: self.percentChange)
        }
    }

    /// Calculate chartElements from periodData (which may point to dailyData or be a grouped version of it)
    func computeChart() {
        ready = false
        var xRaw: CGFloat = xFactor / 2
        var oldestClose: Double = 0, oldestValidBar: Int = 0

        tmp.clear()

        if oldestBarShown < 1 || periodData.count == 0 {
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
        var barCenter: CGFloat = 0, barHeight: CGFloat = 0
        tmp.yFloor = tmp.yFactor * tmp.maxHigh.doubleValue + sparklineHeight
        var lastMonth = periodData[oldestValidBar].month

        for index in stride(from: oldestValidBar, through: newestBarShown, by: -1) {
            barCenter = ChartElements.pxAlign(xRaw, alignTo: 0.5)

            if periodData[index].month != lastMonth {
                var label = periodData[index].monthName(calendar: gregorian)
                if periodData[index].month == 1 {
                    let shortYearString = String(periodData[index].year % 100)
                    if periodData.count < dailyData.count || xFactor < 4 { // not enough room
                        label = shortYearString
                    } else {
                        label += shortYearString
                    }
                } else if barUnit > 5 { // only year markets
                    label = ""
                } else if barUnit > 1 || xFactor < 2 { // shorten months
                    label = String(label.prefix(1))
                }

                if !label.isEmpty { // show month or year line
                    tmp.monthLabels.append(label)
                    tmp.monthLines.append(contentsOf: [CGPoint(x: barCenter - 2, y: sparklineHeight),
                                                       CGPoint(x: barCenter - 2, y: volumeBase)])
                }
            }
            lastMonth = periodData[index].month

            if stock.chartType == .ohlc || stock.chartType == .hlc {
                if oldestClose > periodData[index].close { // green bar
                    if stock.chartType == .ohlc { // include open
                        tmp.redPoints.append(contentsOf: [CGPoint(x: barCenter - xFactor/2, y: tmp.yFloor - tmp.yFactor * periodData[index].open),
                                                          CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].open)])
                    }
                    tmp.redPoints.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                      CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low),
                                                      CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].close),
                                                      CGPoint(x: barCenter + xFactor/2, y: tmp.yFloor - tmp.yFactor * periodData[index].close)])
                } else { // red bar
                    if stock.chartType == .ohlc { // include open
                        tmp.points.append(contentsOf: [CGPoint(x: barCenter - xFactor/2, y: tmp.yFloor - tmp.yFactor * periodData[index].open),
                                                       CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].open)])
                    }

                    tmp.points.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                   CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low),
                                                   CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].close),
                                                   CGPoint(x: barCenter + xFactor/2, y: tmp.yFloor - tmp.yFactor * periodData[index].close)])
                }
            } else if stock.chartType == .candle {
                barHeight = tmp.yFactor * (periodData[index].open - periodData[index].close)
                if abs(barHeight) < 1 {
                    barHeight = barHeight > 0 ? 1 : -1  // min 1 px height either up or down
                }

                if periodData[index].open >= periodData[index].close { // filled bar
                    if oldestClose < periodData[index].close { // filled green bar
                        let rect = CGRect(x: barCenter - xFactor * 0.4,
                                          y: tmp.yFloor - tmp.yFactor * periodData[index].open,
                                          width: 0.8 * xFactor, height: barHeight)
                        tmp.filledGreenBars.append(rect)

                        tmp.points.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                       CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low)])
                    } else {
                        tmp.redPoints.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                          CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low)])

                        tmp.redBars.append(CGRect(x: barCenter - xFactor * 0.4,
                                                  y: tmp.yFloor - tmp.yFactor * periodData[index].open,
                                                  width: 0.8 * xFactor, height: barHeight))
                    }
                } else {
                    if oldestClose > periodData[index].close { // red hollow bar
                        tmp.hollowRedBars.append(CGRect(x: barCenter - xFactor * 0.4,
                                                        y: tmp.yFloor - tmp.yFactor * periodData[index].open,
                                                        width: 0.8 * xFactor, height: barHeight))

                        tmp.redPoints.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                          CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].close),
                                                          CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].open),
                                                          CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low)])
                    } else {
                        tmp.greenBars.append(CGRect(x: barCenter - xFactor * 0.4,
                                                    y: tmp.yFloor - tmp.yFactor * periodData[index].open,
                                                    width: 0.8 * xFactor, height: barHeight))

                        tmp.points.append(contentsOf: [CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].high),
                                                       CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].close),
                                                       CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].open),
                                                       CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].low)])
                    }
                }
            } else if stock.chartType == .close {
                tmp.points.append(CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].close))
            }
            if sma50 && periodData[index].movingAvg1 > 0 {
                tmp.movingAvg1.append(CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].movingAvg1))
            }
            if sma200 && periodData[index].movingAvg2 > 0 {
                tmp.movingAvg2.append(CGPoint(x: barCenter, y: tmp.yFloor - tmp.yFactor * periodData[index].movingAvg2))
            }
            if bb20 && periodData[index].mbb > 0 {
                let yMiddle = tmp.yFloor - tmp.yFactor * periodData[index].mbb
                let yStdDev = tmp.yFactor * 2 * periodData[index].stdev
                tmp.upperBollingerBand.append(CGPoint(x: barCenter, y: yMiddle + yStdDev))
                tmp.middleBollingerBand.append(CGPoint(x: barCenter, y: yMiddle))
                tmp.lowerBollingerBand.append(CGPoint(x: barCenter, y: yMiddle - yStdDev))
            }
            if periodData[index].volume > 0 {
                let rect = CGRect(x: barCenter - xFactor/2,
                                  y: volumeBase,
                                  width: xFactor, height: -1 * periodData[index].volume/volumeFactor)
                if oldestClose > periodData[index].close {
                    tmp.redVolume.append(rect)
                } else {
                    tmp.blackVolume.append(rect)
                }
            }
            oldestClose = periodData[index].close
            xRaw += xFactor            // keep track of the unaligned value or the chart will end too soon
        }
    }

    /// Computes fundamental bar pixel alignment after computeChart sets oldestValidBar and xRaw
    func computeFundamentalBarPixelAlignments(from oldestValidBar: Int, xRaw: CGFloat) {
        if tmp.fundamentalAlignments.isEmpty == false {

            var oldestReport = tmp.fundamentalAlignments.count - 1
            var newestReport = 0
            var lastBarAlignment = 0
            for index in 0...oldestReport {
                lastBarAlignment = tmp.barAlignmentFor(report: index)
                if newestReport > 0 && lastBarAlignment == -1 {
                    print("ran out of trading data after report \(newestReport)")
                } else if lastBarAlignment > 0 && lastBarAlignment <= newestBarShown {
                    newestReport = index
                }
                if lastBarAlignment > oldestValidBar || lastBarAlignment == -1 {
                    oldestReport = index       // first report just out of view
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

            var index = newestReport
            tmp.newestReportInView = newestReport

            for index in 0 ..< tmp.fundamentalAlignments.count {
                tmp.fundamentalAlignments[index].x = CGFloat(offscreen)
            }
            var barAlignment = offscreen
            lastBarAlignment = offscreen

            repeat {
                lastBarAlignment = barAlignment
                barAlignment = tmp.barAlignmentFor(report: index)
                if barAlignment < 0 {
                    break
                }
                let xPosition = Double(oldestValidBar - barAlignment + 1) * xFactor + xRaw
                tmp.fundamentalAlignments[index].x = xPosition
                index += 1
            } while index <= oldestReport

            tmp.oldestReportInView = index
        }
    }

    /// Create a copy of the values mutated on a background thread by computeChart for use by ChartRenderer on the mainThread
    func copyChartElements() -> ChartElements {
        // swiftlint:disable:next force_cast
        return tmp.copy() as! ChartElements // copy() returns an Any
    }
}
