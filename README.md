# ChartInsight iPad and iPhone app

This app was originally created in 2012 for the first retina iPad and is being rewritten from Objective-C to Swift. While most financial apps require cumbersome drop-downs to adjust date ranges, this app supports intuitive zooming and panning. Easily zoom between daily, weekly and monthly charts. The financial data for the app is parsed from XML filings from the Security and Exchange Commission and is provided as-is with no warranty.

## App Structure

Since this app was built prior to SwiftUI, it follows the typical MVC pattern of UIKit apps. The code for rendering multiple stock charts is in Views/ScrollChartView.* with  Controllers/RootViewController.* managing the list of stocks and the panning and zooming interactions on the ScrollChartView.

Another tab will be added to this app to show stocks with buying by insiders or leading investors who file 13-F filings.

The companion responsive website [chartinsight.com](https://chartinsight.com) was created later and uses a separate axis to compare a fundamental metric (Revenue Per Share, Earnings Per Share, Cash Flow From Ops Per Share) with the stock chart. Dual axis comparison charts work better for small close-only stock charts. The original 2012 app showed Book Value on the stock chart but book value isn't directly available from the XML filings (it was provided by an expensive paid financial service) and often doesn't reflect the current value of assets.

The original 2012 app also supported searching for news around a date selected on the chart and sharing screenshots. That functionality has been removed to speed up the rewrite to Swift and may be reimplemented later.
