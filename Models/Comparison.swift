//
//  Comparison.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

import CoreData

@objc(Comparison)
public final class Comparison: NSManagedObject {

    @NSManaged public var title: String
    @NSManaged public var created: Date
    @NSManaged public var stockSet: NSOrderedSet?
    public var minMetricValues: [String: NSDecimalNumber] = [:]
    public var maxMetricValues: [String: NSDecimalNumber] = [:]

    public override func awakeFromInsert() {
        created = Date()
    }

    /// Union of all metric keys for stocks in this comparison set
    public func sparklineKeys() -> [String] {
        guard let stockSet else { return [] }
        var fundamentalKeys = ""

        for case let stock as ComparisonStock in stockSet {
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

    /// Delete a single stock from this comparison
    /// Returns updated list of all stock comparisons
    public func delete(stock: ComparisonStock) async -> [Comparison] {
        var updatedList = [Comparison]()
        if let stockSet, let managedObjectContext {
            do {
                if stockSet.count > 0 {
                    for case let comparisonStock as ComparisonStock in stockSet where comparisonStock.stockId == stock.stockId {
                        removeFromStockSet(comparisonStock)
                    }
                    title = title.replacingOccurrences(of: stock.ticker, with: "").trimmingCharacters(in: .whitespaces)
                    try managedObjectContext.save()
                } else {
                    managedObjectContext.delete(self)
                }
                updatedList = Comparison.fetchAll()
            } catch {
                print("Error while removing comparisonStock from comparison: \(error)")
            }
        }
        return updatedList
    }
}

// MARK: CoreData methods
extension Comparison: Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Comparison> {
        return NSFetchRequest<Comparison>(entityName: "Comparison")
    }

    public class func fetchAll() -> [Comparison] {
        var list = [Comparison]()
        let request = Comparison.fetchRequest()
        let sort = NSSortDescriptor(key: "created", ascending: true)
        request.sortDescriptors = [sort]
        if let results = try? CoreDataStack.shared.container.viewContext.fetch(request), results.isEmpty == false {
            list.append(contentsOf: results)
        }
        return list
    }

    /// Called by DB Actor if stock changes affected history rows indicating a watchlist stock had a stock change
    internal class func fetchAllAfterStockChanges(_ stockChanges: [StockChangeService.StockChange]) -> [Comparison] {
        for change in stockChanges {
            switch change.action {
            case .tickerChange, .nameChange:
                print("TODO: Update the comparisonStock object and comparison.title for \(change.ticker)")
            case .delisted:
                print("TODO: Remove delisted \(change.ticker) from comparisonStock and comparison.title")
            case .added, .split:
                break // Won't affect comparisonStock entries
            }
        }
        return Comparison.fetchAll()
    }

    public class func findExisting(ticker: String) -> Comparison? {
        let list = Comparison.fetchAll()

        for comparison in list {
            if let stockSet = comparison.stockSet {
                for case let comparisonStock as ComparisonStock in stockSet where comparisonStock.ticker == ticker {
                    return comparison
                }
            }
        }
        return nil
    }

    public class func addSampleData(context: NSManagedObjectContext) {
        let stocks = [1: "AAPL", 2: "MSFT", 3: "AMZN"]

        for (stockId, ticker) in stocks {
            let comparison = Comparison(context: context)
            comparison.title = ticker
            let comparisonStock = ComparisonStock(context: context)
            comparisonStock.stockId = Int64(stockId)
            comparisonStock.ticker = ticker
            comparison.addToStockSet(comparisonStock)
            comparisonStock.comparison = comparison
        }
        CoreDataStack.shared.save()
    }

    @objc(addStockSetObject:)
    @NSManaged public func addToStockSet(_ value: ComparisonStock)

    @objc(removeStockSetObject:)
    @NSManaged public func removeFromStockSet(_ value: ComparisonStock)
}
