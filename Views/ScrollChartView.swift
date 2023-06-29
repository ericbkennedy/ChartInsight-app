//
//  ScrollChartView.swift
//  ChartInsight
//
//  View that requests rendered stock charts from ChartRenderer
//  in an offscreen CGContext by providing ChartElements computed by StockData.

//  Created by Eric Kennedy on 6/28/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

let padding: CGFloat = 5

class ScrollChartView: UIView, StockDataDelegate {
    var barUnit: CGFloat
    var pxWidth: CGFloat // chart area excluding axis and horizontal padding
    var svWidth: CGFloat
    var xFactor: CGFloat
    var comparison: Comparison
    var progressIndicator: ProgressIndicator? // reference to WatchlistVC property

    private var pxHPadding: CGFloat
    private var maxWidth: CGFloat
    private var pxHeight: CGFloat
    private var scaleShift: CGFloat
    private var scaledWidth: CGFloat
    private var sparklineHeight: CGFloat
    private var svHeight: CGFloat
    private var layerRef: CGLayer?
    private var chartRenderer: ChartRenderer?
    
    private var stockDataList: [StockData]
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
        pxHPadding = padding
        
        (maxWidth, pxHeight, scaleShift, scaledWidth, sparklineHeight, svHeight) = (0, 0, 0, 0, 0, 0)
        
        comparison = Comparison()
        stockDataList = []
        gregorian = Calendar(identifier: .gregorian)

        chartPercentChange = NSDecimalNumber.zero
        
        sparklineKeys = []
        lastNetworkErrorShown = Date(timeIntervalSinceNow: -120) // ensure first error shows
        super.init(frame: frame)
    }
    
    required convenience init?(coder: NSCoder) {
        self.init(frame: CGRect.zero) // Required by UIKit but Storyboard isn't used
    }
    
    /// Adjusts _svWidth chart area to allow one right axis per stock
    func updateDimensions() {
        svHeight = bounds.size.height
        maxWidth = bounds.size.width
        scaledWidth = maxWidth
        let horizontalPadding = padding + layer.position.x + 30 * CGFloat(comparison.stockList.count)
        svWidth = maxWidth - horizontalPadding
        pxWidth = layer.contentsScale * svWidth
        pxHPadding = layer.contentsScale * pxHPadding
        pxHeight = layer.contentsScale * svHeight
    }

    func maxBarOffset() -> Int {
        return Int(floor((pxWidth)/(xFactor * barUnit)));
    }
    
    func createLayerContext() {
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, layer.contentsScale)
        if let currentContext = UIGraphicsGetCurrentContext() {
            layerRef = CGLayer(currentContext,
                               size: CGSize(width: layer.contentsScale * maxWidth, height: pxHeight), auxiliaryInfo: nil)
            UIGraphicsEndImageContext()
            if let layerRef = layerRef {
                chartRenderer = ChartRenderer(layerRef: layerRef, contentsScale: layer.contentsScale, xFactor: xFactor, barUnit: barUnit, pxWidth: pxWidth)
            }
        }
    }
        
    /// Ensure any pending requests for prior comparison are invalidated and set stockData.delegate = nil
    func clearChart() {
        progressIndicator?.reset()
        if let layerRef = layerRef {
            layerRef.context?.clear(CGRect(x: 0, y: 0,
                                           width: layerRef.size.width,
                                           height: layerRef.size.height))
        }
        setNeedsDisplay()
            
        for stockData in stockDataList {
            stockData.invalidateAndCancel() // cancel all requests
            stockData.delegate = nil
        }
        stockDataList.removeAll()
    }
    
    /// Redraw charts without loading any data if a stock color, chart type or technical changes
    func redrawCharts() {
        for stockData in stockDataList {
            stockData.recompute(chartPercentChange, forceRecompute: true)
        }
        renderCharts()
    }
    
    /// Render charts for the stocks in scrollChartView.comparison and fetch data as needed
    func loadChart() {
        chartPercentChange = NSDecimalNumber.zero
        
        updateDimensions() // adjusts chart area to allow one right axis per stock
        
        sparklineKeys = comparison.sparklineKeys()
        
        sparklineHeight = CGFloat(100 * sparklineKeys.count)
        
        for stock in comparison.stockList {
            let stockData = StockData(stock: stock, gregorian: gregorian, delegate: self, oldestBarShown: maxBarOffset())
            stockDataList.append(stockData)

            stockData.barUnit = barUnit
            stockData.xFactor = xFactor * barUnit
            stockData.setPxHeight(pxHeight, sparklineHeight: sparklineHeight)
            stockData.fetchStockData()
        }
    }
    
    /// Use ChartRenderer to render the charts in an offscreen CGContext and return a list of the chartText to render via UIGraphicsPushContext
    /// Apple deprecated the CoreGraphics function for rendering text with a specified CGContext so it is necessary
    /// to use UIGraphicsPushContext(context) to render text in the offscreen layerRef.context
    func renderCharts() {
        if var renderer = chartRenderer, let context = layerRef?.context {
            renderer.barUnit = barUnit
            renderer.xFactor = xFactor
            renderer.pxWidth = pxWidth
            let chartText = renderer.renderCharts(comparison: comparison, stocks: stockDataList)
        
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
    func magnifyBar(x: CGFloat, y:CGFloat) -> UIImage? {
        if var renderer = chartRenderer {
            renderer.barUnit = barUnit
            renderer.xFactor = xFactor
            renderer.pxWidth = pxWidth - layer.position.x
            return renderer.magnifyBar(x: x, y: y, stocks: stockDataList)
        }
        return nil
    }
    
    /// Horizontally scale chart image during pinch/zoom gesture and calculate change in bars shown for scaleChart call
    func scaleChartImage(_ newScale: CGFloat, withCenter touchMidpoint: CGFloat) {
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
    
    /// Check if a stock has less price data available so the caller can limit all stocks to that shorter date range
    /// Returns a tuple (maxSupportedPeriods, oldestBarShown)
    func maxSupportedPeriodsForComparison() -> (Int, Int) {
        var maxSupportedPeriods = 0
        var oldestBarShown = 0
        
        for stockData in stockDataList {
            if oldestBarShown == 0 {
                oldestBarShown = stockData.oldestBarShown
            }
            let periodCountAtNewScale = stockData.maxPeriodSupported(barUnit: barUnit)
            
            if maxSupportedPeriods == 0 || maxSupportedPeriods > periodCountAtNewScale {
                maxSupportedPeriods = periodCountAtNewScale
            }
        }
        return (maxSupportedPeriods, oldestBarShown)
    }
    
    /// Complete pinch/zoom transformation by rerendering the chart with the newScale
    /// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
    func scaleChart(_ newScale: CGFloat) {
        scaledWidth = maxWidth // reset buffer output width after temporary transformation
        
        var newXfactor = xFactor * newScale
        
        // Keep xFactor and barUnit separate and multiply them together for StockData.xFactor
        
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
        
        // Check if a stock has less price data available and limit all stocks to that shorter date rangev
        let (maxSupportedPeriods, currentOldestShown) = maxSupportedPeriodsForComparison()
        
        if newXfactor == xFactor {
            return // prevent strange pan when zoom hits max or min
        } else if currentOldestShown + shiftBars > maxSupportedPeriods { // already at maxSupportedPeriods
            shiftBars = 0
        }
        
        xFactor = newXfactor
        var percentChange = NSDecimalNumber.one
        
        chartPercentChange = NSDecimalNumber.zero
        
        for stockData in stockDataList {
            stockData.xFactor = xFactor * barUnit
            
            if stockData.barUnit != barUnit {
                stockData.newestBarShown = Int(floor(CGFloat(stockData.newestBarShown) * stockData.barUnit / barUnit))
                stockData.oldestBarShown = Int(floor(CGFloat(stockData.oldestBarShown) * stockData.barUnit / barUnit))
                stockData.barUnit = barUnit
                
                stockData.updatePeriodDataByDayWeekOrMonth()
                
                if stockData.oldestBarShown > maxSupportedPeriods {
                    stockData.oldestBarShown = maxSupportedPeriods
                }
                
                stockData.updateHighLow() // must be a separate call to handle shifting
            }
            
            stockData.setPxHeight(pxHeight, sparklineHeight: sparklineHeight)
            
            percentChange = stockData.shiftRedraw(shiftBars, withBars: maxBarOffset())
            if percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = percentChange
            }
        }
        
        for stock in stockDataList {
            stock.recompute(chartPercentChange, forceRecompute: false)
        }
        renderCharts()
    }

    /// Determine range of chart
    func updateMaxPercentChange(withBarsShifted barsShifted: Int) {
        var percentChange = NSDecimalNumber.one

        var outOfBars = true
        let MIN_BARS_SHOWN = 20
        var maxSupportedPeriods = 0, currentOldestShown = 0
        
        for stock in stockDataList {
            if maxSupportedPeriods == 0 || maxSupportedPeriods > stock.periodData.count {
                maxSupportedPeriods = stock.periodData.count
            }
            if currentOldestShown == 0 {
                currentOldestShown = stock.oldestBarShown
            }
            
            if barsShifted == 0 {
                outOfBars = false
            } else if barsShifted > 0 { // users panning to older dates
                if currentOldestShown + barsShifted >= maxSupportedPeriods { // already at max
                    outOfBars = true
                } else if barsShifted < stock.periodData.count - stock.newestBarShown {
                    outOfBars = false
                }
            } else if barsShifted < 0 && stock.oldestBarShown - barsShifted > MIN_BARS_SHOWN {
                outOfBars = false
            }
        }
        if outOfBars {
            return
        }
        for stockData in stockDataList {
            percentChange = stockData.shiftRedraw(barsShifted, withBars: maxBarOffset())
            if percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = percentChange
            }
        }
        for stock in stockDataList {
            stock.recompute(chartPercentChange, forceRecompute: false)
        }
        renderCharts()
    }

    /// Create rendering context to match scrollChartViews.bounds. Called on initial load and after rotation
    func resize() {
        updateDimensions()
        createLayerContext()
        
        chartPercentChange = NSDecimalNumber.zero
        
        for stock in stockDataList {
            stock.setPxHeight(pxHeight, sparklineHeight: sparklineHeight)
            stock.xFactor = xFactor * barUnit
            stock.newestBarShown = stock.oldestBarShown - maxBarOffset()
            stock.updateHighLow()
            
            if stock.percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = stock.percentChange
            }
        }
        
        for stock in stockDataList {
            stock.recompute(chartPercentChange, forceRecompute: false)
        }
        renderCharts()
    }
    
    /// User panned WatchlistViewController by barsShifted. Resize and rerender chart.
    func updateMaxPercentChangeWithBarsShifted(barsShifted: Int) {
        var percentChange = NSDecimalNumber.zero
        
        var outOfBars = true
        let MIN_BARS_SHOWN = 20
        var maxSupportedPeriods = 0
        var currentOldestShown = 0
        
        for stock in stockDataList {
            if maxSupportedPeriods == 0 || maxSupportedPeriods > stock.periodData.count {
                maxSupportedPeriods = stock.periodData.count
            }
            if currentOldestShown == 0 {
                currentOldestShown = stock.oldestBarShown
            }
            
            if barsShifted == 0 {
                outOfBars = false
            } else if barsShifted > 0 {
                // Users panning to older dates
                if currentOldestShown + barsShifted >= maxSupportedPeriods {
                    // Already at max
                    outOfBars = true
                } else if barsShifted < stock.periodData.count - stock.newestBarShown {
                    outOfBars = false
                }
            } else if barsShifted < 0 && stock.oldestBarShown - barsShifted > MIN_BARS_SHOWN {
                outOfBars = false
            }
        }

        if outOfBars {
            return
        }
        
        for stockData in stockDataList {
            percentChange = stockData.shiftRedraw(barsShifted, withBars: maxBarOffset())
            if percentChange.compare(chartPercentChange) == .orderedDescending {
                chartPercentChange = percentChange
            }
        }

        for stock in stockDataList {
            stock.recompute(chartPercentChange, forceRecompute: false)
        }
        
        renderCharts()
    }
    
    func showProgressIndicator() {
        progressIndicator?.startAnimating()
    }
    
    func stopProgressIndicator() {
        progressIndicator?.stopAnimating()
    }
    
    
    func requestFailed(message: String) {
        progressIndicator?.stopAnimating()
    }
    
    func requestFinished(newPercentChange: NSDecimalNumber) {
        let stocksReady = stockDataList.reduce(0) { count, stock in
            return stock.ready ? count + 1 : count
        }
        
        if newPercentChange.compare(chartPercentChange) == .orderedDescending {
            chartPercentChange = newPercentChange
        }
        
        if stocksReady == stockDataList.count {
            // Check if a stock has less price data available and limit all stocks to that shorter date range
            let (maxSupportedPeriods, _) = maxSupportedPeriodsForComparison()
            
            for stockData in stockDataList {
                if stockData.oldestBarShown > maxSupportedPeriods {
                    stockData.oldestBarShown = maxSupportedPeriods
                }
            }
            layer.removeAllAnimations()
            renderCharts()
            progressIndicator?.stopAnimating()
        }
    }

}
