//
//  Stock.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

enum ChartType: Int, CaseIterable {
    case ohlc, hlc, candle, close
}

class Stock: NSObject {
    static let chartColors = [UIColor.init(red: 0, green: 0.6, blue: 0, alpha: 1.0), // green
                              UIColor.init(red: 0, green: 0.6, blue: 1.0, alpha: 1.0), // blue
                              UIColor.init(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0), // purple
                              UIColor.init(red: 1.0, green: 0.8, blue: 0, alpha: 1.0), // yellow
                              UIColor.init(red: 1.0, green: 0.6, blue: 0, alpha: 1.0), // orange
                              UIColor.init(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)] // gray

    var id: Int = 0
    var chartType: ChartType = .close
    var comparisonStockId: Int = 0
    var hasFundamentals: Bool = true
    var color: UIColor = .red {
        willSet(newColor) {
            let (red, green, blue) = newColor.rgba
            colorHalfAlpha = UIColor.init(red: red, green: green, blue: blue, alpha: 0.5)
        }
    }
    var colorHalfAlpha: UIColor = .init(red: 1, green: 0, blue: 0, alpha: 0.5)
    var colorInverse: UIColor = .green
    var colorInverseHalfAlpha: UIColor = .init(red: 0, green: 1, blue: 0, alpha: 0.5)
    var upColor: UIColor = .init(red: 0, green: 0.6, blue: 0, alpha: 1) {
        willSet(newColor) {
            let (red, green, blue) = newColor.rgba
            upColorHalfAlpha = UIColor.init(red: red, green: green, blue: blue, alpha: 0.5)
            colorInverse = UIColor.init(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 1.0)
            colorInverseHalfAlpha = UIColor.init(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 0.5)
        }
    }
    var upColorHalfAlpha: UIColor = .init(red: 0, green: 0.6, blue: 0, alpha: 0.5)
    var ticker: String = ""
    var name: String = ""
    var fundamentalList: String = ""
    var technicalList: String = ""
    var startDateString: String = "" // full text search returns a string value
    var startDate: Date?             // converted from startDateString

    override init() {
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

        super.init()
    }

    func setColorWith(hexString: String) {

        if let upColor = UIColor.init(hex: hexString) {
            self.upColor = upColor
            if hexString == "009900" && chartType != .close {
                color = .red // upColor is green so other bars should be red
            } else {
                color = upColor
            }
        } else {
            color = .red // default: when color == red, upColor is green
        }
    }

    func hexFromUpColor() -> String {
        return upColor.hexString
    }

    func hasUpColor(otherColor: UIColor) -> Bool {

        if upColor.hexString == otherColor.hexString {
            return true
        }
        return false
    }

    func addToFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) == false {
            fundamentalList = fundamentalList.appending("\(metric),")
        }
    }

    func removeFromFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) {
            fundamentalList = fundamentalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }

    func addToTechnicals(_ metric: String) {
        if technicalList.contains(metric) == false {
            technicalList = technicalList.appending("\(metric),")
        }
    }

    func removeFromTechnicals(_ metric: String) {
        if technicalList.contains(metric) {
            technicalList = technicalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }
}
