//
//  Comparison.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

final class Comparison {

    public var id: Int = 0
    public var stockList: [Stock] = []
    public var title: String = ""
    public var minMetricValues: [String: NSDecimalNumber] = [:]
    public var maxMetricValues: [String: NSDecimalNumber] = [:]

    /// Union of all metric keys for stocks in this comparison set
    public func sparklineKeys() -> [String] {
        var fundamentalKeys = ""

        for stock in stockList {
            fundamentalKeys = fundamentalKeys.appending(stock.fundamentalList)
        }

        var sortedMetrics: [String] = []

        for category in Metrics.shared.metrics {
            for metric in category where metric.count > 0 {
                let metricKey = String(metric[0])
                if fundamentalKeys.contains(metricKey) {
                    sortedMetrics.append(metricKey)
                }
            }
        }
        return sortedMetrics
    }

    public func resetMinMax() {
        minMetricValues.removeAll(keepingCapacity: true)
        maxMetricValues.removeAll(keepingCapacity: true)
    }

    /// Determine min and max values for fundamental metric key
    public func updateMinMax(for key: String, value: NSDecimalNumber?) {
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
            if value?.compare(NSDecimalNumber.zero) == .orderedAscending {
                minMetricValues[key] = value // negative value
            } else {
                minMetricValues[key] = NSDecimalNumber.zero
            }
            maxMetricValues[key] = value
        }
    }

    /// Determines range from the maxValue to zero or minValue, whichever yields the bigger range. Returns notANumber if no values for key
    public func range(for key: String) -> NSDecimalNumber {
        if let maxValue = maxMetricValues[key],
           let minValue = minMetricValues[key] {
            if maxValue.compare(NSDecimalNumber.zero) == .orderedDescending {
                if minValue.compare(NSDecimalNumber.zero) == .orderedDescending {
                    // both positive, but extend range to zero for clarity
                    return maxValue.subtracting(NSDecimalNumber.zero)
                } else { // extend range to negative minValue
                    return maxValue.subtracting(minValue)
                }
            } else {
                // when all values are negative, range is from zero to minValue
                return NSDecimalNumber.zero.subtracting(minValue)
            }
        }
        return NSDecimalNumber.notANumber
    }

    public func min(for key: String) -> NSDecimalNumber? {
        return minMetricValues[key]
    }

    public func max(for key: String) -> NSDecimalNumber? {
        return maxMetricValues[key]
    }

    private static func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }

    /// Insert or update this stock comparison.
    /// Returns updated list of all stock comparisons
    public func saveToDb() async -> ([Comparison], Int) {
        let (updatedList, insertedComparisonStockId) = await DBActor.shared.save(comparison: self)
        return (updatedList, insertedComparisonStockId)
    }

    /// Deletes comparison row and all comparisonStock rows.
    /// Returns updated list of all stock comparisons
    public func deleteFromDb() async -> [Comparison] {
        let updatedList = await DBActor.shared.delete(comparison: self)
        return updatedList
    }

    /// Delete a single stock from this comparison
    /// Returns updated list of all stock comparisons
    public func delete(stock: Stock) async -> [Comparison] {
        let updatedList: [Comparison]
        if stockList.count > 0 {
            stockList.removeAll(where: {$0.comparisonStockId == stock.comparisonStockId})
            updatedList = await DBActor.shared.delete(stock: stock)
        } else {
            updatedList = await deleteFromDb()
        }
        return updatedList
    }

}
