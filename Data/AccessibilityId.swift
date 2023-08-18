//
//  AccessibilityId.swift
//  ChartInsight
//
//  An enum without cases is used to namespace the accessbility identifiers
//  similar to how Apple uses a caseless enum in the Combine framework.
//
//  Created by Eric Kennedy on 8/17/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

enum AccessibilityId {
    enum Watchlist {
        static let newComparisonButton = "Add a new stock"
        static let navStockButtonToolbar = "Toolbar"
        static let addToComparisonButton = "Compare with another stock"
        static let toggleListButton = "Show or hide the list"
        static let shareMenuButton = "External links"
        static let tableView = "Watchlist"
    }
    enum AddStock {
        static let tableView = "Search results"
        static let searchBar = "Enter stock ticker or name"
        static let noMatches = "No matches with supported fundamentals"
    }
    enum ChartOptions {
        static let doneButton = "Done"
        static let deleteButton = "Delete"
        static let tableView = "Chart options"
        static let unavilableMessage = "Unavailable for"
        static let addFundamentalRow = "        + Add Financial Metric" // leading whitespace looks better
    }
    enum AddFundamental {
        static let tableView = "Fundamental metrics"
    }
    enum Settings {
        static let nideModeSwitch = "Night mode"
        static let tableView = "Settings and stock list"
        static let watchlistSection = "Watchlist stocks"
        static let contactSupport = "Contact Support"
    }
}
