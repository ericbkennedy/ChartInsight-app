//
//  ScrollChartView.swift
//  ChartInsight
//
//  View that requests rendered stock charts from ChartRenderer
//  in an offscreen CGContext by providing ChartElements computed by StockActor.

//  Created by Eric Kennedy on 6/28/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

let padding: CGFloat = 5

final class ScrollChartView: UIView, StockActorDelegate {
    public var barUnit: CGFloat
    public var pxWidth: CGFloat // chart area excluding axis and horizontal padding
    public var svWidth: CGFloat
    public var xFactor: CGFloat
    private(set) var comparison: Comparison // use await updateComparison(comparison:) to change
    public var progressIndicator: ProgressIndicator? // reference to WatchlistVC property

    private var maxWidth: CGFloat
    private var pxHeight: CGFloat
    private var scaleShift: CGFloat
    private var scaledWidth: CGFloat
    private var sparklineHeight: CGFloat
    private var svHeight: CGFloat
    private var layerRef: CGLayer?
    private var chartRenderer: ChartRenderer?

    private var stockActorList: [StockActor]
    private var chartPercentChange: NSDecimalNumber
    private var sparklineKeys: [String]
    private var gregorian: Calendar
    private var lastNetworkErrorShown: Date

    override init(frame: CGRect) {
        scaleShift = 0
        xFactor = 7.5
        barUnit = 1.0 // daily
        pxWidth = frame.width
        svWidth = frame.width

        (maxWidth, pxHeight, scaleShift, scaledWidth, sparklineHeight, svHeight) = (0, 0, 0, 0, 0, 0)

        comparison = Comparison()
        stockActorList = []
        gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = .autoupdatingCurrent // required for monthName from .shortNameSymbols

        chartPercentChange = NSDecimalNumber.one
        sparklineKeys = []
        lastNetworkErrorShown = Date(timeIntervalSinceNow: -120) // ensure first error shows
        super.init(frame: frame)
    }

    required convenience init?(coder: NSCoder) {
        self.init(frame: CGRect.zero) // Required by UIKit but Storyboard isn't used
    }

    /// Adjusts _svWidth chart area to allow one right axis per stock
    public func updateDimensions(axisCount: Int = 1) {
        svHeight = bounds.size.height
        maxWidth = bounds.size.width
        scaledWidth = maxWidth
        let horizontalPadding = padding + layer.position.x + 30 * CGFloat(axisCount)
        svWidth = maxWidth - horizontalPadding
        pxWidth = layer.contentsScale * svWidth
        pxHeight = layer.contentsScale * svHeight
    }

    private func maxBarOffset() -> Int {
        return Int(floor((pxWidth)/(xFactor * barUnit)))
    }

    private func createLayerContext() {
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, layer.contentsScale)
        if let currentContext = UIGraphicsGetCurrentContext() {
            layerRef = CGLayer(currentContext,
                               size: CGSize(width: layer.contentsScale * maxWidth, height: pxHeight), auxiliaryInfo: nil)
            UIGraphicsEndImageContext()
            if let layerRef = layerRef {
                chartRenderer = ChartRenderer(layerRef: layerRef, contentsScale: layer.contentsScale,
                                              xFactor: xFactor, barUnit: barUnit, pxWidth: pxWidth)
            }
        }
    }

    /// Clear prior render before resizing the chart to avoid odd animation
    public func clearChart() {
        progressIndicator?.reset()
        if let layerRef = layerRef {
            layerRef.context?.clear(CGRect(x: 0, y: 0,
                                           width: layerRef.size.width,
                                           height: layerRef.size.height))
        }
        setNeedsDisplay()
    }

    /// Remove stock from current comparison and return updated list of all comparisons
    public func removeFromComparison(stock: Stock) async -> [Comparison] {
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
    public func updateComparison(stock: Stock) async -> [Comparison] {
        for index in 0 ..< comparison.stockList.count where comparison.stockList[index].comparisonStockId == stock.comparisonStockId {
            comparison.stockList[index] = stock
        }

        for stockActor in stockActorList where stockActor.comparisonStockId == stock.comparisonStockId {
            await stockActor.update(updatedStock: stock)
        }

        let (updatedList, _) = await comparison.saveToDb()
        return updatedList
    }

    /// Add stock to existing comparison and saveToDB. Then set comparisonStockId = insertedComparisonStockId
    public func addToComparison(stock: Stock) async -> [Comparison] {
        var (_, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: xFactor)
        comparison.stockList.append(stock)
        // Adding a stock will add another y Axis and thus reduce maxBarOffset
        updateDimensions(axisCount: comparison.stockList.count)
        if currentOldestShown > maxBarOffset() {
            currentOldestShown = maxBarOffset()
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
    public func updateComparison(newComparison: Comparison) async {
        // updateDimensions to relect new axis count since it determines oldestBarShown
        updateDimensions(axisCount: newComparison.stockList.count) // adjusts chart area to allow one right axis per stock

        if newComparison.id != comparison.id {
            // Changes to existing comparisons are handled by removeFromComparison(stock:) and addToComparison(stock:)
            // Changing comparisons requires invalidating prior stockActor network sessions
            for stockActor in stockActorList {
                await stockActor.invalidateAndCancel() // cancel all requests
            }
            stockActorList.removeAll()
            chartPercentChange = NSDecimalNumber.one // will be increased to percentChange for newComparison.stockList
            for stock in newComparison.stockList {
                let stockActor = StockActor(stock: stock, gregorian: gregorian, delegate: self, oldestBarShown: maxBarOffset(),
                                            barUnit: barUnit, xFactor: xFactor)
                stockActorList.append(stockActor)
            }
        }

        comparison = newComparison
        sparklineKeys = comparison.sparklineKeys()
        sparklineHeight = CGFloat(100 * comparison.sparklineKeys().count)

        for stockActor in stockActorList {
            await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: UIScreen.main.scale)
            await stockActor.fetchPriceAndFundamentals()
        }
    }

    /// Redraw charts without loading any data if a stock color, chart type or technical changes
    public func redrawCharts() async {
        sparklineKeys = comparison.sparklineKeys()
        sparklineHeight = CGFloat(100 * comparison.sparklineKeys().count)
        for stockActor in stockActorList {
            await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: UIScreen.main.scale)
            await stockActor.recompute(chartPercentChange, forceRecompute: true)
        }
        await renderCharts()
    }

    /// Use ChartRenderer to render the charts in an offscreen CGContext and return a list of the chartText to render via UIGraphicsPushContext
    /// Apple deprecated the CoreGraphics function for rendering text with a specified CGContext so it is necessary
    /// to use UIGraphicsPushContext(context) to render text in the offscreen layerRef.context
    private func renderCharts() async {
        if var renderer = chartRenderer, let context = layerRef?.context {
            renderer.barUnit = barUnit
            renderer.xFactor = xFactor
            renderer.pxWidth = pxWidth

            var stockChartElements = [ChartElements]()
            for stockActor in stockActorList {
                stockChartElements.append(await stockActor.copyChartElements())
            }

            let chartText = renderer.renderCharts(comparison: comparison, stockChartElements: stockChartElements)

            UIGraphicsPushContext(context) // required for textData.text.draw(at: withAttributes:)
            for textData in chartText {
                let textAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: textData.size),
                                      NSAttributedString.Key.foregroundColor: textData.color]
                textData.string.draw(at: textData.position, withAttributes: textAttributes)
            }
            UIGraphicsPopContext() // remove context used to render text
            setNeedsDisplay()
        }
    }

    /// Draw the offscreen layerContext into the context for this view
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(UIColor.systemBackground.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: layer.contentsScale * maxWidth, height: pxHeight + 5))
        if let layerRef = layerRef {
             ctx.draw(layerRef, in: CGRect(x: 5 + scaleShift, y: 5, width: scaledWidth, height: svHeight))
        }

        if layer.position.x > 0 { // Add dividing line from tableView on the left
            ctx.setStrokeColor(UIColor.lightGray.cgColor)
            ctx.setLineWidth(1.0)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0.5, y: 0.5))
            ctx.addLine(to: CGPoint(x: 0.5, y: svHeight))
            ctx.strokePath()
        }
    }

    /// Enlarged screenshot of chart under user's finger with a bar highlighted if coordinates match
    public func magnifyBar(xPress: CGFloat, yPress: CGFloat) async -> UIImage? {
        if var renderer = chartRenderer {
            renderer.barUnit = barUnit
            renderer.xFactor = xFactor
            renderer.pxWidth = pxWidth - layer.position.x

            let centerX = xPress * layer.contentsScale
            let centerY = yPress * layer.contentsScale
            let barOffset = Int(round(centerX / (xFactor * barUnit)))

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
                let monthName = barData.monthName(calendar: gregorian)
                return renderer.magnifyBar(x: xPress, y: yPress, bar: barData, monthName: monthName)
            }
        }
        return nil
    }

    /// Horizontally scale chart image during pinch/zoom gesture and calculate change in bars shown for scaleChart call
    public func scaleChartImage(_ newScale: CGFloat, withCenter touchMidpoint: CGFloat) {
        var scaleFactor = xFactor * newScale
        var newScale = newScale

        if scaleFactor <= 0.25 {
            scaleFactor = 0.25
            newScale = 0.25 / xFactor
        } else if scaleFactor > 50 {
            scaleFactor = 50
            newScale = 50 / xFactor
        }

        if scaleFactor == xFactor {
            return
        }

        scaleShift = touchMidpoint * (1 - newScale)
        scaledWidth = maxWidth * newScale

        setNeedsDisplay()
    }

    /// Check if a stockActor has less price data available and update that actor's oldestBarShown to fit the periodLimit
    /// Returns a tuple (periodLimit, limitOldestBarShown)
    public func limitComparisonPeriod(barUnit: CGFloat, xFactor: CGFloat) async -> (Int, Int) {
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

    /// Complete pinch/zoom transformation by rerendering the chart with the newScale
    /// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
    public func scaleChart(_ newScale: CGFloat) {

        if let layerRef = layerRef {
            // clearing the layer context before renderCharts provides a better animation
            layerRef.context?.clear(CGRect(x: 0, y: 0,
                                           width: layerRef.size.width,
                                           height: layerRef.size.height))
        }
        scaledWidth = maxWidth // reset buffer output width after temporary transformation

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

        var shiftBars = Int(floor(Double(layer.contentsScale * scaleShift) / (barUnit * newXfactor)))
        scaleShift = 0.0

        Task {
            // Check if a stock has less price data available and limit all stocks to that shorter date range
            let (periodLimit, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: newXfactor)

            if newXfactor == xFactor {
                return // prevent strange pan when zoom hits max or min
            } else if currentOldestShown + shiftBars > periodLimit { // already at periodLimit
                shiftBars = 0
            }

            xFactor = newXfactor
            chartPercentChange = NSDecimalNumber.one

            for stockActor in stockActorList {
                let percentChange = await stockActor.shiftRedraw(shiftBars, screenBarWidth: maxBarOffset())
                if percentChange.compare(chartPercentChange) == .orderedDescending {
                    chartPercentChange = percentChange
                }
            }

            for stockActor in stockActorList {
                await stockActor.recompute(chartPercentChange, forceRecompute: false)
            }
            await renderCharts()
        }
    }

    /// Determine range of chart
    public func updateMaxPercentChange(barsShifted: Int) {

        var percentChange = NSDecimalNumber.one
        Task {
            let (periodLimit, currentOldestShown) = await limitComparisonPeriod(barUnit: barUnit, xFactor: xFactor)

            if barsShifted >= 0 && currentOldestShown + barsShifted > periodLimit { // already at max
                await renderCharts()
                return
            }
            chartPercentChange = NSDecimalNumber.one // reduce to minimum chart scale to find new max percentChange
            for stockActor in stockActorList {
                percentChange = await stockActor.shiftRedraw(barsShifted, screenBarWidth: maxBarOffset())
                if percentChange.compare(chartPercentChange) == .orderedDescending {
                    chartPercentChange = percentChange
                }
            }
            for stockActor in stockActorList {
                await stockActor.recompute(chartPercentChange, forceRecompute: false)
            }
            await renderCharts()
        }
    }

    /// Create rendering context to match scrollChartViews.bounds. Called on initial load and after rotation
    public func resize() {
        updateDimensions()
        createLayerContext()
        guard stockActorList.isEmpty == false else { return }

        chartPercentChange = NSDecimalNumber.one

        Task {
            for stockActor in stockActorList {
                await stockActor.setPxHeight(pxHeight, sparklineHeight: sparklineHeight, scale: UIScreen.main.scale)

                await stockActor.setNewestBarShown(stockActor.oldestBarShown - maxBarOffset())
                let stockPercentChange = await stockActor.percentChangeAfterUpdateHighLow()

                if stockPercentChange.compare(chartPercentChange) == .orderedDescending {
                    chartPercentChange = stockPercentChange
                }
            }
            // now that the chartPercentChange has been calculated, recompute each stock chart using it
            for stockActor in stockActorList {
                await stockActor.recompute(chartPercentChange, forceRecompute: false)
            }
            await renderCharts()
        }
    }

    @MainActor public func showProgressIndicator() {
        progressIndicator?.startAnimating()
    }

    @MainActor public func stopProgressIndicator() {
        progressIndicator?.stopAnimating()
    }

    @MainActor public func requestFailed(message: String) {
        progressIndicator?.stopAnimating()
    }

    @MainActor public func requestFinished(newPercentChange: NSDecimalNumber) {
        Task {
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
                await renderCharts()
                progressIndicator?.stopAnimating()
            }
        }
    }

}
