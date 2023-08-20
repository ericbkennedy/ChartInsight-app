//
//  ChartElements.swift
//  ChartInsight
//
//  StockActor computes the elements for one stock and ChartRenderer renders all chart elements.
//  The user can trigger recomputation while panning or zooming so it is important to only
//  provide the ChartRenderer with copies of the chart elements after computation.
//
//  Created by Eric Kennedy on 6/27/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

struct ChartElements {
    public var stock: ComparisonStock
    public var monthLabels: [String] = []
    public var monthLines: [CGPoint] = []
    // Fundamental reports
    public var oldestReportInView: Int = 0
    public var newestReportInView: Int = 0
    public var fundamentalColumns: [String: [NSDecimalNumber]] = [:]
    public var fundamentalAlignments: [FundamentalAlignment] = []
    public var points: [CGPoint] = []
    public var redPoints: [CGPoint] = []
    public var yFactor: CGFloat = 0.0
    public var yFloor: CGFloat = 0.0
    public var maxHigh: NSDecimalNumber = .one
    public var minLow: NSDecimalNumber = .zero
    public var scaledLow: NSDecimalNumber = .zero
    public var lastPrice: NSDecimalNumber = .one
    public var movingAvg1: [CGPoint] = []
    public var movingAvg2: [CGPoint] = []
    public var upperBollingerBand: [CGPoint] = []
    public var middleBollingerBand: [CGPoint] = []
    public var lowerBollingerBand: [CGPoint] = []
    public var greenBars: [CGRect] = []
    public var filledGreenBars: [CGRect] = []
    public var hollowRedBars: [CGRect] = []
    public var redBars: [CGRect] = []
    public var redVolume: [CGRect] = []
    public var blackVolume: [CGRect] = []

    /// Center a stroked line in the center of a pixel.  Point value can be 0.25, 0.333, 0.5, 0.666, or 0.75
    /// bitmap graphics always use pixel context, so they always have alignTo=0.5
    public static func pxAlign(_ input: Double, alignTo: Double) -> Double {
        var intPart = 0.0
        if modf(input, &intPart) != alignTo { // modf separates integer and fractional parts
            return intPart + alignTo
        }
        return input
    }

    public mutating func clear() {
        monthLabels.removeAll(keepingCapacity: true)
        // Don't remove fundamentalColumns since the values loaded once and won't change
        // Don't remove fundamentalAlignments since the alignments will get updated
        monthLines.removeAll(keepingCapacity: true)
        points.removeAll(keepingCapacity: true)
        redPoints.removeAll(keepingCapacity: true)
        movingAvg1.removeAll(keepingCapacity: true)
        movingAvg2.removeAll(keepingCapacity: true)
        upperBollingerBand.removeAll(keepingCapacity: true)
        middleBollingerBand.removeAll(keepingCapacity: true)
        lowerBollingerBand.removeAll(keepingCapacity: true)
        greenBars.removeAll(keepingCapacity: true)
        filledGreenBars.removeAll(keepingCapacity: true)
        hollowRedBars.removeAll(keepingCapacity: true)
        redBars.removeAll(keepingCapacity: true)
        redVolume.removeAll(keepingCapacity: true)
        blackVolume.removeAll(keepingCapacity: true)
    }

    /// Returns all fundamental metric keys or [] if fundamentals aren't loaded
    public func fundamentalKeys() -> [String] {
        if !fundamentalColumns.isEmpty {
            return Array(fundamentalColumns.keys)
        }
        return []
    }

    /// Metric value (or .notANumber) for a report index and metric key
    public func fundamentalValue(forReport report: Int, metric: String) -> NSDecimalNumber {
        if !fundamentalColumns.isEmpty {
            if let valuesForMetric = fundamentalColumns[metric], report < valuesForMetric.count {
                return valuesForMetric[report]
            }
        }
        return NSDecimalNumber.notANumber
    }

    public func fundamentalReportCount() -> Int {
        return fundamentalAlignments.count
    }

    public mutating func setBarAlignment(_ barIndex: Int, report: Int) {
        if report < fundamentalAlignments.count {
            fundamentalAlignments[report].bar = barIndex
        }
    }

    public func barAlignmentFor(report: Int) -> Int {
        if report < fundamentalAlignments.count {
            return fundamentalAlignments[report].bar
        }
        return -1
    }

    public func valueFor(report: Int, key: String) -> NSDecimalNumber {
        if let metricValues = fundamentalColumns[key],
           report < metricValues.count {
            return metricValues[report]
        }
        return NSDecimalNumber.notANumber // ChartRenderer will skip it
    }
}
