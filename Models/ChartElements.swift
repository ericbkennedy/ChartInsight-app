//
//  ChartElements.swift
//  ChartInsight
//
//  StockActor computes the elements for one stock and ScrollChartView renders all chart elements.
//  The user can trigger recomputation while panning or zooming so it is important to only
//  provide ScrollChartView with copies of the chart elements after computation.
//
//  Created by Eric Kennedy on 6/27/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

struct ChartElements {
    var stock: Stock
    var monthLabels: [String]
    var monthLines: [CGPoint]
    // Fundamental reports
    var oldestReportInView: Int
    var newestReportInView: Int
    var fundamentalColumns: [String: [NSDecimalNumber]]
    var fundamentalAlignments: [FundamentalAlignment]
    var points: [CGPoint]
    var redPoints: [CGPoint]
    var yFactor: CGFloat
    var yFloor: CGFloat
    var maxHigh: NSDecimalNumber
    var minLow: NSDecimalNumber
    var scaledLow: NSDecimalNumber
    var lastPrice: NSDecimalNumber
    var movingAvg1: [CGPoint]
    var movingAvg2: [CGPoint]
    var upperBollingerBand: [CGPoint]
    var middleBollingerBand: [CGPoint]
    var lowerBollingerBand: [CGPoint]
    var greenBars: [CGRect]
    var filledGreenBars: [CGRect]
    var hollowRedBars: [CGRect]
    var redBars: [CGRect]
    var redVolume: [CGRect]
    var blackVolume: [CGRect]

    init(stock: Stock) {
        self.init(stock: stock,
                  monthLabels: [],
                  monthLines: [],
                  oldestReportInView: 0,
                  newestReportInView: 0,
                  fundamentalColumns: [:],
                  fundamentalAlignments: [],
                  points: [],
                  redPoints: [],
                  yFactor: 0.0,
                  yFloor: 0.0,
                  maxHigh: NSDecimalNumber.one,
                  minLow: NSDecimalNumber.zero,
                  scaledLow: NSDecimalNumber.zero,
                  lastPrice: NSDecimalNumber.one,
                  movingAvg1: [],
                  movingAvg2: [],
                  upperBollingerBand: [],
                  middleBollingerBand: [],
                  lowerBollingerBand: [],
                  greenBars: [],
                  filledGreenBars: [],
                  hollowRedBars: [],
                  redBars: [],
                  redVolume: [],
                  blackVolume: [])
    }

    init(stock: Stock, monthLabels: [String], monthLines: [CGPoint], oldestReportInView: Int, newestReportInView: Int,
         fundamentalColumns: [String: [NSDecimalNumber]], fundamentalAlignments: [FundamentalAlignment],
         points: [CGPoint], redPoints: [CGPoint], yFactor: CGFloat, yFloor: CGFloat,
         maxHigh: NSDecimalNumber, minLow: NSDecimalNumber, scaledLow: NSDecimalNumber, lastPrice: NSDecimalNumber,
         movingAvg1: [CGPoint], movingAvg2: [CGPoint], upperBollingerBand: [CGPoint], middleBollingerBand: [CGPoint],
         lowerBollingerBand: [CGPoint], greenBars: [CGRect], filledGreenBars: [CGRect], hollowRedBars: [CGRect],
         redBars: [CGRect], redVolume: [CGRect], blackVolume: [CGRect]) {
        self.stock = stock
        self.monthLabels = monthLabels
        self.monthLines = monthLines
        self.oldestReportInView = oldestReportInView
        self.newestReportInView = newestReportInView
        self.fundamentalColumns = fundamentalColumns
        self.fundamentalAlignments = fundamentalAlignments
        self.points = points
        self.redPoints = redPoints
        self.yFactor = yFactor
        self.yFloor = yFloor
        self.maxHigh = maxHigh
        self.minLow = minLow
        self.scaledLow = scaledLow
        self.lastPrice = lastPrice
        self.movingAvg1 = movingAvg1
        self.movingAvg2 = movingAvg2
        self.upperBollingerBand = upperBollingerBand
        self.middleBollingerBand = middleBollingerBand
        self.lowerBollingerBand = lowerBollingerBand
        self.greenBars = greenBars
        self.filledGreenBars = filledGreenBars
        self.hollowRedBars = hollowRedBars
        self.redBars = redBars
        self.redVolume = redVolume
        self.blackVolume = blackVolume
    }

    /// Center a stroked line in the center of a pixel.  Point value can be 0.25, 0.333, 0.5, 0.666, or 0.75
    /// bitmap graphics always use pixel context, so they always have alignTo=0.5
    static func pxAlign(_ input: Double, alignTo: Double) -> Double {
        var intPart = 0.0
        if modf(input, &intPart) != alignTo { // modf separates integer and fractional parts
            return intPart + alignTo
        }
        return input
    }

    mutating func clear() {
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
    func fundamentalKeys() -> [String] {
        if !fundamentalColumns.isEmpty {
            return Array(fundamentalColumns.keys)
        }
        return []
    }

    /// Metric value (or .notANumber) for a report index and metric key
    func fundamentalValue(forReport report: Int, metric: String) -> NSDecimalNumber {
        if !fundamentalColumns.isEmpty {
            if let valuesForMetric = fundamentalColumns[metric], report < valuesForMetric.count {
                return valuesForMetric[report]
            }
        }
        return NSDecimalNumber.notANumber
    }

    func fundamentalReportCount() -> Int {
        return fundamentalAlignments.count
    }

    mutating func setBarAlignment(_ barIndex: Int, report: Int) {
        if report < fundamentalAlignments.count {
            fundamentalAlignments[report].bar = barIndex
        }
    }

    func barAlignmentFor(report: Int) -> Int {
        if report < fundamentalAlignments.count {
            return fundamentalAlignments[report].bar
        }
        return -1
    }

    func valueFor(report: Int, key: String) -> NSDecimalNumber {
        if let metricValues = fundamentalColumns[key],
           report < metricValues.count {
            return metricValues[report]
        }
        return NSDecimalNumber.notANumber // ScrollChartView will skip it
    }
}
