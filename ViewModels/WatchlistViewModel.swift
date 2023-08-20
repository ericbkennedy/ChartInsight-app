//
//  WatchlistViewModel.swift
//  ChartInsight
//
//  Root ViewModel which receives the list of stock comparisons from the DBActor
//  and tells the ScrollChartViewModel which comparison to load.
//
//  Created by Eric Kennedy on 8/13/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import Foundation

protocol ChartOptionsDelegate: AnyObject {
    func delete(comparison: Comparison)
    func deleteStock(_ stock: ComparisonStock)
    func load(comparisonToChart: Comparison)
    func insert(stock: Stock, isNewComparison: Bool)
    func redraw(stock: ComparisonStock) async
    func reload(stock: ComparisonStock) async
    func dismissPopover()
}

@MainActor final class WatchlistViewModel {
    private (set) var scrollChartViewModel: ScrollChartViewModel!
    private (set) var container: NSPersistentContainer!

    // Closures to bind View to ViewModel
    public var didBeginRequest: (@MainActor (Comparison) -> Void)?
    public var didDismiss: (@MainActor () -> Void)?
    public var didUpdate: (@MainActor (_ selectedIndex: Int) -> Void)?

    public var listCount: Int { list.count }
    private var list: [Comparison] = []

    init(container: NSPersistentContainer, scrollChartViewModel: ScrollChartViewModel) {
        self.container = container
        self.scrollChartViewModel = scrollChartViewModel
        list = Comparison.fetchAll()
        if list.isEmpty {
            Comparison.addSampleData(context: container.viewContext)
            list = Comparison.fetchAll()
        }
        // Wait to call update(list:reloadComparison:) until views have finished loading and have nonzero dimensions
    }

    public func didSelectRow(at index: Int) {
        loadComparison(listIndex: index)
    }

    /// Called when app first loads (with listIndex == 0) or when user taps a tableView row
    public func loadComparison(listIndex: Int) {
        guard list.count > listIndex else { return }
        let comparison = list[listIndex]
        didBeginRequest?(comparison) // Updates the title immediately
        Task {
            await scrollChartViewModel.updateComparison(newComparison: comparison)
            didUpdate?(listIndex)
        }
    }

    public func title(for row: Int) -> String {
        guard list.count > row else { return "" }
        return list[row].title
    }

    /// Called when the user deletes a comparison from the SettingsViewController
    public func delete(at index: Int) {
        guard list.count > index else { return }
        delete(comparison: list[index])
    }

    /// Delete a comparison. CoreData will handle cascading delete for comparisonStock entries
    public func delete(comparison: Comparison) {
        let isCurrentComparison = scrollChartViewModel.comparison == comparison

        container.viewContext.delete(comparison)
        update(list: Comparison.fetchAll(), reloadComparison: isCurrentComparison)
    }
}

extension WatchlistViewModel: DBActorDelegate {
    /// Callback after async comparisonList reload and by StockChangeService if user rows were updated
    public func update(list newList: [Comparison], reloadComparison: Bool) {
        var selectedIndex = 0
        if let currentComparison = scrollChartViewModel.comparison, !newList.isEmpty {
            for (index, comparison) in newList.enumerated() where comparison.id == currentComparison.id {
                selectedIndex = index
            }
        }
        self.list = newList
        didUpdate?(selectedIndex)
        if reloadComparison { // When the chart color changes, need to update the list silently
            if self.list.count > selectedIndex {
                loadComparison(listIndex: selectedIndex)
            }
        }
    }
}

extension WatchlistViewModel: ChartOptionsDelegate {
    /// Called after user taps the Trash icon in ChartOptionsController to delete a stock in a comparison
    public func deleteStock(_ stock: ComparisonStock) {
        guard let currentComparison = scrollChartViewModel.comparison else { return }
        let stockCountBeforeDeletion = currentComparison.stockSet?.count ?? 0

        Task {
            var updatedList: [Comparison]
            if stockCountBeforeDeletion <= 1 { // all stocks in comparison were deleted
                delete(comparison: currentComparison)
                updatedList = Comparison.fetchAll()
            } else {  // comparison still has at least one stock left
                updatedList = await scrollChartViewModel.removeFromComparison(stock: stock)
            }
            update(list: updatedList, reloadComparison: true)
            didDismiss?()
        }
    }

    /// Callers need a way to dismiss the popover and nil out its NavigationController
    func dismissPopover() {
        didDismiss?()
    }

    /// Called by WebViewController when user wants to switch from the WebView to an existing comparison in the list
    public func load(comparisonToChart: Comparison) {
        for (index, comparison) in list.enumerated() where comparison.id == comparisonToChart.id {
            loadComparison(listIndex: index)
            break
        }
    }

    /// Called by AddStockController or WebViewController when a new stock is added
    public func insert(stock: Stock, isNewComparison: Bool) {
        guard var currentComparison = scrollChartViewModel.comparison,
            let currentStockSet = currentComparison.stockSet else { return }
        Task {
            let comparisonStock = ComparisonStock(context: container.viewContext).setValues(with: stock)

            if isNewComparison || currentStockSet.count == 0 {
                // Create an empty comparison and tell scrollChartViewModel to use it instead of any prior comparison
                currentComparison = Comparison(context: container.viewContext)
                await scrollChartViewModel.updateComparison(newComparison: currentComparison)
                comparisonStock.setColors(upHexColor: .greenAndRed)
            } else {
                // Skip colors already used by other stocks in this comparison or use gray
                var otherColors = ChartHexColor.allCases
                for case let otherStock as ComparisonStock in currentStockSet {
                    // end before lastIndex to always keep gray as an option
                    for index in 0 ..< otherColors.count - 1 where otherStock.hasUpColor(otherHexColor: otherColors[index]) {
                        otherColors.remove(at: index)
                    }
                }
                comparisonStock.setColors(upHexColor: otherColors[0])
            }
            await scrollChartViewModel.addToComparison(stock: comparisonStock)
            CoreDataStack.shared.save()
            let updatedList = Comparison.fetchAll()
            update(list: updatedList, reloadComparison: true)
            didDismiss?()
        }
    }

    /// Called by ChartOptionsController when chart color or type changes
    public func redraw(stock: ComparisonStock) async {
        guard let currentComparison = scrollChartViewModel.comparison else { return }
        CoreDataStack.shared.save()
        let updatedList = await scrollChartViewModel.updateComparison(stock: stock)
        // Update list without reloading the comparison as that clears the chart for a second
        update(list: updatedList, reloadComparison: false)
        didBeginRequest?(currentComparison)
        await scrollChartViewModel.chartOptionsChanged()
    }

    /// Called by ChartOptionsController when the user adds new fundamental metrics
    public func reload(stock: ComparisonStock) async {
        CoreDataStack.shared.save()
    }
}
