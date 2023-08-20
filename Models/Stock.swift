//
//  Stock.swift
//  ChartInsight
//
//  Stock objects are returned by the search results and are used to create ComparisonStock entries.
//
//  Created by Eric Kennedy on 8/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

public struct Stock {
    public var id: Int = 0
    public var hasFundamentals: Bool = true
    public var ticker: String = ""
    public var name: String = ""
    public var startDateString: String = "20090102" // full text search returns a string value
}
