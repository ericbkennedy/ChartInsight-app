//
//  BarData.swift
//  ChartInsight
//
//  Stock price data for a period (day, week or month). 
//
//  Created by Eric Kennedy on 6/13/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

@objcMembers class BarData: NSObject {
    
    var year: NSInteger = 0
    var month: NSInteger = 0
    var day: NSInteger = 0
    var open: Double = 0.0
    var high: Double = 0.0
    var low: Double = 0.0
    var close: Double = 0.0
    var adjClose: Double = 0.0
    var volume: Double = 0.0
    var movingAvg1: Double = 0.0
    var movingAvg2: Double = 0.0
    var mbb: Double = 0.0
    var stdev: Double = 0.0
    var splitRatio: Double = 0.0
    
    static func == (lhs: BarData, rhs: BarData) -> Bool {
        
        if lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day {
            return true
        }
        return false;
    }
    
    func dateIntFromBar() -> Int {

        return year * 10000 + month * 100 + day;
    }
}
