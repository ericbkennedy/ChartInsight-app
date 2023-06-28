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
    var volume: Double = 0.0 // Converted from int to simplify graphics code
    var movingAvg1: Double = -1.0
    var movingAvg2: Double = -1.0
    var mbb: Double = -1.0
    var stdev: Double = -1.0
    var upClose: Bool = false // currently only set after user long presses on the chart
    
    enum MonthShortName: String, CaseIterable {
        case Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec
    }
    
    static func == (lhs: BarData, rhs: BarData) -> Bool {
        
        if lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day {
            return true
        }
        return false;
    }
    
    func dateIntFromBar() -> Int {

        return year * 10000 + month * 100 + day;
    }
    
    /// Returns a short month name for this bar with a trailing space to append the year as space allows
    func monthName() -> String {
        var monthName = ""
        if month >= 0 && month <= 12 {
            monthName = MonthShortName.allCases[month - 1].rawValue
        }
        return monthName + " "
    }
    
    /// If CSV line contains yyyy-mm-dd,open,high,low,close,volume then a new BarData object will be returned
    /// date,open,high,low,close,volume
    /// 2023-06-15,179.9650,180.1200,177.4300,179.2100,64848374
    static func parse(from line: String) -> BarData? {
        if line.count > 0 {
            let cols = line.components(separatedBy: ",")
            if cols.count == 6 {
                let dateParts = cols[0].components(separatedBy: "-")
                if dateParts.count == 3 {
                    let barData = BarData() // note this is a class so properties can be mutated
                    barData.year   = Int(dateParts[0]) ?? 0
                    barData.month  = Int(dateParts[1]) ?? 0
                    barData.day    = Int(dateParts[2]) ?? 0
                    barData.open   = Double(cols[1]) ?? 0.0
                    barData.high   = Double(cols[2]) ?? 0.0
                    barData.low    = Double(cols[3]) ?? 0.0
                    barData.close  = Double(cols[4]) ?? 0.0
                    barData.volume = Double(Int(cols[5]) ?? 0)
                    if (barData.year > 1990) {
                        return barData
                    }
                }
            }
        }
        return nil
    }
}
