//
//  DBUpdater.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/2/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class DBUpdater : NSObject {
    
    // Update local db for stock splits (delete from history), ticker changes and delistings
    func updateFromAPI(delegate: RootViewController) -> Void {
         
        let session = URLSession(configuration: .default)

        // TODO create real API
        guard let url = URL(string: "https://chartinsight.com/api/close/STR?token=test") else {
            print("Invalid API url for updates")
            return;
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
    
    @objc(moveDBToDocumentsForDelegate:)
    func moveDBToDocuments(delegate: RootViewController) -> Void {
        
        guard let path = Bundle.main.path(forResource:"charts.db", ofType:nil) else {
            print("charts.db is missing from Bundle")
            return
        }
        
        let fileManager = FileManager.default
        let destinationPath = String(format: "%@/Documents/charts.db", NSHomeDirectory())
        do {
            if fileManager.fileExists(atPath: destinationPath) == false {
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
}

