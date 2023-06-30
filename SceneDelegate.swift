//
//  SceneDelegate.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/21/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    let tabBarController = UITabBarController()
    var watchlistViewController = WatchlistViewController()
    var settingsViewController = SettingsViewController(style: .plain)

    var watchlistNavigationController: UINavigationController?
    var settingsNavigationController: UINavigationController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        
        let isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")
        
        window.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        window.backgroundColor = UIColor.systemBackground
        
        Task {
            await DBActor.shared.update(delegate: watchlistViewController);   // copy db to documents and/or update existing db
        }
        
        settingsViewController.delegate = watchlistViewController; // will refresh comparison list after deletion
        watchlistNavigationController = UINavigationController(rootViewController: watchlistViewController)
        watchlistNavigationController?.title = "Watchlist"
        watchlistNavigationController?.tabBarItem.image = UIImage(systemName: "chart.xyaxis.line")
        settingsNavigationController = UINavigationController(rootViewController: settingsViewController)
        settingsNavigationController?.title = "Settings"
        settingsNavigationController?.tabBarItem.image = UIImage(systemName: "gear")
        tabBarController.viewControllers = [watchlistNavigationController!, settingsNavigationController!]
        tabBarController.tabBar.backgroundColor = UIColor.systemBackground
        
        window.rootViewController = tabBarController
        
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
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
        watchlistViewController.progressIndicator.timer?.invalidate()
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
    func darkMode(isOn: Bool) {
        UserDefaults.standard.setValue(isOn, forKey: "darkMode")
        
        tabBarController.overrideUserInterfaceStyle = isOn ? .dark : .light
    }
}
