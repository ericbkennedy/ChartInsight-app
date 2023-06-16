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
    
}

