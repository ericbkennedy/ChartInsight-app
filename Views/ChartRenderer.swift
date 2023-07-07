//
//  ChartRenderer.swift
//  ChartInsight
//
//  Renders a comparison chart into the layerRef CGLayer in ScrollChartView
//  using ChartElements from the stocks: [StockData] provided by ScrollChartView.
//
//  Created by Eric Kennedy on 6/29/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//
//  x and y are better variable names than longer names
// swiftlint:disable identifier_name

import Foundation
import UIKit

struct ChartText {
    let string: String
    let position: CGPoint
    let color: UIColor
    let size: CGFloat
}

struct ChartRenderer {
    var layerRef: CGLayer
    var contentsScale: CGFloat
    var xFactor: CGFloat
    var barUnit: CGFloat
    var pxWidth: CGFloat
    let magnifierSize: CGFloat = 100.0 // both width and height
    let numberFormatter = BigNumberFormatter()
    var roundDown = NSDecimalNumberHandler(roundingMode: .down, scale: 0,
                                           raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)

    func renderCharts(comparison: Comparison, stocks: [StockData]) -> [ChartText] {
        var chartText: [ChartText] = [] // will return to caller because Apple deprecated CGContext-based methods
        let context = layerRef.context!
        context.clear(CGRect(x: 0, y: 0, width: layerRef.size.width, height: layerRef.size.height))
        context.setBlendMode(.normal)

        comparison.resetMinMax() // will update min and max in the following loop, then render in renderFundamentals()

        for (index, stockData) in stocks.enumerated().reversed() { // go backwards so stock[0] draws on top
            stockData.copyChartElements()
            let chartElements = stockData.chartElements
            if index == 0 { // Dislay month lines
                chartText.append(contentsOf: renderMonthLines(stockData: stockData))
            }
            context.setLineWidth(1.0 * contentsScale)

            let fundamentalKeys = stockData.fundamentalKeys()
            if !fundamentalKeys.isEmpty {
                for key in fundamentalKeys {
                    var index = stockData.newestReportInView
                    repeat {
                        let reportValue = stockData.fundamentalValue(forReport: index, metric: key)
                        comparison.updateMinMax(for: key, value: reportValue)
                        index += 1
                    } while index <= stockData.oldestReportInView
                }
            }

            context.setStrokeColor(stockData.stock.upColor.cgColor)

            if chartElements.movingAvg1.count > 2 {
                context.setStrokeColor(stockData.stock.colorInverseHalfAlpha.cgColor)
                strokeLineFromPoints(chartElements.movingAvg1, context: context)
            }

            if chartElements.movingAvg2.count > 2 {
                context.setStrokeColor(stockData.stock.upColorHalfAlpha.cgColor)
                strokeLineFromPoints(chartElements.movingAvg2, context: context)
            }

            if chartElements.upperBollingerBand.count > 2 {
                context.setLineDash(phase: 0, lengths: [1.0, 1.5])
                context.setStrokeColor(stockData.stock.upColor.cgColor)
                strokeLineFromPoints(chartElements.upperBollingerBand, context: context)
                strokeLineFromPoints(chartElements.middleBollingerBand, context: context)
                strokeLineFromPoints(chartElements.lowerBollingerBand, context: context)
                context.setLineDash(phase: 0, lengths: []) // reset to solid
            }

            context.setFillColor(stockData.stock.color.cgColor)
            context.setStrokeColor(stockData.stock.color.cgColor)
            strokeLinesFromPoints(chartElements.redPoints, context: context)

            for hollowRedBars in chartElements.hollowRedBars {
                context.stroke(hollowRedBars)
            }
            context.fill(chartElements.redBars)

            if chartElements.greenBars.count > 0 {
                context.setStrokeColor(stockData.stock.upColor.cgColor)
                context.setFillColor(stockData.stock.upColor.cgColor)
                for greenBars in chartElements.greenBars {
                    context.stroke(greenBars)
                }
                context.fill(chartElements.filledGreenBars)
            }

            context.setFillColor(stockData.stock.colorHalfAlpha.cgColor)
            context.fill(chartElements.redVolume)

            context.setFillColor(stockData.stock.upColorHalfAlpha.cgColor)
            context.fill(chartElements.blackVolume)

            context.setStrokeColor(stockData.stock.upColor.cgColor)
            if stockData.stock.chartType == .close {
                context.setLineJoin(.round)
                strokeLineFromPoints(chartElements.points, context: context)
                context.setLineJoin(.miter)
            } else {
                strokeLinesFromPoints(chartElements.points, context: context)
            }

            // Calculate the range of prices for this stock (scaledLow < minLow if other stock was more volatile)
            // and add right-axis labels at rounded increments

            let range = chartElements.maxHigh.subtracting(chartElements.scaledLow)  // scaledLow if the other stock
            let increment = rightAxisIncrements(range: range)
            var avoidLabel: NSDecimalNumber
            var nextLabel: NSDecimalNumber

            avoidLabel = chartElements.lastPrice
            let minSpace: CGFloat = 20 // Skip any label within this distance of the avoidLabel value
            let x = pxWidth + (CGFloat(index) + 0.15) * 30 * contentsScale

            if minSpace < abs(chartElements.yFactor * chartElements.maxHigh.subtracting(chartElements.lastPrice).doubleValue) {
                // lastPrice is lower than maxHigh
                chartText.append(writeLabel(chartElements.maxHigh, for: stockData, atX: x, showBox: false))
                avoidLabel = chartElements.maxHigh
            }

            nextLabel = chartElements.maxHigh.dividing(by: increment, withBehavior: roundDown).multiplying(by: increment)

            if chartElements.maxHigh.compare(chartElements.lastPrice) == .orderedDescending {
                chartText.append(writeLabel(chartElements.lastPrice, for: stockData, atX: x, showBox: true))

                if minSpace > abs(chartElements.yFactor * chartElements.lastPrice.subtracting(nextLabel).doubleValue) {
                    nextLabel = nextLabel.subtracting(increment) // go to next label
                }
            }

            while nextLabel.compare(chartElements.minLow) == .orderedDescending {
                if minSpace < abs(chartElements.yFactor * avoidLabel.subtracting(nextLabel).doubleValue) {
                    chartText.append(writeLabel(nextLabel, for: stockData, atX: x, showBox: false))
                }
                nextLabel = nextLabel.subtracting(increment)
                if minSpace > abs(chartElements.yFactor * chartElements.lastPrice.subtracting(nextLabel).doubleValue) {
                    avoidLabel = chartElements.lastPrice
                } else {
                    avoidLabel = chartElements.minLow
                }
            }

            // If last price is near the minLow, skip minLow
            if minSpace < abs(chartElements.yFactor * chartElements.minLow.subtracting(chartElements.lastPrice).doubleValue) {
                chartText.append(writeLabel(chartElements.minLow, for: stockData, atX: x, showBox: false))
            }
        }
        chartText.append(contentsOf: renderFundamentals(comparison: comparison, stocks: stocks))
        return chartText // so it can be rendered using NSStringDrawing after UIGraphicsPushContext(context)
    }

    private func renderMonthLines(stockData: StockData) -> [ChartText] {
        var chartText: [ChartText] = []
        if let context = layerRef.context {
            for monthIndex in stride(from: 0, to: stockData.chartElements.monthLines.count, by: 2) {
                let top = stockData.chartElements.monthLines[monthIndex]
                let bottom = stockData.chartElements.monthLines[monthIndex + 1]
                context.beginPath()
                context.move(to: top)
                context.addLine(to: bottom)
                context.setStrokeColor(UIColor(white: 0.2, alpha: 0.5).cgColor)
                context.setLineWidth(1.0) // in pixels not points
                context.strokePath()

                let monthLabelIndex = Int(floorf(Float(monthIndex / 2)))
                if monthLabelIndex < stockData.chartElements.monthLabels.count {
                    let label = stockData.chartElements.monthLabels[monthLabelIndex]
                    let offset = 10 * contentsScale
                    chartText.append(string(label, at: CGPoint(x: bottom.x, y: bottom.y + offset), with: stockData.stock.upColor))
                }
            }
        }
        return chartText
    }

    /// Calculate how far apart labels should be on the right axis
    private func rightAxisIncrements(range: NSDecimalNumber) -> NSDecimalNumber {
        var increment = NSDecimalNumber.one, two = NSDecimalNumber(value: 2)

        if range.doubleValue > 1000 {
            increment = NSDecimalNumber(value: 10000)
            while range.dividing(by: increment, withBehavior: roundDown).doubleValue < 4.0 {
                // too many labels
                increment = increment.dividing(by: two)
            }
        } else if range.doubleValue > 20 {
            increment = NSDecimalNumber(value: 5)
            while range.dividing(by: increment, withBehavior: roundDown).doubleValue > 10.0 {
                // too many labels
                increment = increment.multiplying(by: two)
            }
        } else if range.doubleValue > 10 {
            increment = NSDecimalNumber(value: 2)
        } else if range.doubleValue > 5 {
            increment = NSDecimalNumber(value: 1)
        } else if range.doubleValue > 2.5 {
            increment = NSDecimalNumber(value: 0.5)
        } else if range.doubleValue > 1 {
            increment = NSDecimalNumber(value: 0.25)
        } else if range.doubleValue > 0.5 {
            increment = NSDecimalNumber(value: 0.1)
        } else {
            increment = NSDecimalNumber(value: 0.05)
        }
        return increment
    }

    /// Render fundamental metrics above the stock price chart in layerRef.context
    private func renderFundamentals(comparison: Comparison, stocks: [StockData]) -> [ChartText] {
        let context = layerRef.context!
        var chartText: [ChartText] = []
        let sparkHeight = NSDecimalNumber(value: 90)
        var qWidth = xFactor * 60 // use xFactor to avoid having to divide by barUnit
        var yNegativeAdjustment = 0.0, y = sparkHeight.doubleValue, yLabel = 20.0

        for key in comparison.sparklineKeys() { // go through keys in order in case one stock has the key turned off
            let range = comparison.range(for: key)
            if range.isEqual(to: NSDecimalNumber.notANumber) || range.isEqual(to: NSDecimalNumber.zero) {
                continue // skip it
            }

            let sparklineYFactor = sparkHeight.dividing(by: range)

            if let minForKey = comparison.min(for: key),
               let maxForKey = comparison.max(for: key) {
                if minForKey.compare(NSDecimalNumber.zero) == .orderedAscending {
                    if maxForKey.compare(NSDecimalNumber.zero) == .orderedAscending {
                        yNegativeAdjustment = -1 * sparkHeight.doubleValue
                    } else {
                        yNegativeAdjustment = minForKey.multiplying(by: sparklineYFactor).doubleValue
                    }
                    y += yNegativeAdjustment
                }
            }

            let x = pxWidth - magnifierSize
            chartText.append(string(Metrics.shared.title(for: key), at: CGPoint(x: x, y: yLabel), with: UIColor.systemGray))

            let minBarHeightForLabel: CGFloat = 25 // if fundamental bar is shorter then this, put metric value above the bar

            for stockData in stocks where stockData.stock.fundamentalList.contains(key) {

                let fundamentalAlignments = stockData.chartElements.fundamentalAlignments
                if stockData.oldestBarShown > 0 && fundamentalAlignments.count > 0 {
                    context.setFillColor(stockData.stock.upColorHalfAlpha.cgColor)

                    let r = stockData.newestReportInView

                    for r in r..<stockData.oldestReportInView where fundamentalAlignments[r] > 0 {

                        let reportValue = stockData.fundamentalValue(forReport: r, metric: key)

                        if reportValue.isEqual(to: NSDecimalNumber.notANumber) {
                            continue
                        }
                        if r + 1 < fundamentalAlignments.count && fundamentalAlignments[r + 1] > 0 {
                            // can calculate bar width to older report
                            qWidth = fundamentalAlignments[r] - fundamentalAlignments[r + 1] - 3
                        } else if r > 1 { // no older reports so use default fundamental bar width
                            qWidth = fundamentalAlignments[r - 1] - fundamentalAlignments[r] - 3
                        }

                        let barHeight = reportValue.multiplying(by: sparklineYFactor).doubleValue

                        var metricColor = UIColor.black
                        var labelPosition = CGPoint.zero

                        if reportValue.compare(NSDecimalNumber.zero) == .orderedAscending { // negative value
                            labelPosition.y = y + Double(minBarHeightForLabel) // will be just before zero line
                            metricColor = UIColor.lightGray // use light gray text on red bar for clarity
                            context.setFillColor(UIColor.red.withAlphaComponent(0.8).cgColor)
                        } else {
                            labelPosition.y = y + minBarHeightForLabel - CGFloat(barHeight)
                            if barHeight < Double(minBarHeightForLabel) { // short bars are due to big range in values
                                labelPosition.y = y // text just above zero line (looks best when other values are negative)
                            }
                            metricColor = stockData.stock.upColorHalfAlpha
                            context.setFillColor(metricColor.cgColor)
                        }

                        context.fill(CGRect(x: fundamentalAlignments[r], y: y, width: -qWidth, height: -barHeight))

                        if barUnit < 5.0 && stocks.count == 1, // only show value of fundamental on bar for single stock charts
                           let label = numberFormatter.string(number: reportValue, maxDigits: Float(2 * xFactor)) {
                            labelPosition.x = fundamentalAlignments[r] - 11.5 * CGFloat(label.count) - 10
                            chartText.append(string(label, at: CGPoint(x: labelPosition.x, y: labelPosition.y), with: metricColor))
                        }
                    }
                }
            }
            y += 10 + sparkHeight.doubleValue - yNegativeAdjustment
            yLabel += 10 + sparkHeight.doubleValue
            yNegativeAdjustment = 0
        }
        return chartText
    }

    /// Enlarged screenshot of chart under user's finger with a bar highlighted if coordinates match
    func magnifyBar(x: CGFloat, y: CGFloat, stocks: [StockData]) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: magnifierSize, height: magnifierSize), false, contentsScale)
        guard let lensContext = UIGraphicsGetCurrentContext() else { return nil }

        var backgroundColor = UIColor.white
        var textColor = UIColor.black

        if UserDefaults.standard.bool(forKey: "darkMode") {
            backgroundColor = UIColor.black // reverse colors
            textColor = UIColor.white
        }

        lensContext.setFillColor(backgroundColor.cgColor)
        lensContext.fill(CGRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize))

        let yPressed = y * contentsScale

        let scale = UIScreen.main.scale
        let magnification: CGFloat = 2.0

        let midpoint = magnifierSize / (2 * magnification)

        let x = (x - midpoint) * contentsScale // subtract midpoint to make the touch point the center of the lens, not the top left corner
        let y = (y - 2 * midpoint) * contentsScale

        if scale >= 1 {
            lensContext.scaleBy(x: magnification / scale, y: magnification / scale)
        }
        lensContext.draw(layerRef, at: CGPoint(x: -x, y: -y))
        lensContext.setBlendMode(.normal)

        let centerX = x + midpoint * scale - xFactor * barUnit / 2 // because xRaw starts at xFactor/scale

        for stockData in stocks {
            let barOffset = Int(round(centerX / (xFactor * barUnit)))
            if stockData.oldestBarShown - barOffset >= 0 {
                let pressedBarIndex = stockData.oldestBarShown - barOffset // only overwrite pressedBarIndex if it's valid

                if let (bar, monthName) = stockData.bar(at: pressedBarIndex) {
                    let barHigh = stockData.chartElements.yFloor - stockData.chartElements.yFactor * bar.high
                    let barLow = stockData.chartElements.yFloor - stockData.chartElements.yFactor * bar.low

                    if yPressed < barLow && yPressed > barHigh {
                        lensContext.setFillColor(backgroundColor.withAlphaComponent(0.25).cgColor)
                        lensContext.fill(CGRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize))

                        let strokeColor = bar.upClose ? stockData.stock.upColor : stockData.stock.color

                        lensContext.setStrokeColor(strokeColor.cgColor)
                        lensContext.setLineWidth(UIScreen.main.scale)
                        lensContext.setShadow(offset: CGSize(width: 0.5, height: 0.5), blur: 0.75)
                        numberFormatter.maximumFractionDigits = bar.high > 100 ? 0 : 2

                        var label = monthName
                        if barUnit < 19 {
                            label += "\(bar.day)"
                        } else {
                            label += "'" + String(bar.year).suffix(2)
                        }

                        showString(label, at: CGPoint(x: 16.0 * scale, y: 7.0 * scale), with: textColor, size: 12.0)

                        let scopeFactor = (bar.high > bar.low) ? 31.0 * scale / (bar.high - bar.low) : 0
                        let midPoint = (bar.high + bar.low) / 2.0

                        label = numberFormatter.string(from: NSNumber(value: bar.open)) ?? ""
                        var y = 27.5 * scale + scopeFactor * (midPoint - bar.open)
                        showString(label, at: CGPoint(x: 10.0 * scale, y: y), with: textColor, size: 12.0)

                        y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.0 * scale
                        lensContext.move(to: CGPoint(x: 20.0 * scale, y: y))
                        lensContext.addLine(to: CGPoint(x: 25.0 * scale, y: y))

                        label = numberFormatter.string(from: NSNumber(value: bar.high)) ?? ""
                        y = 27.5 * scale + scopeFactor * (midPoint - bar.high)
                        showString(label, at: CGPoint(x: 22.0 * scale, y: y), with: textColor, size: 12.0)

                        y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.0 * scale
                        lensContext.move(to: CGPoint(x: 25.0 * scale, y: y))

                        label = numberFormatter.string(from: NSNumber(value: bar.low)) ?? ""
                        y = 27.5 * scale + scopeFactor * (midPoint - bar.low)
                        showString(label, at: CGPoint(x: 22.0 * scale, y: y), with: textColor, size: 12.0)

                        y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.0 * scale
                        lensContext.addLine(to: CGPoint(x: 25.0 * scale, y: y))

                        label = numberFormatter.string(from: NSNumber(value: bar.close)) ?? ""
                        y = 27.5 * scale + scopeFactor * (midPoint - bar.close)
                        showString(label, at: CGPoint(x: 33.0 * scale, y: y), with: textColor, size: 12.0)

                        y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.0 * scale
                        lensContext.move(to: CGPoint(x: 25.0 * scale, y: y))
                        lensContext.addLine(to: CGPoint(x: 30.0 * scale, y: y))
                        lensContext.strokePath()
                        break // use the first bar that fits to avoid overlap
                    }
                }
            }
        }
        let screenshot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return screenshot
    }

    func writeLabel(_ price: NSDecimalNumber, for stock: StockData, atX x: CGFloat, showBox: Bool) -> ChartText {
        let l = numberFormatter.string(from: price) ?? ""

        var y = stock.chartElements.yFloor - stock.chartElements.yFactor * price.doubleValue + 20

        let pxPerPoint: CGFloat = 1 / contentsScale
        y = ChartElements.pxAlign(y, alignTo: pxPerPoint)
        let alignedX = ChartElements.pxAlign(x, alignTo: pxPerPoint)

        if showBox {
            let boxWidth = CGFloat(l.count) * 14
            let padding: CGFloat = 4
            let boxHeight: CGFloat = 28

            let boxRect = CGRect(x: alignedX - pxPerPoint, y: y - boxHeight + padding, width: boxWidth, height: boxHeight)

            layerRef.context?.setStrokeColor(stock.stock.upColorHalfAlpha.cgColor)
            layerRef.context?.stroke(boxRect)
        }

        let textPoint = CGPoint(x: alignedX, y: y)
        return string(l, at: textPoint, with: stock.stock.upColor)
    }

    /// Returns ChartText struct with info for string with point, color and size to chartText array for later rendering in pushed graphics context
    func string(_ string: String, at point: CGPoint, with color: UIColor, size: CGFloat = 22) -> ChartText {
        let adjustedPoint = CGPoint(x: point.x, y: point.y - size)
        return ChartText(string: string, position: adjustedPoint, color: color, size: size)
    }

    /// Renders string in current graphics context
    func showString(_ string: String, at point: CGPoint, with color: UIColor, size: CGFloat) {
        let textAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: size),
                              NSAttributedString.Key.foregroundColor: color]
        string.draw(at: CGPoint(x: point.x, y: point.y - size), withAttributes: textAttributes)
    }

    /// Create a continuous path using the points provided and stroke the final path
    func strokeLineFromPoints(_ points: [CGPoint], context: CGContext) {
        guard points.count > 0 else {
            return
        }
        context.beginPath()

        for (index, point) in points.enumerated() {
            if index == 0 {
                context.move(to: point)
            } else {
                context.addLine(to: point)
            }
        }
        context.strokePath()
    }

    /// Create separate lines from each pair of points and stroke each line separately
    func strokeLinesFromPoints(_ points: [CGPoint], context: CGContext) {
        for (index, point) in points.enumerated() {

            if index % 2 == 0 {
                context.beginPath()
                context.move(to: point)
            } else {
                context.addLine(to: point)
                context.strokePath()
            }
        }
    }

}

// swiftlint:enable identifier_name
