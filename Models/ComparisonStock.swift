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

import CoreData
import Foundation
import UIKit

public enum ChartType: Int, CaseIterable {
    case ohlc, hlc, candle, close
}

public struct Stock {
    public var  id: Int = 0
    public var  hasFundamentals: Bool = true
    public var  ticker: String = ""
    public var  name: String = ""
    public var  startDateString: String = "" // full text search returns a string value
}

@objc(ComparisonStock)
public class ComparisonStock: NSManagedObject {
    @NSManaged public var stockId: Int64
    @NSManaged public var chartType: Int64
    @NSManaged public var ticker: String
    @NSManaged public var name: String
    @NSManaged public var hasFundamentals: Bool
    @NSManaged public var fundamentalList: String
    @NSManaged public var technicalList: String
    @NSManaged public var startDateString: String
    @NSManaged public var hexColor: String
    @NSManaged public var comparison: Comparison?
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
            hexColor = newColor.hexString
        }
    }
    public var  upColorHalfAlpha: UIColor = .init(red: 0, green: 0.6, blue: 0, alpha: 0.5)

    /// Initialize ComparisonStock using user default settings (if set) or app defaults
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        if let defaultChartType = ChartType(rawValue: UserDefaults.standard.integer(forKey: "chartTypeDefault")) {
            chartType = Int64(defaultChartType.rawValue)
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

    /// Set the stock chart colors from the saved hex value
    public override func awakeFromFetch() {
        if let colorFromHex = ChartHexColor(rawValue: hexColor) {
            setColors(upHexColor: colorFromHex)
        }
    }

    /// Use the values in the provided stock for this comparisonStock. Returns self to allow chaining methods.
    public func setValues(with stock: Stock) -> ComparisonStock {
        stockId = Int64(stock.id)
        name = stock.name
        ticker = stock.ticker
        startDateString = stock.startDateString
        hasFundamentals = stock.hasFundamentals
        if hasFundamentals == false {
            fundamentalList = ""
        }
        return self
    }

    /// Set the up color using provided ChartHexColor value and if that value is .greenAndRed then down color is .red
    public func setColors(upHexColor: ChartHexColor) {

        upColor = upHexColor.color()
        if upHexColor == .greenAndRed && chartType != ChartType.close.rawValue {
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

    public func addToFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) == false {
            fundamentalList = fundamentalList.appending("\(metric),")
        }
    }

    public func removeFromFundamentals(_ metric: String) {
        if fundamentalList.contains(metric) {
            fundamentalList = fundamentalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }

    public func addToTechnicals(_ metric: String) {
        if technicalList.contains(metric) == false {
            technicalList = technicalList.appending("\(metric),")
        }
    }

    public func removeFromTechnicals(_ metric: String) {
        if technicalList.contains(metric) {
            technicalList = technicalList.replacingOccurrences(of: "\(metric),", with: "")
        }
    }
}

// MARK: CoreData managed properties
extension ComparisonStock: Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ComparisonStock> {
        return NSFetchRequest<ComparisonStock>(entityName: "ComparisonStock")
    }
}
