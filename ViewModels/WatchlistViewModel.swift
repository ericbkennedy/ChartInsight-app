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

import Foundation

protocol ChartOptionsDelegate: AnyObject {
    func deleteStock(_ stock: Stock)
    func load(comparisonToChart: Comparison)
    func insert(stock: Stock, isNewComparison: Bool)
    func redraw(stock: Stock) async
    func reload(stock: Stock) async
    func dismissPopover()
}

@MainActor final class WatchlistViewModel {
    private (set) var scrollChartViewModel: ScrollChartViewModel!

    // Closures to bind View to ViewModel
    public var didBeginRequest: (@MainActor (Comparison) -> Void)?
    public var didDismiss: (@MainActor () -> Void)?
    public var didUpdate: (@MainActor (_ selectedIndex: Int) -> Void)?

    public var listCount: Int { list.count }
    private var list: [Comparison] = []

    init(scrollChartViewModel: ScrollChartViewModel) {
        self.scrollChartViewModel = scrollChartViewModel
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
}

extension WatchlistViewModel: DBActorDelegate {
    /// Callback after async comparisonList reload and by StockChangeService if user rows were updated
    public func update(list newList: [Comparison], reloadComparison: Bool) {
        var selectedIndex = 0
        if !newList.isEmpty && scrollChartViewModel.comparison.id > 0 {
            for (index, comparison) in newList.enumerated() where comparison.id == scrollChartViewModel.comparison.id {
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
    public func deleteStock(_ stock: Stock) {
        let stockCountBeforeDeletion = scrollChartViewModel.comparison.stockList.count

        Task {
            var updatedList: [Comparison]
            if stockCountBeforeDeletion <= 1 { // all stocks in comparison were deleted
                updatedList = await scrollChartViewModel.comparison.deleteFromDb()

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
        Task {
            var stock = stock
            if isNewComparison || scrollChartViewModel.comparison.stockList.isEmpty {
                await scrollChartViewModel.updateComparison(newComparison: Comparison())
                stock.setColors(upHexColor: .greenAndRed)
            } else {
                // Skip colors already used by other stocks in this comparison or use gray
                var otherColors = ChartHexColor.allCases
                for otherStock in scrollChartViewModel.comparison.stockList {
                    // end before lastIndex to always keep gray as an option
                    for index in 0 ..< otherColors.count - 1 where otherStock.hasUpColor(otherHexColor: otherColors[index]) {
                        otherColors.remove(at: index)
                    }
                }
                stock.setColors(upHexColor: otherColors[0])
            }

            let updatedList = await scrollChartViewModel.addToComparison(stock: stock)
            update(list: updatedList, reloadComparison: true)
            didDismiss?()
        }
    }

    /// Called by ChartOptionsController when chart color or type changes
    public func redraw(stock: Stock) async {
        let updatedList = await scrollChartViewModel.updateComparison(stock: stock)
        // Update list without reloading the comparison as that clears the chart for a second
        update(list: updatedList, reloadComparison: false)
        didBeginRequest?(scrollChartViewModel.comparison)
        await scrollChartViewModel.chartOptionsChanged()
    }

    /// Called by ChartOptionsController when the user adds new fundamental metrics
    public func reload(stock: Stock) async {
        let updatedList = await scrollChartViewModel.updateComparison(stock: stock)
        update(list: updatedList, reloadComparison: true)
    }
}
