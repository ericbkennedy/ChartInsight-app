//
//  UIViewController+TestHelper.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 8/3/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

/// Extension ensures lifecycle events (viewDidLoad, viewWillAppear, and viewDidAppear)
/// are triggered to ensure the view controller is ready for testing.
extension UIViewController {
    func triggerLifecycleIfNeeded() {
        guard !isViewLoaded else { return }

        loadViewIfNeeded()
        beginAppearanceTransition(true, animated: false)
        endAppearanceTransition()
    }
}
