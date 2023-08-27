//
//  SceneDelegate.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/21/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    enum TabIndex: Int {
        case watchlist, web, settings
    }
    var window: UIWindow?
    let tabBarController = UITabBarController()
    var scrollChartViewModel: ScrollChartViewModel!
    var watchlistViewModel: WatchlistViewModel!
    var watchlistViewController: WatchlistViewController!
    var webViewController = WebViewController()
    var settingsViewController: SettingsViewController!

    var watchlistNavigationController: UINavigationController?
    var webNavigationController: UINavigationController?
    var settingsNavigationController: UINavigationController?

    /// Configure and attach the UIWindow to the provided UIWindowScene `scene`
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)

        scrollChartViewModel = ScrollChartViewModel(contentsScale: window.screen.scale)
        watchlistViewModel = WatchlistViewModel(container: CoreDataStack.shared.container, scrollChartViewModel: scrollChartViewModel)
        watchlistViewController = WatchlistViewController(watchlistViewModel: watchlistViewModel)
        settingsViewController = SettingsViewController(watchlistViewModel: watchlistViewModel)

        let isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")

        window.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        window.backgroundColor = UIColor.systemBackground

        let list = Comparison.fetchAll()
        var migrateToContext: NSManagedObjectContext?
        if list.isEmpty {
            migrateToContext = CoreDataStack.shared.viewContext
        }
        Task {
            await DBActor.shared.moveIfNeeded(delegate: watchlistViewModel, toManagedContext: migrateToContext)

            if let stockChanges = await StockChangeService().fetchChanges() { // will be nil if no changes since last fetch
                await DBActor.shared.update(stockChanges: stockChanges, delegate: watchlistViewModel)
            }
        }

        watchlistNavigationController = UINavigationController(rootViewController: watchlistViewController)
        watchlistNavigationController?.title = "Watchlist"

        webNavigationController = UINavigationController(rootViewController: webViewController)
        webNavigationController?.tabBarItem.image = UIImage(systemName: "sparkle.magnifyingglass")
        webNavigationController?.title = "ChartInsight.com"
        webViewController.delegate = watchlistViewModel // Users can add stocks found on chartinsight.com
        watchlistNavigationController?.tabBarItem.image = UIImage(systemName: "chart.xyaxis.line")

        settingsNavigationController = UINavigationController(rootViewController: settingsViewController)
        settingsNavigationController?.title = "Settings"
        settingsNavigationController?.tabBarItem.image = UIImage(systemName: "gear")

        tabBarController.viewControllers = [watchlistNavigationController!, webNavigationController!, settingsNavigationController!]
        tabBarController.tabBar.backgroundColor = UIColor.systemBackground

        window.rootViewController = tabBarController

        window.makeKeyAndVisible()
        self.window = window
    }

    public func showWebView(urlString: String) {
        webViewController.urlString = urlString
        tabBarController.selectedIndex = TabIndex.web.rawValue
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).

        // Hide magnified chart and invalidate any progressIndicator.timer
        watchlistViewController.magnifier.isHidden = true
        watchlistViewController.progressIndicator?.timer?.invalidate()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }

    /// Switch color scheme with darkMode when isOn == true
    public func darkMode(isOn: Bool) {
        UserDefaults.standard.setValue(isOn, forKey: "darkMode")

        tabBarController.overrideUserInterfaceStyle = isOn ? .dark : .light
    }
}
