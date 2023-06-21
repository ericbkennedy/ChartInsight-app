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
    var minMetricValues: [String: NSDecimalNumber] = [:]
    var maxMetricValues: [String: NSDecimalNumber] = [:]
      
    /// Union of all metric keys for stocks in this comparison set
    @objc func sparklineKeys() -> [String] {
        var fundamentalKeys = "";
            
        for stock in stockList {
            fundamentalKeys = fundamentalKeys.appending(stock.fundamentalList)
        }
     
        var sortedMetrics: [String] = []
        
        if let delegate = UIApplication.shared.delegate as? CIAppDelegate {
            for category in delegate.metrics {
                for metric in category {
                    if metric.count > 0 {
                        let metricKey = String(metric[0])
                        if fundamentalKeys.contains(metricKey) {
                            sortedMetrics.append(metricKey)
                        }
                    }
                }
            }
        }
        return sortedMetrics
    }
    
    @objc func resetMinMax() {
        minMetricValues.removeAll(keepingCapacity: true)
        maxMetricValues.removeAll(keepingCapacity: true)
    }
    
    /// Determine min and max values for fundamental metric key
    @objc func updateMinMax(for key: String, value: NSDecimalNumber?) {
        guard value != nil && value != .notANumber else { return }

        if let minValueForKey = minMetricValues[key], minValueForKey != .notANumber {
            if value?.compare(minValueForKey) == .orderedAscending {
                minMetricValues[key] = value
            }
            if let maxValueForKey = maxMetricValues[key],
               value?.compare(maxValueForKey) == .orderedDescending {
                maxMetricValues[key] = value
            }
            
        } else { // minKeyValues[key] == nil or .notANumber
            // Fundamental bar scale should range from zero (or a negative report value) to max
            if (value?.compare(NSDecimalNumber.zero) == .orderedAscending) {
                minMetricValues[key] = value // negative value
            } else {
                minMetricValues[key] = NSDecimalNumber.zero
            }
            maxMetricValues[key] = value
        }
    }
    
    /// Returns notANumber if no values for key
    @objc func range(for key: String) -> NSDecimalNumber {
        if let maxValue = maxMetricValues[key],
           let minValue = minMetricValues[key] {
            return maxValue.subtracting(minValue)
        }
        return NSDecimalNumber.notANumber
    }
    
    @objc func min(for key: String) -> NSDecimalNumber? {
        return minMetricValues[key]
    }
    
    @objc func max(for key: String) -> NSDecimalNumber? {
        return maxMetricValues[key]
    }
    
    static func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }
    
    @objc func add(_ stock: Stock) {
        stockList.append(stock)
        saveToDb()
    }
    
    /// Insert or update this stock comparison
    @objc func saveToDb() {
        var db: sqlite3ptr = nil
        
        guard SQLITE_OK == sqlite3_open(Comparison.dbPath(), &db) else { return }
        var statement: sqlite3ptr = nil
        var sql = ""
        if id == 0 {
            sql = "INSERT INTO comparison (sort) VALUES (0)"
            guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
            id = Int(sqlite3_last_insert_rowid(db))
        }
        
        for stock in stockList {
            let hexColorUTF8     = NSString(string: stock.hexFromUpColor()).utf8String
            let fundamentalsUTF8 = NSString(string: stock.fundamentalList).utf8String
            let technicalsUTF8   = NSString(string: stock.technicalList).utf8String
            
            if stock.comparisonStockId > 0 {
                sql = "UPDATE comparisonStock SET chartType=?, color=?, fundamentals=?, technicals=? WHERE rowid=?"
                sqlite3_prepare(db, sql, -1, &statement, nil);
    
                sqlite3_bind_int64(statement, 1, Int64(stock.chartType.rawValue));
                sqlite3_bind_text(statement,  2, hexColorUTF8, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement,  3, fundamentalsUTF8, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(statement,  4, technicalsUTF8, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(statement, 5, Int64(stock.comparisonStockId));

                if SQLITE_DONE != sqlite3_step(statement) {
                    print("Save to DB ERROR ", String(cString: sqlite3_errmsg(db)), sql)
                }
                sqlite3_finalize(statement);
            } else if stock.comparisonStockId == 0 {
                sql = "INSERT OR REPLACE INTO comparisonStock (comparisonId, stockId, chartType, color, fundamentals, technicals) VALUES (?, ?, ?, ?, ?, ?)"
                sqlite3_prepare(db, sql, -1, &statement, nil);
                
                sqlite3_bind_int64(statement, 1, Int64(id));
                sqlite3_bind_int64(statement, 2, Int64(stock.id));
                sqlite3_bind_int64(statement, 3, Int64(stock.chartType.rawValue));
                sqlite3_bind_text(statement,  4, hexColorUTF8, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement,  5, fundamentalsUTF8, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(statement,  6, technicalsUTF8, -1, SQLITE_TRANSIENT);

                if SQLITE_DONE != sqlite3_step(statement) {
                    print("Save to DB ERROR ", String(cString: sqlite3_errmsg(db)), sql)
                }
                sqlite3_finalize(statement);
            }
        }
        sqlite3_close(db);
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
            print(String(format: "Delete from comparisonStock DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement);
        
        sql = "DELETE FROM comparison WHERE rowid = ?"
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
                
        sqlite3_bind_int64(statement, 1, Int64(id))
        
        if SQLITE_DONE != sqlite3_step(statement){
            print(String(format: "Delete from comparison DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement);
        sqlite3_close(db);        
    }
    
    /// Delete a single stock from this comparison
    @objc(deleteStock:) func delete(stock: Stock) {
        var db: sqlite3ptr = nil
        
        guard SQLITE_OK == sqlite3_open(Comparison.dbPath(), &db) else { return }
        var statement: sqlite3ptr = nil
        
        let sql = "DELETE FROM comparisonStock WHERE stockId = ?"
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
        
        sqlite3_bind_int64(statement, 1, Int64(stock.id))
        
        if SQLITE_DONE == sqlite3_step(statement){
            stockList.removeAll(where: {$0 == stock})
        } else {
            print(String(format: "delete(stock:) DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement);
        sqlite3_close(db);
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
        
        var comparison: Comparison? = nil
        var lastComparisonId = 0
        var title = ""
        
        while (SQLITE_ROW == sqlite3_step(statement)) {
            if lastComparisonId != sqlite3_column_int(statement, 0) {
                title = ""
                comparison = Comparison() // only need to create a new comparison after initial one
                lastComparisonId = Int(sqlite3_column_int(statement, 0))
                comparison?.id = lastComparisonId
                list.append(comparison!)
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
            
            comparison?.stockList.append(stock)
            comparison?.title = title
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
            
        return list
    }
    
}
