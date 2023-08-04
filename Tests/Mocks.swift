//
//  Mocks.swift
//  ChartInsightTests
//
//  Mock objects to test WatchlistViewController without including other Views in Test target
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

final class SceneDelegate {
    public func showWebView(urlString: String) { }
}

extension Stock {
    static func testAAPL() -> Stock {
        var stock = Stock()
        stock.id = 1
        stock.name = "Apple"
        stock.ticker = "AAPL"
        stock.startDateString = "20230601" // reduce date range for faster tests
        stock.fundamentalList = "" // empty fundamentals to skip FundamentalService
        return stock
    }
}

final class ProgressIndicator: UIView {
    override init(frame: CGRect) { super.init(frame: frame) }
    required convenience init?(coder: NSCoder) { self.init(frame: .zero) }
    func reset() { }
    func startAnimating() { }
    func stopAnimating() { }
}

final class AddStockController: UITableViewController {
    public var delegate: WatchlistViewController?
    public var isNewComparison: Bool = false
}

final class ChartOptionsController: UITableViewController {
    public var sparklineKeys: [String] = []
    public var stock: Stock
    private weak var delegate: WatchlistViewController?

    public init(stock: Stock, delegate: WatchlistViewController?) {
        self.stock = stock
        self.delegate = delegate
        super.init(style: .plain)
    }

    required convenience init?(coder: NSCoder) {
        self.init(stock: Stock.testAAPL(), delegate: nil)
    }

    public func chartTypeChanged(to chartTypeIndex: Int) -> Stock {
        return Stock.testAAPL()
    }

    public func chartColorChanged(to colorIndex: Int) -> Stock {
        return Stock.testAAPL()
    }
}
