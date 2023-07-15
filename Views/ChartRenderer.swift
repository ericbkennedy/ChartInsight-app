//
//  ChartRenderer.swift
//  ChartInsight
//
//  Renders a comparison chart into the layerRef CGLayer in ScrollChartView
//  using ChartElements from stockChartElements: [ChartElements] provided by ScrollChartView.
//
//  Created by Eric Kennedy on 6/29/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

struct ChartText {
    let string: String
    let position: CGPoint
    let color: UIColor
    let size: CGFloat
}

struct ChartRenderer {
    public var layerRef: CGLayer
    public var contentsScale: CGFloat
    public var xFactor: CGFloat
    public var barUnit: CGFloat
    public var pxWidth: CGFloat
    private let magnifierSize: CGFloat = 100.0 // both width and height
    private let numberFormatter = BigNumberFormatter()
    private let roundDown = NSDecimalNumberHandler(roundingMode: .down, scale: 0,
                                           raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)

    public func renderCharts(comparison: Comparison, stockChartElements: [ChartElements]) -> [ChartText] {
        var chartText: [ChartText] = [] // will return to caller because Apple deprecated CGContext-based methods
        let context = layerRef.context!
        context.clear(CGRect(x: 0, y: 0, width: layerRef.size.width, height: layerRef.size.height))
        context.setBlendMode(.normal)

        comparison.resetMinMax() // will update min and max in the following loop, then render in renderFundamentals()

        for (index, chartElements) in stockChartElements.enumerated().reversed() { // go backwards so stock[0] draws on top
            if index == 0 { // Dislay month lines
                chartText.append(contentsOf: renderMonthLines(chartElements: chartElements))
            }
            context.setLineWidth(1.0 * contentsScale)

            let fundamentalKeys = chartElements.fundamentalKeys()
            if !fundamentalKeys.isEmpty {
                for key in fundamentalKeys {
                    var index = chartElements.newestReportInView
                    repeat {
                        let reportValue = chartElements.fundamentalValue(forReport: index, metric: key)
                        comparison.updateMinMax(for: key, value: reportValue)
                        index += 1
                    } while index <= chartElements.oldestReportInView
                }
            }

            context.setStrokeColor(chartElements.stock.upColor.cgColor)

            if chartElements.movingAvg1.count > 2 {
                context.setStrokeColor(chartElements.stock.colorInverseHalfAlpha.cgColor)
                strokeLineFromPoints(chartElements.movingAvg1, context: context)
            }

            if chartElements.movingAvg2.count > 2 {
                context.setStrokeColor(chartElements.stock.upColorHalfAlpha.cgColor)
                strokeLineFromPoints(chartElements.movingAvg2, context: context)
            }

            if chartElements.upperBollingerBand.count > 2 {
                context.setLineDash(phase: 0, lengths: [1.0, 1.5])
                context.setStrokeColor(chartElements.stock.upColor.cgColor)
                strokeLineFromPoints(chartElements.upperBollingerBand, context: context)
                strokeLineFromPoints(chartElements.middleBollingerBand, context: context)
                strokeLineFromPoints(chartElements.lowerBollingerBand, context: context)
                context.setLineDash(phase: 0, lengths: []) // reset to solid
            }

            context.setFillColor(chartElements.stock.color.cgColor)
            context.setStrokeColor(chartElements.stock.color.cgColor)
            strokeLinesFromPoints(chartElements.redPoints, context: context)

            for hollowRedBars in chartElements.hollowRedBars {
                context.stroke(hollowRedBars)
            }
            context.fill(chartElements.redBars)

            if chartElements.greenBars.count > 0 {
                context.setStrokeColor(chartElements.stock.upColor.cgColor)
                context.setFillColor(chartElements.stock.upColor.cgColor)
                for greenBars in chartElements.greenBars {
                    context.stroke(greenBars)
                }
                context.fill(chartElements.filledGreenBars)
            }

            context.setFillColor(chartElements.stock.colorHalfAlpha.cgColor)
            context.fill(chartElements.redVolume)

            context.setFillColor(chartElements.stock.upColorHalfAlpha.cgColor)
            context.fill(chartElements.blackVolume)

            context.setStrokeColor(chartElements.stock.upColor.cgColor)
            if chartElements.stock.chartType == .close {
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
                chartText.append(writeLabel(chartElements.maxHigh, for: chartElements, atX: x, showBox: false))
                avoidLabel = chartElements.maxHigh
            }

            nextLabel = chartElements.maxHigh.dividing(by: increment, withBehavior: roundDown).multiplying(by: increment)

            if chartElements.maxHigh.compare(chartElements.lastPrice) == .orderedDescending {
                chartText.append(writeLabel(chartElements.lastPrice, for: chartElements, atX: x, showBox: true))

                if minSpace > abs(chartElements.yFactor * chartElements.lastPrice.subtracting(nextLabel).doubleValue) {
                    nextLabel = nextLabel.subtracting(increment) // go to next label
                }
            }

            while nextLabel.compare(chartElements.minLow) == .orderedDescending {
                if minSpace < abs(chartElements.yFactor * avoidLabel.subtracting(nextLabel).doubleValue) {
                    chartText.append(writeLabel(nextLabel, for: chartElements, atX: x, showBox: false))
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
                chartText.append(writeLabel(chartElements.minLow, for: chartElements, atX: x, showBox: false))
            }
        }
        chartText.append(contentsOf: renderFundamentals(comparison: comparison, stockChartElements: stockChartElements))
        return chartText // so it can be rendered using NSStringDrawing after UIGraphicsPushContext(context)
    }

    private func renderMonthLines(chartElements: ChartElements) -> [ChartText] {
        var chartText: [ChartText] = []
        if let context = layerRef.context {
            for monthIndex in stride(from: 0, to: chartElements.monthLines.count, by: 2) {
                let top = chartElements.monthLines[monthIndex]
                let bottom = chartElements.monthLines[monthIndex + 1]
                context.beginPath()
                context.move(to: top)
                context.addLine(to: bottom)
                context.setStrokeColor(UIColor(white: 0.2, alpha: 0.5).cgColor)
                context.setLineWidth(1.0) // in pixels not points
                context.strokePath()

                let monthLabelIndex = Int(floorf(Float(monthIndex / 2)))
                if monthLabelIndex < chartElements.monthLabels.count {
                    let label = chartElements.monthLabels[monthLabelIndex]
                    let offset = 10 * contentsScale
                    chartText.append(string(label, at: CGPoint(x: bottom.x, y: bottom.y + offset), with: chartElements.stock.upColor))
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
    private func renderFundamentals(comparison: Comparison, stockChartElements: [ChartElements]) -> [ChartText] {
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

            var x = pxWidth
            if stockChartElements.count == 1 { // Only 1 y axis doesn't leave enough room for Metric title so shift left by magniferSize
                x -= magnifierSize
            }
            chartText.append(string(Metrics.shared.title(for: key), at: CGPoint(x: x, y: yLabel), with: UIColor.systemGray))

            let minBarHeightForLabel: CGFloat = 25 // if fundamental bar is shorter then this, put metric value above the bar

            for chartElements in stockChartElements where chartElements.stock.fundamentalList.contains(key) {

                let fundamentalAlignments = chartElements.fundamentalAlignments
                if fundamentalAlignments.count > 0 {
                    context.setFillColor(chartElements.stock.upColorHalfAlpha.cgColor)

                    let r = chartElements.newestReportInView

                    for r in r ..< chartElements.oldestReportInView where fundamentalAlignments[r].bar > 0 {

                        let reportValue = chartElements.fundamentalValue(forReport: r, metric: key)

                        if reportValue.isEqual(to: NSDecimalNumber.notANumber) {
                            continue
                        }
                        if r + 1 < fundamentalAlignments.count && fundamentalAlignments[r + 1].x > 0 {
                            // can calculate bar width to older report
                            qWidth = fundamentalAlignments[r].x - fundamentalAlignments[r + 1].x - 3
                        } else if r > 1 { // no older reports so use default fundamental bar width
                            qWidth = fundamentalAlignments[r - 1].x - fundamentalAlignments[r].x - 3
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
                            metricColor = chartElements.stock.upColorHalfAlpha
                            context.setFillColor(metricColor.cgColor)
                        }

                        context.fill(CGRect(x: fundamentalAlignments[r].x, y: y, width: -qWidth, height: -barHeight))

                        if barUnit < 5.0 && stockChartElements.count == 1, // only show value of fundamental on bar for single stock charts
                           let label = numberFormatter.string(number: reportValue, maxDigits: Float(2 * xFactor)) {
                            labelPosition.x = fundamentalAlignments[r].x - 11.5 * CGFloat(label.count) - 10
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
    public func magnifyBar(x: CGFloat, y: CGFloat, bar: BarData, monthName: String) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: magnifierSize, height: magnifierSize), false, contentsScale)
        guard let lensContext = UIGraphicsGetCurrentContext() else { return nil }

        var backgroundColor = UIColor.white
        var color = UIColor.black
        if UserDefaults.standard.bool(forKey: "darkMode") {
            backgroundColor = UIColor.black // reverse colors
            color = UIColor.white
        }

        lensContext.setFillColor(backgroundColor.cgColor)
        lensContext.fill(CGRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize))

        let magnification: CGFloat = 2.0
        let midpoint = magnifierSize / (2 * magnification)

        let x = (x - midpoint) * contentsScale // subtract midpoint to make the touch point the center of the lens, not the top left corner
        var y = (y - 2 * midpoint) * contentsScale

        if contentsScale >= 1 {
            lensContext.scaleBy(x: magnification / contentsScale, y: magnification / contentsScale)
        }
        lensContext.draw(layerRef, at: CGPoint(x: -x, y: -y))
        lensContext.setBlendMode(.normal)

        // Overlay background color with 25% opacity so lensContext bar color stands out
        lensContext.setFillColor(backgroundColor.withAlphaComponent(0.25).cgColor)
        lensContext.fill(CGRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize))

        let strokeColor = color

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

        showString(label, at: CGPoint(x: 16.0 * contentsScale, y: 7.0 * contentsScale), with: color, size: 12.0)

        let scopeFactor = (bar.high > bar.low) ? 31.0 * contentsScale / (bar.high - bar.low) : 0
        let midPoint = (bar.high + bar.low) / 2.0

        label = numberFormatter.string(from: NSNumber(value: bar.open)) ?? ""
        y = 27.5 * contentsScale + scopeFactor * (midPoint - bar.open)
        showString(label, at: CGPoint(x: 10.0 * contentsScale, y: y), with: color, size: 12.0)

        y = (y < 27.5 * contentsScale) ? y + 2.5 * contentsScale : y - 5.0 * contentsScale
        lensContext.move(to: CGPoint(x: 20.0 * contentsScale, y: y))
        lensContext.addLine(to: CGPoint(x: 25.0 * contentsScale, y: y))

        label = numberFormatter.string(from: NSNumber(value: bar.high)) ?? ""
        y = 27.5 * contentsScale + scopeFactor * (midPoint - bar.high)
        showString(label, at: CGPoint(x: 22.0 * contentsScale, y: y), with: color, size: 12.0)

        y = (y < 27.5 * contentsScale) ? y + 2.5 * contentsScale : y - 5.0 * contentsScale
        lensContext.move(to: CGPoint(x: 25.0 * contentsScale, y: y))

        label = numberFormatter.string(from: NSNumber(value: bar.low)) ?? ""
        y = 27.5 * contentsScale + scopeFactor * (midPoint - bar.low)
        showString(label, at: CGPoint(x: 22.0 * contentsScale, y: y), with: color, size: 12.0)

        y = (y < 27.5 * contentsScale) ? y + 2.5 * contentsScale : y - 5.0 * contentsScale
        lensContext.addLine(to: CGPoint(x: 25.0 * contentsScale, y: y))

        label = numberFormatter.string(from: NSNumber(value: bar.close)) ?? ""
        y = 27.5 * contentsScale + scopeFactor * (midPoint - bar.close)
        showString(label, at: CGPoint(x: 33.0 * contentsScale, y: y), with: color, size: 12.0)

        y = (y < 27.5 * contentsScale) ? y + 2.5 * contentsScale : y - 5.0 * contentsScale
        lensContext.move(to: CGPoint(x: 25.0 * contentsScale, y: y))
        lensContext.addLine(to: CGPoint(x: 30.0 * contentsScale, y: y))
        lensContext.strokePath()

        let screenshot = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return screenshot
    }

    private func writeLabel(_ price: NSDecimalNumber, for chartElements: ChartElements, atX x: CGFloat, showBox: Bool) -> ChartText {
        let l = numberFormatter.string(from: price) ?? ""

        var y = chartElements.yFloor - chartElements.yFactor * price.doubleValue + 20

        let pxPerPoint: CGFloat = 1 / contentsScale
        y = ChartElements.pxAlign(y, alignTo: pxPerPoint)
        let alignedX = ChartElements.pxAlign(x, alignTo: pxPerPoint)

        if showBox {
            let boxWidth = CGFloat(l.count) * 14
            let padding: CGFloat = 4
            let boxHeight: CGFloat = 28

            let boxRect = CGRect(x: alignedX - pxPerPoint, y: y - boxHeight + padding, width: boxWidth, height: boxHeight)

            layerRef.context?.setStrokeColor(chartElements.stock.upColorHalfAlpha.cgColor)
            layerRef.context?.stroke(boxRect)
        }

        let textPoint = CGPoint(x: alignedX, y: y)
        return string(l, at: textPoint, with: chartElements.stock.upColor)
    }

    /// Returns ChartText struct with info for string with point, color and size to chartText array for later rendering in pushed graphics context
    private func string(_ string: String, at point: CGPoint, with color: UIColor, size: CGFloat = 22) -> ChartText {
        let adjustedPoint = CGPoint(x: point.x, y: point.y - size)
        return ChartText(string: string, position: adjustedPoint, color: color, size: size)
    }

    /// Renders string in current graphics context
    private func showString(_ string: String, at point: CGPoint, with color: UIColor, size: CGFloat) {
        let textAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: size),
                              NSAttributedString.Key.foregroundColor: color]
        string.draw(at: CGPoint(x: point.x, y: point.y - size), withAttributes: textAttributes)
    }

    /// Create a continuous path using the points provided and stroke the final path
    private func strokeLineFromPoints(_ points: [CGPoint], context: CGContext) {
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
    private func strokeLinesFromPoints(_ points: [CGPoint], context: CGContext) {
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
