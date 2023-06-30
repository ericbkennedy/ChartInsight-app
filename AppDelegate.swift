//
//  AppDelegate.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/21/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Non-alphabetical order of metrics achieved with array of categories which contains array of metric details
    var metrics: [[[String]]] = []
    var metricDictionary: [String:[String]] = [:]
        
    func title(for key: String) -> String {
        if let item = metricDictionary[key] {
            return item[1]
        }
        return ""
    }

    func description(for key: String) -> String {
        if let item = metricDictionary[key] {
            return item[2]
        }
        return ""
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Load metrics from plist
        typealias MetricsConfig = [[[String]]] // Arrays allow custom order by category and tag
        
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
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func darkMode() -> Bool {
        return UserDefaults.standard.bool(forKey: "darkMode")
    }

}

