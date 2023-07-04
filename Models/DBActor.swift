//
//  DBActor.swift
//  ChartInsight
//
//  Interface for sqlite3 DB
//
//  Created by Eric Kennedy on 6/2/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//
// allow db variable name
// swiftlint:disable identifier_name

import Foundation

@globalActor actor DBActor {
    static let shared = DBActor()

    typealias Sqlite3ptr = OpaquePointer?
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let READONLY_NOMUTEX = Int32(SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)

    // Update local db for stock splits (delete from history), ticker changes and delistings
    func updateFromAPI(delegate: WatchlistViewController) async {

        // EK create real API
        guard let url = URL(string: "https://chartinsight.com/api/close/STR?token=test") else {
            print("Invalid API url for updates")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.network(reason: "Response to \(url) wasn't expected HTTPURLResponse")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.http(statusCode: httpResponse.statusCode)
            }

            print(String(data: data, encoding: .utf8) ?? "")

        } catch {
            print("error is \(error.localizedDescription)")
        }
    }

    func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }

    func update(delegate: WatchlistViewController) async {

        guard let path = Bundle.main.path(forResource: "charts.db", ofType: nil) else {
            print("charts.db is missing from Bundle")
            return
        }

        let fileManager = FileManager.default
        let destinationPath = dbPath()
        do {
            if fileManager.fileExists(atPath: dbPath()) == false {
                let fromURL = URL(fileURLWithPath: path)
                let toURL = URL(fileURLWithPath: destinationPath)
                try fileManager.copyItem(at: fromURL, to: toURL)
            }

            let list = comparisonList()
            await MainActor.run {
                delegate.update(list: list)
            }
            // Check for stock splits and ticker updates after UI has rendered
            // await updateFromAPI(delegate: delegate)

        } catch let error as NSError {
            print("DBUpdater Error: \(error.domain) \(error.description)")
        }
    }

    func save(_ barDataArray: [BarData], stockId: Int) {
        var db: Sqlite3ptr = nil
        var statement: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return }

        let sql = "INSERT OR IGNORE INTO history (stockId, date, open, high, low, close, adjClose, volume) values (?, ?, ?, ?, ?, ?, ?, ?)"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }

        for barData in barDataArray {
            let dateInt = barData.dateIntFromBar()
            sqlite3_bind_int64(statement, 1, Int64(stockId))
            sqlite3_bind_int64(statement, 2, Int64(dateInt))
            sqlite3_bind_double(statement, 3, barData.open)
            sqlite3_bind_double(statement, 4, barData.high)
            sqlite3_bind_double(statement, 5, barData.low)
            sqlite3_bind_double(statement, 6, barData.close)
            sqlite3_bind_double(statement, 7, barData.adjClose)
            sqlite3_bind_int64(statement, 8, Int64(barData.volume))

            if SQLITE_DONE != sqlite3_step(statement) {
                print("Save to DB ERROR ", String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
    }

    func loadBarData(for stockId: Int, startDateInt: Int) -> [BarData] {
        var rowsLoaded: [BarData] = []

        var db: Sqlite3ptr = nil
        var statement: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return [] }

        var sql = "SELECT SUBSTR(date,1,4), SUBSTR(date,5,2), SUBSTR(date,7,2), open, high, low, close, adjClose, volume"
        sql += " FROM history WHERE stockId=? and date >= ? ORDER BY date DESC"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return rowsLoaded }
        sqlite3_bind_int64(statement, 1, Int64(stockId))
        sqlite3_bind_int64(statement, 2, Int64(startDateInt))

        while SQLITE_ROW == sqlite3_step(statement) {
            let newBar = BarData()
            newBar.year = Int(sqlite3_column_int64(statement, 0))
            newBar.month = Int(sqlite3_column_int64(statement, 1))
            newBar.day = Int(sqlite3_column_int64(statement, 2))
            newBar.open = sqlite3_column_double(statement, 3)
            newBar.high = sqlite3_column_double(statement, 4)
            newBar.low = sqlite3_column_double(statement, 5)
            newBar.close = sqlite3_column_double(statement, 6)
            newBar.adjClose = sqlite3_column_double(statement, 7)
            newBar.volume = Double(sqlite3_column_int64(statement, 8))

            rowsLoaded.append(newBar)
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
        return rowsLoaded
    }

    /// Split the user's search text into words and calls findSymbol(search:db:) to query for matches
    func findStock(search: String) -> [Stock] {
         var list: [Stock] = []
         var exactMatches: [Stock] = []
         var db: Sqlite3ptr = nil

         guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return [] }

         list += stockSearch(term: search, db: db)

         if list.isEmpty { // split into separate searches
             for var term in search.components(separatedBy: " ") {
                 if term.isEmpty { continue }
                 var isMiddleTerm = false
                 if search.contains("\(term) ") {
                     // ends with a space so add a space for word endings
                     term += " "
                     isMiddleTerm = true
                 }
                 let termMatches = stockSearch(term: term, db: db)

                 list.removeAll(keepingCapacity: true)
                 list += termMatches

                 if termMatches.count > 0 {
                     if termMatches.count == 1 || isMiddleTerm {
                         exactMatches.append(termMatches[0])
                     }
                 } else if exactMatches.count > 0 {
                     list += exactMatches
                 }
             }
         }
         sqlite3_close(db)

         if list.count == 0 { // Add placeholder
             let stock = Stock()
             stock.ticker = ""
             stock.name = "No matches with supported fundamentals"
             list.append(stock)
         }
         return list
     }

    /// Search db for term which can be both the user's full search text or a substring of it.
    /// findStock(search:) wraps this in order to split the user's search text into words if no exact matches occur.
    private func stockSearch(term: String, db: Sqlite3ptr) -> [Stock] {
        var list: [Stock] = []
        var statement: Sqlite3ptr = nil

        var sql = "SELECT rowid,ticker,name,startDate,hasFundamentals,offsets(stock)"
        sql += " FROM stock WHERE stock MATCH ? ORDER BY offsets(stock) ASC LIMIT 50"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return list }

        let wildcardSearch = NSString(string: "\(term)*")

        sqlite3_bind_text(statement, 1, wildcardSearch.utf8String, -1, SQLITE_TRANSIENT)

        while SQLITE_ROW == sqlite3_step(statement) {
            let stock = Stock()
            stock.id = Int(sqlite3_column_int(statement, 0))

            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(1))))
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(2))))
            // Faster search results UI if string to date conversion happens after user selects the stock
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(3))))

            stock.hasFundamentals = 0 < Int(sqlite3_column_int(statement, Int32(4)))
            if stock.hasFundamentals == false { // Banks aren't supported and ETFs don't report XML financials
                stock.fundamentalList = ""
            }
            list.append(stock)
        }
        sqlite3_finalize(statement)
        return list
    }

    /// Returns a stock with the provided ticker or nil if not found
    func getStock(ticker: String) -> Stock? {
        var db: Sqlite3ptr = nil
        var statement: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return nil }

        let sql = "SELECT rowid,ticker,name,startDate,hasFundamentals FROM stock WHERE ticker=?"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return nil }

        sqlite3_bind_text(statement, 1, NSString(string: ticker).utf8String, -1, SQLITE_TRANSIENT)

        if SQLITE_ROW == sqlite3_step(statement) {
            let stock = Stock()
            stock.id = Int(sqlite3_column_int(statement, 0))

            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(1))))
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(2))))
            // Faster search results UI if string to date conversion happens after user selects the stock
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(3))))

            stock.hasFundamentals = 0 < Int(sqlite3_column_int(statement, Int32(4)))
            if stock.hasFundamentals == false { // Banks aren't supported and ETFs don't report XML financials
                stock.fundamentalList = ""
            }
            sqlite3_finalize(statement)
            sqlite3_close(db)
            return stock
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
        return nil
    }

    /// Save a stock as part of a new comparison (if comparison.id == 0) or add to an existing comparison
    func save(comparison: Comparison) {
        var db: Sqlite3ptr = nil
        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return }
        var statement: Sqlite3ptr = nil
        var sql = ""
        if comparison.id == 0 {
            sql = "INSERT INTO comparison (sort) VALUES (0)"
            guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
            comparison.id = Int(sqlite3_last_insert_rowid(db))
        }

        for stock in comparison.stockList {
           let hexColorUTF8     = NSString(string: stock.hexFromUpColor()).utf8String
           let fundamentalsUTF8 = NSString(string: stock.fundamentalList).utf8String
           let technicalsUTF8   = NSString(string: stock.technicalList).utf8String

           if stock.comparisonStockId > 0 {
               sql = "UPDATE comparisonStock SET chartType=?, color=?, fundamentals=?, technicals=? WHERE rowid=?"
               sqlite3_prepare(db, sql, -1, &statement, nil)

               sqlite3_bind_int64(statement, 1, Int64(stock.chartType.rawValue))
               sqlite3_bind_text(statement, 2, hexColorUTF8, -1, SQLITE_TRANSIENT)
               sqlite3_bind_text(statement, 3, fundamentalsUTF8, -1, SQLITE_TRANSIENT)
               sqlite3_bind_text(statement, 4, technicalsUTF8, -1, SQLITE_TRANSIENT)
               sqlite3_bind_int64(statement, 5, Int64(stock.comparisonStockId))

               if SQLITE_DONE != sqlite3_step(statement) {
                   print("Save to DB ERROR ", String(cString: sqlite3_errmsg(db)), sql)
               }
               sqlite3_finalize(statement)
           } else if stock.comparisonStockId == 0 {
               sql = "INSERT OR REPLACE INTO comparisonStock (comparisonId, stockId, chartType, color, fundamentals, technicals)"
               sql += " VALUES (?, ?, ?, ?, ?, ?)"
               sqlite3_prepare(db, sql, -1, &statement, nil)

               sqlite3_bind_int64(statement, 1, Int64(comparison.id))
               sqlite3_bind_int64(statement, 2, Int64(stock.id))
               sqlite3_bind_int64(statement, 3, Int64(stock.chartType.rawValue))
               sqlite3_bind_text(statement, 4, hexColorUTF8, -1, SQLITE_TRANSIENT)
               sqlite3_bind_text(statement, 5, fundamentalsUTF8, -1, SQLITE_TRANSIENT)
               sqlite3_bind_text(statement, 6, technicalsUTF8, -1, SQLITE_TRANSIENT)

               if SQLITE_DONE == sqlite3_step(statement) {
                   stock.comparisonStockId = Int(sqlite3_last_insert_rowid(db))
               } else {
                   print("Save to DB ERROR ", String(cString: sqlite3_errmsg(db)), sql)
               }
               sqlite3_finalize(statement)
           }
       }
       sqlite3_close(db)
    }

    /// Delete all stock from a comparison and the comparison row itself
    func delete(comparison: Comparison) {
        var db: Sqlite3ptr = nil
        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return }
        var statement: Sqlite3ptr = nil

        var sql = "DELETE FROM comparisonStock WHERE comparisonId = ?"
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }

        sqlite3_bind_int64(statement, 1, Int64(comparison.id))

        if SQLITE_DONE != sqlite3_step(statement) {
            print(String(format: "Delete from comparisonStock DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)

        sql = "DELETE FROM comparison WHERE rowid = ?"
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }

        sqlite3_bind_int64(statement, 1, Int64(comparison.id))

        if SQLITE_DONE != sqlite3_step(statement) {
            print(String(format: "Delete from comparison DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)

    }

    /// Delete stock from a comparison. Call delete(comparison:) to delete the last stock in a comparison
    func delete(stock: Stock) -> Bool {
        var db: Sqlite3ptr = nil
        var isDeleted = false

        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return false }
        var statement: Sqlite3ptr = nil

        let sql = "DELETE FROM comparisonStock WHERE stockId = ?"
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return false }

        sqlite3_bind_int64(statement, 1, Int64(stock.id))

        if SQLITE_DONE == sqlite3_step(statement) {
            isDeleted = true
        } else {
            print(String(format: "delete(stock:) DB ERROR '%s'.", sqlite3_errmsg(db)))
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
        return isDeleted
    }

    /// Load all comparisons or only those with the provided ticker
    func comparisonList(ticker: String = "") -> [Comparison] {
        var list: [Comparison] = []
        var db: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return [] }
        var statement: Sqlite3ptr = nil

        enum Col: Int32 {
            case comparisonId
            case comparisonStockId
            case stockId
            case ticker
            case startDate
            case hasFundamentals
            case chartType
            case color
            case fundamentalList
            case technicalList
        }
        var sql = "SELECT K.rowid, CS.rowid, stockId, ticker, startDate, hasFundamentals, chartType, color, fundamentals, technicals"
        sql += " FROM comparison K JOIN comparisonStock CS on K.rowid = CS.comparisonId JOIN stock ON stock.rowid = stockId "

        if ticker.count > 0 {
            sql += " WHERE stock.ticker = ? "
        }
        sql += " ORDER BY K.rowid, CS.rowId"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return list }

        if ticker.count > 0 {
            sqlite3_bind_text(statement, 1, NSString(string: ticker).utf8String, -1, SQLITE_TRANSIENT)
        }

        var comparison: Comparison?
        var lastComparisonId = 0
        var title = ""

        while SQLITE_ROW == sqlite3_step(statement) {
            if lastComparisonId != sqlite3_column_int(statement, 0) {
                title = ""
                comparison = Comparison() // only need to create a new comparison after initial one
                lastComparisonId = Int(sqlite3_column_int(statement, 0))
                comparison?.id = lastComparisonId
                list.append(comparison!)
            }
            let stock = Stock()
            stock.comparisonStockId = Int(sqlite3_column_int(statement, Col.comparisonStockId.rawValue))
            stock.id = Int(sqlite3_column_int(statement, Col.stockId.rawValue))
            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.ticker.rawValue)))
            title = title.appending("\(stock.ticker) ")
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.startDate.rawValue)))
            // startDateString will be converted to NSDate by [StockData init] as price data is loaded

            stock.hasFundamentals = 0 < sqlite3_column_int(statement, Col.hasFundamentals.rawValue)
            if let chartType = ChartType(rawValue: Int(sqlite3_column_int(statement, Col.chartType.rawValue))) {
                stock.chartType = chartType
            }

            let hexString = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.color.rawValue)))

            if hexString != "" {
                stock.setColorWith(hexString: hexString)
            } else {
                stock.setColorWith(hexString: "009900") // upColor = green, down = red
            }

            if sqlite3_column_bytes(statement, Col.fundamentalList.rawValue) > 2 {
                stock.fundamentalList = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.fundamentalList.rawValue)))
            }

            if sqlite3_column_bytes(statement, Col.technicalList.rawValue) > 2 {
                stock.technicalList = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.technicalList.rawValue)))
            }

            comparison?.stockList.append(stock)
            comparison?.title = title
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)

        return list
    }
}
// swiftlint:enable identifier_name
