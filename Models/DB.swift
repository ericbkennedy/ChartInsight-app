//
//  DB.swift
//  ChartInsight
//
//  Interface for sqlite3 DB
//
//  Created by Eric Kennedy on 6/2/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class DB: NSObject {
    typealias sqlite3ptr = OpaquePointer?
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // Update local db for stock splits (delete from history), ticker changes and delistings
    func updateFromAPI(delegate: RootViewController) -> Void {
         
        let session = URLSession(configuration: .default)

        // TODO create real API
        guard let url = URL(string: "https://chartinsight.com/api/close/STR?token=test") else {
            print("Invalid API url for updates")
            return
        }

        session.dataTask(with: url) {(data, response, error) in
            if let error = error {
                print("error is \(error.localizedDescription)")
                return
            }

            guard let data = data else { // No data returned so no updates to process
                return
            }

            do {
                let updates = try JSONDecoder().decode([[Double]].self, from:data)
                print(updates)

                DispatchQueue.main.async {
                    delegate.reloadWhenVisible()
                }
            } catch (let decodingError) {
                print(decodingError)
            }
        }.resume()
    }
    
    func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }
    
    @objc(moveDBToDocumentsForDelegate:)
    func moveDBToDocuments(delegate: RootViewController) -> Void {
        
        guard let path = Bundle.main.path(forResource:"charts.db", ofType:nil) else {
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
            delegate.dbMoved(destinationPath)
            
          //  updateFromAPI(delegate: delegate)
            
        } catch let error as NSError {
            print("DBUpdater Error: \(error.domain) \(error.description)")
        }
    }
    
    func save(_ barDataArray: [BarData], stockId: Int) {
        var db: sqlite3ptr = nil
        var statement: sqlite3ptr = nil
        
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

        var db: sqlite3ptr = nil
        var statement: sqlite3ptr = nil
        
        guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return rowsLoaded }
       
        let sql = "SELECT SUBSTR(date,1,4), SUBSTR(date,5,2), SUBSTR(date,7,2), open, high, low, close, adjClose, volume from history WHERE stockId=? and date >= ? ORDER BY date DESC"
        
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return rowsLoaded }
        sqlite3_bind_int64(statement, 1, Int64(stockId))
        sqlite3_bind_int64(statement, 2, Int64(startDateInt))
        
        while (SQLITE_ROW == sqlite3_step(statement)) {
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
        return rowsLoaded
    }
    
    /// Split the user's search text into words and calls findSymbol(search:db:) to query for matches
     func findStock(search: String) -> [Stock] {
         var list: [Stock] = []
         var exactMatches: [Stock] = []
         var db: sqlite3ptr = nil
         
         guard SQLITE_OK == sqlite3_open(dbPath(), &db) else { return list }
       
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
         
         if (list.count == 0) { // Add placeholder
             let stock = Stock()
             stock.symbol = ""
             stock.name = "No matches with supported fundamentals"
             list.append(stock)
         }
         return list
     }
    
    /// Search db for term which can be both the user's full search text or a substring of it.
    /// findStock(search:) wraps this method in order to split the user's search text into words if no exact matches occur.
    private func stockSearch(term: String, db: sqlite3ptr) -> [Stock] {
        var list: [Stock] = []
        var statement: sqlite3ptr = nil
        
        let sql = "SELECT rowid,symbol,name,startDate,hasFundamentals,offsets(stock) FROM stock WHERE stock MATCH ? ORDER BY offsets(stock) ASC LIMIT 50"
       
        guard SQLITE_OK == sqlite3_prepare_v2(db, sql, -1, &statement, nil) else { return list }
        
        let wildcardSearch = NSString(string: "\(term)*")
        
        sqlite3_bind_text(statement, 1, wildcardSearch.utf8String, -1, SQLITE_TRANSIENT)
        
        while (SQLITE_ROW == sqlite3_step(statement)) {
            let stock = Stock()
            stock.id = Int(sqlite3_column_int(statement, 0))
            
            stock.symbol = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(1))))
            stock.name = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(2))))
            // Faster search results UI if string to date conversion happens after user selects the stock
            stock.startDateString = String(cString: UnsafePointer(sqlite3_column_text(statement, Int32(3))))
            
            stock.hasFundamentals = Int(sqlite3_column_int(statement, Int32(4)))
            if (stock.hasFundamentals != 2) { // Banks aren't supported and ETFs don't report XML financials
                stock.fundamentalList = "";
            }
            list.append(stock)
        }
        sqlite3_finalize(statement)
        return list
    }
}

