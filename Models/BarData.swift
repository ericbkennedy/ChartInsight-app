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

final class BarData {
    public var year: NSInteger = 0
    public var month: NSInteger = 0
    public var day: NSInteger = 0
    public var open: Double = 0.0
    public var high: Double = 0.0
    public var low: Double = 0.0
    public var close: Double = 0.0
    public var adjClose: Double = 0.0
    public var volume: Double = 0.0 // Converted from int to simplify graphics code
    public var movingAvg1: Double = -1.0
    public var movingAvg2: Double = -1.0
    public var mbb: Double = -1.0
    public var stdev: Double = -1.0

    public static func == (lhs: BarData, rhs: BarData) -> Bool {

        if lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day {
            return true
        }
        return false
    }

    /// Returns 20230630 for 2023 June 30
    public func dateIntFromBar() -> Int {
        return year * 10000 + month * 100 + day
    }

    /// Returns a short month name for this bar with a trailing space to append the year as space allows
    public func monthName(calendar: Calendar) -> String {
        var monthName = ""
        let monthShortNames = calendar.shortMonthSymbols
        if month >= 0 && month <= monthShortNames.count {
            monthName = monthShortNames[month - 1]
        }
        return monthName + " "
    }

    /// If CSV line contains yyyy-mm-dd,open,high,low,close,volume then a new BarData object will be returned
    /// date,open,high,low,close,volume
    /// 2023-06-15,179.9650,180.1200,177.4300,179.2100,64848374
    public static func parse(from line: String) -> BarData? {
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
                    if barData.year > 1990 {
                        return barData
                    }
                }
            }
        }
        return nil
    }

    /// Calculate weekly high, low, close and volume starting from startDate using calendar to advance a week at at time
    public static func groupByWeek(_ dailyData: [BarData], calendar: Calendar, startDate: Date) -> [BarData] {
        var startDate = startDate // will be updated in repeat while loop
        var dayIndex = 0
        var weekIndex = 0
        var periodData: [BarData] = []

        repeat {
            let weeklyBar = BarData()
            periodData.append(weeklyBar)
            weeklyBar.close = dailyData[dayIndex].close
            weeklyBar.adjClose = dailyData[dayIndex].adjClose
            weeklyBar.high = dailyData[dayIndex].high
            weeklyBar.low = dailyData[dayIndex].low
            weeklyBar.volume = dailyData[dayIndex].volume
            weeklyBar.movingAvg1 = 0.0
            weeklyBar.movingAvg2 = 0.0
            weeklyBar.mbb = 0.0
            weeklyBar.stdev = 0.0

            var componentsToSubtract = DateComponents()
            let weekdayComponents = calendar.component(.weekday, from: startDate)

            // Get the previous Friday, convert it into an NSInteger and then group all dates LARGER than it into the current week
            // Friday is weekday 6 in Gregorian calendar, so subtract current weekday and -1 to get previous Friday
            componentsToSubtract.day = -1 - weekdayComponents
            let lastFriday = calendar.date(byAdding: componentsToSubtract, to: startDate)!

            let lastFridayY = calendar.component(.year, from: lastFriday)
            let lastFridayM = calendar.component(.month, from: lastFriday)
            let lastFridayD = calendar.component(.day, from: lastFriday)

            let lastFridayDateInt: Int = 10000 * lastFridayY + 100 * lastFridayM + lastFridayD

            dayIndex += 1
            while dayIndex < dailyData.count &&
                    dailyData[dayIndex].dateIntFromBar() > lastFridayDateInt {

                if dailyData[dayIndex].high > weeklyBar.high {
                    weeklyBar.high = dailyData[dayIndex].high
                }
                if dailyData[dayIndex].low < weeklyBar.low {
                    weeklyBar.low = dailyData[dayIndex].low
                }
                weeklyBar.volume += dailyData[dayIndex].volume
                dayIndex += 1
            }

            weeklyBar.year = dailyData[dayIndex - 1].year
            weeklyBar.month = dailyData[dayIndex - 1].month
            weeklyBar.day = dailyData[dayIndex - 1].day
            weeklyBar.open = dailyData[dayIndex - 1].open

            startDate = lastFriday
            weekIndex += 1
        } while dayIndex < dailyData.count // continue loop

        return periodData
    }

    /// Calculate monthly high, low, close and volume
    public static func groupByMonth(_ dailyData: [BarData]) -> [BarData] {
        var dayIndex = 0
        var monthIndex = 0
        var periodData: [BarData] = []
        repeat {
            let monthlyBar = BarData()
            periodData.append(monthlyBar)

            monthlyBar.close = dailyData[dayIndex].close
            monthlyBar.adjClose = dailyData[dayIndex].adjClose
            monthlyBar.high = dailyData[dayIndex].high
            monthlyBar.low = dailyData[dayIndex].low
            monthlyBar.volume = dailyData[dayIndex].volume
            monthlyBar.year = dailyData[dayIndex].year
            monthlyBar.month = dailyData[dayIndex].month
            monthlyBar.movingAvg1 = 0.0
            monthlyBar.movingAvg2 = 0.0
            monthlyBar.mbb = 0.0
            monthlyBar.stdev = 0.0

            dayIndex += 1
            while dayIndex < dailyData.count && dailyData[dayIndex].month == monthlyBar.month {
                if dailyData[dayIndex].high > monthlyBar.high {
                    monthlyBar.high = dailyData[dayIndex].high
                }
                if dailyData[dayIndex].low < monthlyBar.low {
                    monthlyBar.low = dailyData[dayIndex].low
                }
                monthlyBar.volume += dailyData[dayIndex].volume
                dayIndex += 1
            }

            monthlyBar.open = dailyData[dayIndex - 1].open
            monthlyBar.day = dailyData[dayIndex - 1].day
            monthIndex += 1
        } while dayIndex < dailyData.count // continue loop

        return periodData
    }

    /// Calculate 50 and 200 period simple moving averages starting from the last bar in periodData
    public static func calculateSMA(periodData: [BarData]) {
        let oldest50available = periodData.count - 50
        let oldest200available = periodData.count - 200

        if oldest50available > 0 {
            var movingSum50: Double = 0.0
            var movingSum150: Double = 0.0

            for index in (0..<periodData.count).reversed() {
                movingSum50 += periodData[index].close

                if index < oldest50available {
                    movingSum150 += periodData[index + 50].close
                    movingSum50 -= periodData[index + 50].close

                    if index < oldest200available {
                        movingSum150 -= periodData[index + 200].close
                        // i + n - 1, so for bar zero it subtracks bar 199 (200th bar)
                        periodData[index].movingAvg2 = (movingSum50 + movingSum150) / 200
                    } else if index == oldest200available {
                        periodData[index].movingAvg2 = (movingSum50 + movingSum150) / 200
                    }

                    periodData[index].movingAvg1 = movingSum50 / 50
                } else if index == oldest50available {
                    periodData[index].movingAvg1 = movingSum50 / 50
                }
            }
        }
    }

    /// Bollinger bands use a 20 period simple moving average with parallel bands a standard deviation above and below
    /// Upper Band = 20-day SMA + (20-day standard deviation of price x 2)
    /// Lower Band = 20-day SMA - (20-day standard deviation of price x 2)
    public static func calculateBollingerBands(periodData: [BarData]) {
        let period = 20
        let firstFullPeriod = periodData.count - period

        if firstFullPeriod > 0 {
            var movingSum: Double = 0.0
            var powerSumAvg: Double = 0.0

            for index in (0 ..< periodData.count).reversed() {
                movingSum += periodData[index].close

                if index < firstFullPeriod {
                    movingSum -= periodData[index + period].close

                    periodData[index].mbb = movingSum / Double(period)

                    powerSumAvg += (pow(periodData[index].close, 2) - pow(periodData[index + period].close, 2)) / Double(period)

                    periodData[index].stdev = sqrt(powerSumAvg - periodData[index].mbb * periodData[index].mbb)

                } else if index >= firstFullPeriod {
                    powerSumAvg += (periodData[index].close * periodData[index].close - powerSumAvg) / Double(periodData.count - index)

                    if index == firstFullPeriod {
                        periodData[index].mbb = movingSum / Double(period)
                        periodData[index].stdev = sqrt(powerSumAvg - periodData[index].mbb * periodData[index].mbb)
                    }
                }
            }
        }
    }

}
