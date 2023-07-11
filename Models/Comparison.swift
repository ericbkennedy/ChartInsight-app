//
//  Comparison.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class Comparison {

    var id: Int = 0
    var stockList: [Stock] = []
    var title: String = ""
    var minMetricValues: [String: NSDecimalNumber] = [:]
    var maxMetricValues: [String: NSDecimalNumber] = [:]

    /// Union of all metric keys for stocks in this comparison set
    func sparklineKeys() -> [String] {
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

    func resetMinMax() {
        minMetricValues.removeAll(keepingCapacity: true)
        maxMetricValues.removeAll(keepingCapacity: true)
    }

    /// Determine min and max values for fundamental metric key
    func updateMinMax(for key: String, value: NSDecimalNumber?) {
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
    func range(for key: String) -> NSDecimalNumber {
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

    func min(for key: String) -> NSDecimalNumber? {
        return minMetricValues[key]
    }

    func max(for key: String) -> NSDecimalNumber? {
        return maxMetricValues[key]
    }

    static func dbPath() -> String {
        return String(format: "%@/Documents/charts.db", NSHomeDirectory())
    }

    /// Insert or update this stock comparison.
    /// Returns updated list of all stock comparisons
    func saveToDb() async -> [Comparison] {
        let updatedList = await DBActor.shared.save(comparison: self)
        return updatedList
    }

    /// Deletes comparison row and all comparisonStock rows.
    /// Returns updated list of all stock comparisons
    func deleteFromDb() async -> [Comparison] {
        let updatedList = await DBActor.shared.delete(comparison: self)
        return updatedList
    }

    /// Delete a single stock from this comparison
    /// Returns updated list of all stock comparisons
    func delete(stock: Stock) async -> [Comparison] {
        let updatedList: [Comparison]
        if stockList.count > 0 {
            stockList.removeAll(where: {$0 == stock})
            updatedList = await DBActor.shared.delete(stock: stock)
        } else {
            updatedList = await deleteFromDb()
        }
        return updatedList
    }

}
