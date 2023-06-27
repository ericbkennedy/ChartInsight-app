//
//  Comparison.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class Comparison: NSObject {
    
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
        
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
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
        Task {
            await DBActor.shared.save(comparison: self)
        }
    }
    
    /// Deletes comparison row and all comparisonStock rows
    @objc func deleteFromDb() {
        Task {
            await DBActor.shared.delete(comparison: self)
        }
    }
    
    /// Delete a single stock from this comparison
    @objc(deleteStock:) func delete(stock: Stock) {
        Task {
            if (await DBActor.shared.delete(stock: stock)) {
                stockList.removeAll(where: {$0 == stock})
            }
        }
    }
    
    @objc static func listAll() async -> [Comparison] {
        return await DBActor.shared.comparisonList()
    }
    
}