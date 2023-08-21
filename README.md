# ChartInsight iPad and iPhone app

[Available on the App Store](https://apps.apple.com/us/app/fundamental-technical-charts/id6451326862)

This app was originally created in 2012 for the first retina iPad and was rewritten from Objective-C to Swift. While most financial apps require cumbersome drop-downs to adjust date ranges, this app supports intuitive zooming and panning. Easily zoom between daily, weekly and monthly charts. The financial data for the app is parsed from XML filings from the Security and Exchange Commission and is provided as-is with no warranty.

![ChartInsight iOS app core objects](./Data/app-core-objects.svg)

View to ViewModel binding is implemented with closures. WatchlistViewModel and ScrollChartViewModel each have a didUpdate() closure property set by the corresponding view so it is notified of updates.

```
WatchlistViewModel didUpdate: (@MainActor (_ selectedIndex: Int) -> Void)?

ScrollChartViewModel didUpdate: (@MainActor ([ChartElements]) -> Void)? 
```

WatchlistViewModel manages the list of stock comparisons and updates the ChildTableViewController of WatchlistViewController with a didUpdate() closure that is used to select a row in ChildTableViewController.tableView.

WatchlistViewController forwards the result of pinch and pan gestures to the ScrollChartViewModel to scale the chart data. 

ScrollChartViewModel computes the ChartElements and uses the didUpdate() closure to pass a copy of ChartElements to the ScrollChartView. ScrollChartView's renderCharts(stockChartElements:) method provides them to the ChartRenderer for rendering.

WatchlistViewModel is also the delegate for ViewControllers in the app that add or change a stock comparison: AddStockController, ChartOptionsController, SettingsViewController, and WebViewController. 

CoreData stores the user's list of stock comparisons using the Comparison and ComparisonStock NSManagedObjects. The list of stocks supported by the app is cached along with historical price data in a SQLite3 charts.db. (SQLite offers full-text search and provides faster inserts and deletes for thousands of rows of historical stock data.)

Concurrent updates to historical and intraday price data from the HistoricalDataService is handled for each stock by a StockActor for multi core thread safety. StockActors accept GAAP financial data from the FundamentalService and then notify the ScrollChartViewModel via a requestFinished(newPercentChange:) delegate method. 

The native app functionality is integrated with a WKWebView of chartinsight.com to allow viewing additional metrics, insider buying and 13-F holdings.

The companion responsive website [chartinsight.com](https://chartinsight.com) was created after the 2012 iOS app and uses a separate axis to compare a fundamental metric (Revenue Per Share, Earnings Per Share, Cash Flow From Ops Per Share) with the stock chart. Dual axis comparison charts work better for single-stock close-only charts but can be confusing when comparing multiple stocks like the iOS app can. For that reason, the iOS app shows the fundamental data above the stock chart.

The original 2012 app also supported searching for news around a date selected on the chart and sharing screenshots. That functionality was removed to speed up the rewrite to Swift and may be reimplemented later.
