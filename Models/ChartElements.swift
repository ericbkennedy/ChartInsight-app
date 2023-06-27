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

@objcMembers
class ChartElements: NSObject, NSCopying {
    var monthLabels: NSMutableArray
    var monthLines:  NSMutableArray  // contains CGPoint in NSValue
 
    // fundamentalColumns are a property of StockData because it is loaded once and doesn't change
    // fundamentalAlignments must be updated frequently as the user pans or zooms
    var fundamentalAlignments: NSMutableArray // contains CGFloat
    
    var points:              NSMutableArray  // contains CGPoint in NSValue
    var redPoints:           NSMutableArray  // contains CGPoint in NSValue
    var movingAvg1:          NSMutableArray  // contains CGPoint in NSValue
    var movingAvg2:          NSMutableArray  // contains CGPoint in NSValue
    var upperBollingerBand:  NSMutableArray  // contains CGPoint in NSValue
    var middleBollingerBand: NSMutableArray  // contains CGPoint in NSValue
    var lowerBollingerBand:  NSMutableArray  // contains CGPoint in NSValue
    var greenBars:           NSMutableArray  // contains CGRect in NSValue
    var filledGreenBars:     NSMutableArray  // contains CGRect in NSValue
    var hollowRedBars:       NSMutableArray  // contains CGRect in NSValue
    var redBars:             NSMutableArray  // contains CGRect in NSValue
    var redVolume:           NSMutableArray  // contains CGRect in NSValue
    var blackVolume:         NSMutableArray  // contains CGRect in NSValue
    
    convenience override init() {
        self.init(monthLabels: NSMutableArray(),
                  monthLines: NSMutableArray(),
                  fundamentalAlignments: NSMutableArray(),
                  points: NSMutableArray(),
                  redPoints: NSMutableArray(),
                  movingAvg1: NSMutableArray(),
                  movingAvg2: NSMutableArray(),
                  upperBollingerBand: NSMutableArray(),
                  middleBollingerBand: NSMutableArray(),
                  lowerBollingerBand: NSMutableArray(),
                  greenBars: NSMutableArray(),
                  filledGreenBars: NSMutableArray(),
                  hollowRedBars: NSMutableArray(),
                  redBars: NSMutableArray(),
                  redVolume: NSMutableArray(),
                  blackVolume: NSMutableArray())
    }
    
    init(monthLabels: NSMutableArray, monthLines: NSMutableArray, fundamentalAlignments: NSMutableArray, points: NSMutableArray, redPoints: NSMutableArray, movingAvg1: NSMutableArray, movingAvg2: NSMutableArray, upperBollingerBand: NSMutableArray, middleBollingerBand: NSMutableArray, lowerBollingerBand: NSMutableArray, greenBars: NSMutableArray, filledGreenBars: NSMutableArray, hollowRedBars: NSMutableArray, redBars: NSMutableArray, redVolume: NSMutableArray, blackVolume: NSMutableArray) {
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
        monthLabels.removeAllObjects()
        // Don't remove fundamentalAlignments since the alignments will get updated
        monthLines.removeAllObjects()
        points.removeAllObjects()
        redPoints.removeAllObjects()
        movingAvg1.removeAllObjects()
        movingAvg2.removeAllObjects()
        upperBollingerBand.removeAllObjects()
        middleBollingerBand.removeAllObjects()
        lowerBollingerBand.removeAllObjects()
        greenBars.removeAllObjects()
        filledGreenBars.removeAllObjects()
        hollowRedBars.removeAllObjects()
        redBars.removeAllObjects()
        redVolume.removeAllObjects()
        blackVolume.removeAllObjects()
    }
    
    /// Return a copy of all of the arrays and their elements so rendering can use these values while the user pans to trigger recomputation
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = ChartElements(monthLabels: NSMutableArray(array: monthLabels),
                                 monthLines: NSMutableArray(array: monthLines),
                                 fundamentalAlignments: NSMutableArray(array: fundamentalAlignments),
                                 points: NSMutableArray(array: points),
                                 redPoints: NSMutableArray(array: redPoints),
                                 movingAvg1: NSMutableArray(array: movingAvg1),
                                 movingAvg2: NSMutableArray(array: movingAvg2),
                                 upperBollingerBand: NSMutableArray(array: upperBollingerBand),
                                 middleBollingerBand: NSMutableArray(array: middleBollingerBand),
                                 lowerBollingerBand: NSMutableArray(array: lowerBollingerBand),
                                 greenBars: NSMutableArray(array: greenBars),
                                 filledGreenBars: NSMutableArray(array: filledGreenBars),
                                 hollowRedBars: NSMutableArray(array: hollowRedBars),
                                 redBars: NSMutableArray(array: redBars),
                                 redVolume: NSMutableArray(array: redVolume),
                                 blackVolume: NSMutableArray(array: blackVolume))
        return copy
    }
}
