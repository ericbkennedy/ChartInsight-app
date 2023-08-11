//
//  ScrollChartViewModel.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

public let axisWidth: Double = 30

final class ScrollChartViewModel: StockActorDelegate {
    public var axisCount: Int
    public var axisPadding: Double { // print(contentsScale, axisCount)
        axisWidth * contentsScale * Double(axisCount)
    }
    public var barUnit: Double // days per bar (1 = daily, 5 = weekly, > 5 = monthly)
    public var xFactor: Double // determines width of each bar
    public var contentsScale: Double
    // iPad rotation and split view resizing will change pxWidth on the MainActor
    // so only MainActor should get and set these to avoid a data race
    @MainActor public var pxWidth: Double
    @MainActor public var pxHeight: Double
    @MainActor public var maxBarOffset: Int {
        Int(floor((pxWidth - axisPadding)/(xFactor * barUnit)))
    }

    // Closures to bind View to ViewModel
    public var didBeginRequest: (@MainActor () -> Void)?
    public var didCancel: (@MainActor () -> Void)?
    public var didError: (@MainActor (String) -> Void)?
    public var didUpdate: (@MainActor ([ChartElements]) -> Void)?

    private(set) var comparison: Comparison // use await updateComparison(comparison:) to change

    private var chartPercentChange: NSDecimalNumber
    private var sparklineKeys: [String]
    private var stockActorList: [StockActor]
    private var gregorian: Calendar
    private var scaledWidth: Double
    private var sparklineHeight: Double

    public init(contentsScale: CGFloat) {
        barUnit = 1.0 // daily
        xFactor = 7.5
        axisCount = 1
        self.contentsScale = contentsScale
        (pxWidth, pxHeight, scaledWidth, sparklineHeight) = (0, 0, 0, 0)

        chartPercentChange = .one
        comparison = Comparison()
        sparklineKeys = []
        stockActorList = []
        gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = .autoupdatingCurrent // required for monthName from .shortNameSymbols
    }

    /// A StockActor started a network request
    public func requestStarted() {
        didBeginRequest?()
    }

    /// A StockActor canceled the latest request because its HistoricalDataService already has a request in progress
    public func requestCanceled() {
        didCancel?()
    }

    /// A StockActor failed to fetch new price or fundamental data
    public func requestFailed(message: String) {
        didError?(message)
    }

    public func requestFinished(newPercentChange: NSDecimalNumber) async {
        var stocksReady = 0
        if stockActorList.count > 1 {
            for stockActor in stockActorList where await stockActor.ready {
                stocksReady += 1
            }
        } else {
            stocksReady = 1 // since the StockActor that called this was ready
        }

        if newPercentChange.compare(chartPercentChange) == .orderedDescending {
            chartPercentChange = newPercentChange
        }

        if stocksReady == stockActorList.count {
            // Check if a stock has less price data available and limit all stocks to that shorter date range
            _ = await limitComparisonPeriod(barUnit: barUnit, xFactor: xFactor)
            didUpdate?(await copyChartElements())
        }
    }

    /// Returns a copy of the chartElements for each StockActor for use by the ChartRenderer
    public func copyChartElements() async -> [ChartElements] {
        var chartElements = [ChartElements]()
        for stockActor in stockActorList {
            chartElements.append(await stockActor.copyChartElements())
        }
        return chartElements
    }

    /// Return barData at index
    public func matchedBarAtIndex(barOffset: Int, centerY: Double) async -> (BarData, String)? {
        var matchedBar: BarData?
        await withTaskGroup(of: BarData?.self) { group in
            for stockActor in stockActorList {
                group.addTask {
                    let pressedBarIndex = await stockActor.oldestBarShown - barOffset
                    if let (bar, yHigh, yLow) = await stockActor.bar(at: pressedBarIndex) {
                        if centerY >= yHigh && centerY <= yLow {
                            return bar // good match (note CoreGraphics has yHigh < yLow)
                        }
                    }
                    return nil
                }
            }
            for await barData in group where barData != nil {
                matchedBar = barData
                break // use first non-nil match because multiple bars are hard to read
            }
        }
        if let barData = matchedBar {
            return (barData, barData.monthName(calendar: gregorian))
        }
        return nil
    }

    /// Redraw charts without loading any data if a stock color, chart type or technical changes
    public func chartOptionsChanged() async {
        sparklineKeys = comparison.sparklineKeys()
        sparklineHeight = Double(100 * comparison.sparklineKeys().count)
        for stockActor in stockActorList {
            await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: UIScreen.main.scale)
            await stockActor.recompute(chartPercentChange, forceRecompute: true)
        }
        await didUpdate?(await copyChartElements())
    }

    /// Check if a stockActor has less price data available and update that actor's oldestBarShown to fit the periodLimit
    /// Returns a tuple (periodLimit, limitOldestBarShown)
    public func limitComparisonPeriod(barUnit: Double, xFactor: Double) async -> (Int, Int) {
        var supportedPeriods = [Int]()
        var oldestBarsShown = [Int]()
        var stockOldestBarShown = [Int: Int]() // key = comparisonStockId, value = oldestBarShown

        for stockActor in stockActorList {
            let (periodCount, oldestShown) = await stockActor.maxPeriodSupported(newBarUnit: barUnit, newXFactor: xFactor)
            supportedPeriods.append(periodCount)
            oldestBarsShown.append(oldestShown)
            stockOldestBarShown[stockActor.comparisonStockId] = oldestShown
        }

        let periodLimit = supportedPeriods.min() ?? 0
        let limitOldestBarShown = oldestBarsShown.min() ?? 0

        var stocksOverLimit = [Int]()

        for (comparisonStockId, oldestShown) in stockOldestBarShown where oldestShown > periodLimit {
            stocksOverLimit.append(comparisonStockId)
        }

        // Reduce oldestBarShown for only stocksOverLimit
        for stockActor in stockActorList where stocksOverLimit.contains(stockActor.comparisonStockId) {
            await stockActor.setOldestBarShown(limitOldestBarShown)
        }
        return (periodLimit, limitOldestBarShown)
    }

    /// Remove stock from current comparison and return updated list of all comparisons
    @MainActor public func removeFromComparison(stock: Stock) async -> [Comparison] {
        if comparison.stockList.count == 1 {
            print("Error: delete the entire comparison instead of calling removeFromComparison")
        }
        for (index, stockActor) in stockActorList.enumerated() where stockActor.comparisonStockId == stock.comparisonStockId {
            await stockActor.invalidateAndCancel()
            _ = stockActorList.remove(at: index)
            break
        }
        let updatedList = await comparison.delete(stock: stock)
        updateMaxPercentChange(barsShifted: 0) // Updates chart scale if deleted stock had largest range
        return updatedList
    }

    /// Update the stockActor for the stock provided so the next render will use the updated chart options
    /// Returns the list of all stock comparisons
    @MainActor public func updateComparison(stock: Stock) async -> [Comparison] {
        for index in 0 ..< comparison.stockList.count where comparison.stockList[index].comparisonStockId == stock.comparisonStockId {
            comparison.stockList[index] = stock
        }

        for stockActor in stockActorList where stockActor.comparisonStockId == stock.comparisonStockId {
            await stockActor.update(updatedStock: stock)
        }

        let (updatedList, _) = await comparison.saveToDb()
        return updatedList
    }

    /// Add stock to comparison (which can be a new empty one) and saveToDB. Then set comparisonStockId = insertedComparisonStockId
    @MainActor public func addToComparison(stock: Stock) async -> [Comparison] {
        var currentOldestShown = maxBarOffset // fill scrollChartView with bars unless a stock has fewer available
        if comparison.stockList.isEmpty == false {
            (_, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: xFactor)
        }
        comparison.stockList.append(stock)

        axisCount = comparison.stockList.count // additional stock will reduce maxBarOffset
        if currentOldestShown > maxBarOffset {
            currentOldestShown = maxBarOffset
        }

        // Reduce oldestBarShown to reflect the space for the additional axis for the new stock
        for stockActor in stockActorList {
            await stockActor.setOldestBarShown(currentOldestShown)
        }

        let (updatedList, insertedComparisonStockId) = await comparison.saveToDb()
        var updatedStock = stock
        updatedStock.comparisonStockId = insertedComparisonStockId
        comparison.stockList[comparison.stockList.count - 1] = updatedStock
        let stockActor = StockActor(stock: updatedStock, gregorian: gregorian, delegate: self, oldestBarShown: currentOldestShown,
                                    barUnit: barUnit, xFactor: xFactor)
        stockActorList.append(stockActor)

        return updatedList
    }

    /// Invalidate and cancel any requests for the last comparison and create stockActors for the new one.
    /// Note addToComparison(stock:) should be used to add a single stock to the current comparison
    /// and removeFromComparison(stock:) should be used to delete a single stock from a multi-stock comparison.
    ///  Returns the updated list of all stock comparisons
    @MainActor public func updateComparison(newComparison: Comparison) async {
        axisCount = newComparison.stockList.count // must be set before creating StockActors

        if newComparison.id != comparison.id {
            // Changes to existing comparisons are handled by removeFromComparison(stock:) and addToComparison(stock:)
            // Changing comparisons requires invalidating prior stockActor network sessions
            for stockActor in stockActorList {
                await stockActor.invalidateAndCancel() // cancel all requests
            }
            stockActorList.removeAll()
            chartPercentChange = NSDecimalNumber.one // will be increased to percentChange for newComparison.stockList
            for stock in newComparison.stockList {
                let stockActor = StockActor(stock: stock, gregorian: gregorian, delegate: self, oldestBarShown: maxBarOffset,
                                            barUnit: barUnit, xFactor: xFactor)
                stockActorList.append(stockActor)
            }
        }

        comparison = newComparison
        sparklineKeys = comparison.sparklineKeys()
        sparklineHeight = Double(100 * comparison.sparklineKeys().count)

        didBeginRequest?() // Notifies View to start the progressIndicator

        for stockActor in stockActorList {
            await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: UIScreen.main.scale)
            await stockActor.fetchPriceAndFundamentals()
        }
    }

    /// Update stockActor list with new size
    @MainActor public func resize(pxWidth: Double, pxHeight: Double) {
        self.pxWidth = pxWidth
        self.pxHeight = pxHeight
        guard stockActorList.isEmpty == false else { return }
        Task {
            for stockActor in stockActorList {
                await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: contentsScale)
                await stockActor.setNewestBarShown(stockActor.oldestBarShown - maxBarOffset)
            }
            updateMaxPercentChange(barsShifted: 0)
        }
    }

    /// Determine range of chart
    @MainActor public func updateMaxPercentChange(barsShifted: Int) {
        Task {
            var percentChange = NSDecimalNumber.one
            let (periodLimit, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: xFactor)

            if barsShifted >= 0 && currentOldestShown + barsShifted > periodLimit { // already at max
                didUpdate?(await copyChartElements())
                return
            }
            var newChartPercentChange = NSDecimalNumber.one // reduce to minimum chart scale to find new max percentChange
            for stockActor in stockActorList {
                percentChange = await stockActor.shiftRedraw(barsShifted, screenBarWidth: maxBarOffset)
                if percentChange.compare(newChartPercentChange) == .orderedDescending {
                    newChartPercentChange = percentChange
                }
            }
            chartPercentChange = newChartPercentChange
            for stockActor in stockActorList {
                await stockActor.recompute(newChartPercentChange, forceRecompute: false)
            }
            didUpdate?(await copyChartElements())
        }
    }

    /// Complete pinch/zoom transformation by rerendering the chart with the newScale
    /// Uses scaleShift set by scaleChartImage(_:withCenter:) so the rendered chart matches the temporary transformation
    @MainActor public func scaleChart(newScale: Double, pxShift: Double) {
        var newXfactor = xFactor * newScale

        // Keep xFactor (width of bars) and barUnit (number of days per bar) separate

        if newXfactor < 1.0 {
            barUnit = 19.0 // switch to monthly

            if newXfactor < 0.25 {
                newXfactor = 0.25 // minimum size for monthly charting
            }
        } else if newXfactor < 3 {
            barUnit = 4.5 // switch to weekly
        } else if barUnit == 19.0 && newXfactor * barUnit > 20.0 {
            barUnit = 4.5 // switch to weekly
        } else if barUnit == 4.5 && newXfactor * barUnit > 10.0 {
            barUnit = 1.0 // switch to daily
        } else if newXfactor > 50 { // too small, so make no change
            newXfactor = 50
        }

        Task { [newXfactor] in
            var shiftBars = Int(floor(pxShift/(barUnit * newXfactor)))
            // Check if a stock has less price data available and limit all stocks to that shorter date range
            let (periodLimit, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: newXfactor)
            if newXfactor == xFactor {
                return // prevent strange pan when zoom hits max or min
            } else if currentOldestShown + shiftBars > periodLimit { // already at periodLimit
                shiftBars = 0
            }
            xFactor = newXfactor
            updateMaxPercentChange(barsShifted: shiftBars)
        }
    }

}
