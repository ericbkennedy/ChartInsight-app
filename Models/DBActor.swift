//
//  DBActor.swift
//  ChartInsight
//
//  Interface for sqlite3 DB
//
//  Created by Eric Kennedy on 6/2/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import Foundation

protocol DBActorDelegate: AnyObject {
    @MainActor func update(list newList: [Comparison], reloadComparison: Bool)
}

@globalActor actor DBActor {
    static let shared = DBActor()

    typealias Sqlite3ptr = OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let READONLY_NOMUTEX = Int32(SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)

    private func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }

    /// Ensure DB is in Documents directory. If toManagedContext != nil, load list and call delegate?.update(list:reloadComparison:)
    public func moveIfNeeded(delegate: DBActorDelegate, toManagedContext: NSManagedObjectContext? = nil) async {
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
            if let toManagedContext {
                await migrateComparisonList(toManagedContext, for: delegate)
            }
        } catch let error as NSError {
            print("DBUpdater Error: \(error.domain) \(error.description)")
        }
    }

    /// Update DB with the provided array of stock changes (splits, IPOs, ticker changes and delistings)
    public func update(stockChanges: [StockChangeService.StockChange], delegate: DBActorDelegate) async {
        var db: Sqlite3ptr = nil, statement: Sqlite3ptr = nil
        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return }
        var userRowsChanged = 0 // if stockChanges require deleting user data, send new comparisonList to delegate

        for change in stockChanges {
            switch change.action {
            case .added:
                if let name = change.name, let startDateInt = change.startDateInt, let hasFundamentals = change.hasFundamentals {
                    let sql = "INSERT OR REPLACE INTO stock (stockId, ticker, name, startDate, hasFundamentals) VALUES (?, ?, ?, ?, ?)"
                    guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { continue }
                    sqlite3_bind_int64(statement, 1, Int64(change.stockId))
                    sqlite3_bind_text(statement, 2, NSString(string: change.ticker).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, NSString(string: name).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(statement, 4, Int64(startDateInt))
                    sqlite3_bind_int64(statement, 5, Int64(hasFundamentals))

                    if SQLITE_DONE != sqlite3_step(statement) {
                        print("change.added DB ERROR ", String(cString: sqlite3_errmsg(db)))
                    }
                    sqlite3_finalize(statement)
                }
            case .tickerChange, .nameChange:
                if let name = change.name, let startDateInt = change.startDateInt {
                    let sql = "UPDATE stock SET ticker = ?, name = ?, startDate = ? WHERE stockId = ?"
                    guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { continue }
                    sqlite3_bind_text(statement, 1, NSString(string: change.ticker).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, NSString(string: name).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(statement, 3, Int64(startDateInt))
                    sqlite3_bind_int64(statement, 4, Int64(change.stockId))

                    if SQLITE_DONE != sqlite3_step(statement) {
                        print("change.tickerChange DB ERROR ", String(cString: sqlite3_errmsg(db)))
                    }
                    sqlite3_finalize(statement)
                }
            case .split:
                let sql = "DELETE FROM history WHERE stockId = ?"
                var statement: Sqlite3ptr = nil
                guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { continue }
                sqlite3_bind_int64(statement, 1, Int64(change.stockId))

                if SQLITE_DONE != sqlite3_step(statement) {
                    print("change.split DB ERROR ", String(cString: sqlite3_errmsg(db)))
                }
                userRowsChanged += Int(sqlite3_changes(db))
                sqlite3_finalize(statement)
            case .delisted:
                let sql = "DELETE FROM stock WHERE stockId = ?"
                guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { continue }
                sqlite3_bind_int64(statement, 1, Int64(change.stockId))

                if SQLITE_DONE != sqlite3_step(statement) {
                    print(String(format: "change.delisted stock DB ERROR '%s'.", sqlite3_errmsg(db)))
                }
                userRowsChanged += Int(sqlite3_changes(db))
                sqlite3_finalize(statement)
            }
        }
        if userRowsChanged > 0 {
            // fetch updated comparisonList and send it to the delegate
            let list = Comparison.fetchAllAfterStockChanges(stockChanges)
            await MainActor.run {
                delegate.update(list: list, reloadComparison: true)
            }
        } else {
            sqlite3_close(db)
        }
    }

    public func save(_ barDataArray: [BarData], stockId: Int64) {
        var db: Sqlite3ptr = nil, statement: Sqlite3ptr = nil

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

    public func loadBarData(for stockId: Int64, startDateInt: Int) -> [BarData] {
        var rowsLoaded: [BarData] = []

        var db: Sqlite3ptr = nil, statement: Sqlite3ptr = nil

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
    /// Search performance was slow due to actor isolation with writes to the history table.
    public func findStock(search: String) -> [Stock] {
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
             var stock = Stock()
             stock.ticker = ""
             stock.name = AccessibilityId.AddStock.noMatches
             list.append(stock)
         }
         return list
     }

    /// Search db for term which can be both the user's full search text or a substring of it.
    /// findStock(search:) wraps this in order to split the user's search text into words if no exact matches occur.
    private func stockSearch(term: String, db: Sqlite3ptr) -> [Stock] {
        var list: [Stock] = []
        var statement: Sqlite3ptr = nil

        var sql = "SELECT stockId,ticker,name,startDate,hasFundamentals,offsets(stock)"
        sql += " FROM stock WHERE stock MATCH ? ORDER BY offsets(stock) ASC LIMIT 50"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return list }

        let wildcardSearch = NSString(string: "\(term)*")

        sqlite3_bind_text(statement, 1, wildcardSearch.utf8String, -1, SQLITE_TRANSIENT)

        while SQLITE_ROW == sqlite3_step(statement) {
            var stock = Stock()
            stock.id = Int(sqlite3_column_int(statement, 0))

            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(1))))
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(2))))
            // Faster search results UI if string to date conversion happens after user selects the stock
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(3))))
            stock.hasFundamentals = 0 < Int(sqlite3_column_int(statement, Int32(4)))
            list.append(stock)
        }
        sqlite3_finalize(statement)
        return list
    }

    /// Returns a stock with the provided ticker or nil if not found
    public func getStock(ticker: String) -> Stock? {
        var db: Sqlite3ptr = nil, statement: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return nil }

        let sql = "SELECT stockId, ticker, name, startDate, hasFundamentals FROM stock WHERE ticker=?"

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return nil }

        sqlite3_bind_text(statement, 1, NSString(string: ticker).utf8String, -1, SQLITE_TRANSIENT)

        if SQLITE_ROW == sqlite3_step(statement) {
            var stock = Stock()
            stock.id = Int(sqlite3_column_int(statement, 0))

            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(1))))
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(2))))
            // Faster search results UI if string to date conversion happens after user selects the stock
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(3))))

            stock.hasFundamentals = 0 < Int(sqlite3_column_int(statement, Int32(4)))
            sqlite3_finalize(statement)
            sqlite3_close(db)
            return stock
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
        return nil
    }

    /// Creates NSManagedObjects to migrate comparison data from SQLite to CoreData
    public func migrateComparisonList(_ context: NSManagedObjectContext, for delegate: DBActorDelegate) async {
        var list: [Comparison] = []
        var db: Sqlite3ptr = nil, statement: Sqlite3ptr = nil

        guard SQLITE_OK == sqlite3_open_v2(dbPath(), &db, READONLY_NOMUTEX, nil) else { return }

        enum Col: Int32 {
            case comparisonId, stockId, ticker, name, startDate, hasFundamentals, chartType, color, fundamentalList, technicalList
        }
        let sql = """
        SELECT C.rowid, S.stockId, ticker, name, startDate, hasFundamentals, chartType, color, fundamentals, technicals
        FROM comparison C JOIN comparisonStock CS on C.rowid = CS.comparisonId JOIN stock S ON S.stockId = CS.stockId
        ORDER BY C.rowid, CS.rowId
        """

        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return }

        var comparison: Comparison?
        var lastComparisonId = 0
        var title = ""

        while SQLITE_ROW == sqlite3_step(statement) {
            if lastComparisonId != sqlite3_column_int(statement, 0) {
                title = ""
                comparison = Comparison(context: context) // only need to create a new comparison after initial one
                lastComparisonId = Int(sqlite3_column_int(statement, 0))
                list.append(comparison!)
            }
            let stock = ComparisonStock(context: context)
            stock.stockId = Int64(sqlite3_column_int(statement, Col.stockId.rawValue))
            stock.ticker = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.ticker.rawValue)))
            title = title.appending("\(stock.ticker) ")
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.name.rawValue)))
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.startDate.rawValue)))
            // startDateString will be converted to NSDate by [StockActor init] as price data is loaded
            stock.hasFundamentals = 0 < sqlite3_column_int(statement, Col.hasFundamentals.rawValue)
            stock.chartType = Int64(sqlite3_column_int(statement, Col.chartType.rawValue))

            let hexString = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.color.rawValue)))

            if hexString != "", let chartHexColor = ChartHexColor(rawValue: hexString) {
                stock.setColors(upHexColor: chartHexColor)
            } else {
                stock.setColors(upHexColor: .greenAndRed) // upColor = green, down = red
            }

            if stock.hasFundamentals && sqlite3_column_bytes(statement, Col.fundamentalList.rawValue) > 2 {
                stock.fundamentalList = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.fundamentalList.rawValue)))
            } else {
                stock.fundamentalList = "" // Clear out default vaulue for fundamentalList
            }

            if sqlite3_column_bytes(statement, Col.technicalList.rawValue) > 2 {
                stock.technicalList = String(cString: UnsafePointer(sqlite3_column_text(statement, Col.technicalList.rawValue)))
            }

            comparison?.addToStockSet(stock)
            comparison?.title = title
        }
        sqlite3_finalize(statement)
        sqlite3_close(db)
        await delegate.update(list: list, reloadComparison: true)
    }
}
