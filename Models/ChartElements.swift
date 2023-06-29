//
//  ChartElements.swift
//  ChartInsight
//
//  StockData computes the elements for one stock and ScrollChartView renders all chart elements.
//  The user can trigger recomputation while panning or zooming so it is important to only
//  provide ScrollChartView with copies of the chart elements after computation.
//
//  Created by Eric Kennedy on 6/27/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class ChartElements: NSObject, NSCopying {
    var monthLabels: [String]
    var monthLines:  [CGPoint]
 
    // fundamentalColumns are a property of StockData because it is loaded once and doesn't change
    // fundamentalAlignments must be updated frequently as the user pans or zooms
    var fundamentalAlignments: [CGFloat]
    
    var points:              [CGPoint]
    var redPoints:           [CGPoint]
    var movingAvg1:          [CGPoint]
    var movingAvg2:          [CGPoint]
    var upperBollingerBand:  [CGPoint]
    var middleBollingerBand: [CGPoint]
    var lowerBollingerBand:  [CGPoint]
    var greenBars:           [CGRect]
    var filledGreenBars:     [CGRect]
    var hollowRedBars:       [CGRect]
    var redBars:             [CGRect]
    var redVolume:           [CGRect]
    var blackVolume:         [CGRect]
    
    convenience override init() {
        self.init(monthLabels: [],
                  monthLines: [],
                  fundamentalAlignments: [],
                  points: [],
                  redPoints: [],
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
    
    init(monthLabels: [String], monthLines: [CGPoint], fundamentalAlignments: [CGFloat], points: [CGPoint], redPoints: [CGPoint], movingAvg1: [CGPoint], movingAvg2: [CGPoint], upperBollingerBand: [CGPoint], middleBollingerBand: [CGPoint], lowerBollingerBand: [CGPoint], greenBars: [CGRect], filledGreenBars: [CGRect], hollowRedBars: [CGRect], redBars: [CGRect], redVolume: [CGRect], blackVolume: [CGRect]) {
        self.monthLabels = monthLabels
        self.monthLines = monthLines
        self.fundamentalAlignments = fundamentalAlignments
        self.points = points
        self.redPoints = redPoints
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
    
    func clear() {
        monthLabels.removeAll(keepingCapacity: true)
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
    
    /// Return a copy of all of the arrays and their elements so rendering can use these values while the user pans to trigger recomputation
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = ChartElements(monthLabels: Array(monthLabels),
                                 monthLines: Array(monthLines),
                                 fundamentalAlignments: Array(fundamentalAlignments),
                                 points: Array(points),
                                 redPoints: Array(redPoints),
                                 movingAvg1: Array(movingAvg1),
                                 movingAvg2: Array(movingAvg2),
                                 upperBollingerBand: Array(upperBollingerBand),
                                 middleBollingerBand: Array(middleBollingerBand),
                                 lowerBollingerBand: Array(lowerBollingerBand),
                                 greenBars: Array(greenBars),
                                 filledGreenBars: Array(filledGreenBars),
                                 hollowRedBars: Array(hollowRedBars),
                                 redBars: Array(redBars),
                                 redVolume: Array(redVolume),
                                 blackVolume: Array(blackVolume))
        return copy
    }
}
