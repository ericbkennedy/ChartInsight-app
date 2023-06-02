//
//  DBUpdater.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/2/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class DBUpdater : NSObject {
    
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
            
            // TODO: check API for stock splits, ticker changes and new stocks
            
        } catch let error as NSError {
            print("DBUpdater Error: \(error.domain) \(error.description)")
        }
    }
}

