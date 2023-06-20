//
//  Comparison.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class Comparison: NSObject {
    typealias sqlite3ptr = OpaquePointer?
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    @objc var id: Int = 0
    @objc var stockList: [Stock] = []
    @objc var title: String = ""
    var minKeyValues: [String: NSDecimalNumber] = [:]
    var maxKeyValues: [String: NSDecimalNumber] = [:]
      
    /// Union of all metric keys for stocks in this comparison set
    @objc func sparklineKeys() -> [String] {
        var fundamentalKeys = "";
            
        for stock in stockList {
            fundamentalKeys = fundamentalKeys.appending(stock.fundamentalList)
        }
     
        // TODO: load from bundle
        var allMetrics = [["CIRevenuePerShare", "EarningsPerShareBasic"],
                          ["CINetCashFromOpsPerShare"]]
        var sortedMetrics: [String] = []
        
        for category in allMetrics {
            for key in category {
                if fundamentalKeys.contains(key) {
                    sortedMetrics.append(key)
                }
            }
        }
        return sortedMetrics
    }
    
    @objc func resetMinMax() {
        minKeyValues.removeAll(keepingCapacity: true)
        maxKeyValues.removeAll(keepingCapacity: true)
    }
    
    @objc func updateMinMax(for key: String, value: NSDecimalNumber?) {
        guard value != nil && value != .notANumber else { return }

        if let minValueForKey = minKeyValues[key], minValueForKey != .notANumber {
            if value?.compare(minValueForKey) == .orderedAscending {
                print("report value \(String(describing: value)) < \(minValueForKey)")
                minKeyValues[key] = value
            }
            if let maxValueForKey = maxKeyValues[key],
               value?.compare(maxValueForKey) == .orderedDescending {
                print("report value \(String(describing: value)) > \(maxValueForKey)")
                maxKeyValues[key] = value
            }
            
        } else { // if min(for: key) == nil || min(for: key) == .notANumber {
            if (value?.compare(NSDecimalNumber.zero) == .orderedAscending) {
                minKeyValues[key] = value
            } else {
                minKeyValues[key] = NSDecimalNumber.zero
            }
            print("initializing min to \(String(describing: minKeyValues[key])) for key \(key)")
            maxKeyValues[key] = value
        }
    }
    
    // Returns notANumber if no values for key
    @objc func range(for key: String) -> NSDecimalNumber {
        if let maxValue = maxKeyValues[key],
           let minValue = minKeyValues[key] {
            return maxValue.subtracting(minValue)
        }
        return NSDecimalNumber.notANumber
    }
    
    @objc func min(for key: String) -> NSDecimalNumber? {
        return minKeyValues[key]
    }
    
    @objc func max(for key: String) -> NSDecimalNumber? {
        return maxKeyValues[key]
    }
    
    static func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }
    
    @objc func add(_ stock: Stock) {
        stockList.append(stock)
        saveToDb()
    }
    
    @objc func saveToDb() {
        print("Finish rewrite to Swift")
    }
    
    /// Deletes comparison row and all comparisonStock rows
    @objc func deleteFromDb() {
        var db: sqlite3ptr = nil
        
        guard SQLITE_OK == sqlite3_open(Comparison.dbPath(), &db) else { return }
        var statement: sqlite3ptr = nil
        
        var sql = "DELETE FROM comparisonStock WHERE comparisonId = ?"
        
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
        
        sqlite3_bind_int64(statement, 1, Int64(id))
        
        if SQLITE_DONE != sqlite3_step(statement){
            print(String(format: "Delete comparisonStock DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement);
        
        sql = "DELETE FROM comparison WHERE rowid = ?"
        
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
                
        sqlite3_bind_int64(statement, 1, Int64(id))
        
        if SQLITE_DONE != sqlite3_step(statement){
            print(String(format: "Delete comparisonStock DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement);
        sqlite3_close(db);        
    }
    
    @objc(deleteStock:) func delete(stock: Stock) {
        print("Finish rewrite to Swift")
    }
    
    @objc
    static func listAll() -> [Comparison] {
        var list: [Comparison] = []
        var db: sqlite3ptr = nil
        
        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return list }
        var statement: sqlite3ptr = nil
        
        enum CI: Int32 {
            case comparisonId
            case comparisonStockId
            case stockId
            case symbol
            case startDate
            case hasFundamentals
            case chartType
            case color
            case fundamentalList
            case technicalList
        }
        
        let sql = "SELECT K.rowid, CS.rowid, stockId, symbol, startDate, hasFundamentals, chartType, color, fundamentals, technicals FROM comparison K JOIN comparisonStock CS on K.rowid = CS.comparisonId JOIN stock ON stock.rowid = stockId ORDER BY K.rowid, CS.rowId"
       
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return list }
        
        var comparison: Comparison = Comparison() // Note set this to nil once Comparison is fully Swift
        var lastComparisonId = 0
        var title = ""
        
        while (SQLITE_ROW == sqlite3_step(statement)) {
            if lastComparisonId != sqlite3_column_int(statement, 0) {
                comparison = Comparison()
                comparison.id = Int(sqlite3_column_int(statement, 0))
                lastComparisonId = comparison.id
                list.append(comparison)
                title = ""
            }
            let stock = Stock()
            stock.comparisonStockId = Int(sqlite3_column_int(statement, CI.comparisonStockId.rawValue))
            stock.id = Int(sqlite3_column_int(statement, CI.stockId.rawValue))
            stock.symbol = String(cString: UnsafePointer(sqlite3_column_text(statement, CI.symbol.rawValue)))
            title = title.appending("\(stock.symbol) ")
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, CI.startDate.rawValue)))
            // startDateString will be converted to NSDate by [StockData init] as price data is loaded
            
            stock.hasFundamentals = 0 < sqlite3_column_int(statement, CI.hasFundamentals.rawValue)
            if let chartType = ChartType(rawValue: Int(sqlite3_column_int(statement, CI.chartType.rawValue))) {
                stock.chartType = chartType
            }
            
            let hexString = String(cString: UnsafePointer(sqlite3_column_text(statement, CI.color.rawValue)))
            
            if hexString != "" {
                stock.setColorWith(hexString: hexString)
            } else {
                stock.setColorWith(hexString: "009900") // upColor = green, down = red
            }
            
            if sqlite3_column_bytes(statement, CI.fundamentalList.rawValue) > 2 {
                stock.fundamentalList = String(cString: UnsafePointer(sqlite3_column_text(statement, CI.fundamentalList.rawValue)))
            }
            
            if sqlite3_column_bytes(statement, CI.technicalList.rawValue) > 2 {
                stock.technicalList = String(cString: UnsafePointer(sqlite3_column_text(statement, CI.technicalList.rawValue)))
            }
            
            comparison.stockList.append(stock)
            comparison.title = title
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
            
        return list
    }
    
}
