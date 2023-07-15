//
//  Stock.swift
//  ChartInsight
//
//  Stock objects contain user settings for a stock comparison plus company info like ticker, name, startDate, hasFundamentals.
//  When the user selects a new stock from AddStockController, comparisonStockId == 0 so DBActor knows to insert it into comparisonStock
//  and return the insertedComparisonStockId. 
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

public enum ChartType: Int, CaseIterable {
    case ohlc, hlc, candle, close
}

struct Stock {
    public var  id: Int = 0
    public var  chartType: ChartType = .close
    public var  comparisonStockId: Int = 0
    public var  hasFundamentals: Bool = true
    public var  color: UIColor = .red {
        willSet(newColor) {
            let (red, green, blue) = newColor.rgba
            colorHalfAlpha = UIColor.init(red: red, green: green, blue: blue, alpha: 0.5)
        }
    }
    public var  colorHalfAlpha: UIColor = .init(red: 1, green: 0, blue: 0, alpha: 0.5)
    public var  colorInverse: UIColor = .green
    public var  colorInverseHalfAlpha: UIColor = .init(red: 0, green: 1, blue: 0, alpha: 0.5)
    public var  upColor: UIColor = ChartHexColor.greenAndRed.color() {
        willSet(newColor) {
            let (red, green, blue) = newColor.rgba
            upColorHalfAlpha = UIColor.init(red: red, green: green, blue: blue, alpha: 0.5)
            colorInverse = UIColor.init(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 1.0)
            colorInverseHalfAlpha = UIColor.init(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 0.5)
        }
    }
    public var  upColorHalfAlpha: UIColor = .init(red: 0, green: 0.6, blue: 0, alpha: 0.5)
    public var  ticker: String = ""
    public var  name: String = ""
    public var  fundamentalList: String = ""
    public var  technicalList: String = ""
    public var  startDateString: String = "" // full text search returns a string value
    public var  startDate: Date?             // converted from startDateString

    public init() {
        if let defaultChartType = ChartType(rawValue: UserDefaults.standard.integer(forKey: "chartTypeDefault")) {
            chartType = defaultChartType
        }

        if let technicalDefaults = UserDefaults.standard.string(forKey: "technicalDefaults") {
            technicalList = technicalDefaults
        } else {
            technicalList = "sma200,"
        }

        if let fundamentalDefaults = UserDefaults.standard.string(forKey: "fundamentalDefaults") {
            fundamentalList = fundamentalDefaults
        } else {
            fundamentalList = "CIRevenuePerShare,EarningsPerShareBasic,CINetCashFromOpsPerShare,"
        }
    }

    /// Set the up color using provided ChartHexColor value and if that value is .greenAndRed then down color is .red
    public mutating func setColors(upHexColor: ChartHexColor) {

        upColor = upHexColor.color()
        if upHexColor == .greenAndRed && chartType != .close {
            color = .red // upColor is green so other bars should be red
        } else {
            color = upColor
        }
    }

    public func hasUpColor(otherHexColor: ChartHexColor) -> Bool {

        if upColor.hexString == otherHexColor.rawValue {
            return true
        }
        return false
    }

    public mutating func addToFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) == false {
            fundamentalList = fundamentalList.appending("\(metric),")
        }
    }

    public mutating func removeFromFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) {
            fundamentalList = fundamentalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }

    public mutating func addToTechnicals(_ metric: String) {
        if technicalList.contains(metric) == false {
            technicalList = technicalList.appending("\(metric),")
        }
    }

    public mutating func removeFromTechnicals(_ metric: String) {
        if technicalList.contains(metric) {
            technicalList = technicalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }
}
