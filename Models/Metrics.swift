//
//  Metrics.swift
//  ChartInsight
//
//  Singleton array of metrics
//
//  Created by Eric Kennedy on 6/30/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class Metrics {
    static let shared = Metrics()
    /// Non-alphabetical order of metrics achieved with array of categories which contains array of metric details
    var metrics: [[[String]]]
    var metricDictionary: [String: [String]]

    // Load metrics from plist
    typealias MetricsConfig = [[[String]]] // Arrays allow custom order by category and tag

    private init() {
        metrics = []
        metricDictionary = [:]
        let url = Bundle.main.url(forResource: "metrics", withExtension: "plist")!
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: url)
            metrics = try decoder.decode(MetricsConfig.self, from: data)
            for category in metrics {
                for metric in category {
                    let tag = metric[0]
                    metricDictionary[tag] = metric
                }
            }
        } catch {
            print(error)
        }
    }

    func title(for key: String) -> String {
        if let item = metricDictionary[key] {
            return item[1]
        }
        return ""
    }
}
