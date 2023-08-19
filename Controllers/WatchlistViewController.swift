//
//  WatchlistViewController.swift
//  ChartInsight
//
//  This is the primary ViewController which includes a tableView of stocks
//  and the ScrollChartView which displays the stock chart with financials bars.
//  It adds buttons for each stock to the navStockButtonToolbar in the navigationItem.titleView
//  so the user can change the chart style, color or fundamental metrics shown.
//
//  Created by Eric Kennedy on 6/23/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

class WatchlistViewController: UITableViewController {
    var progressIndicator: ProgressIndicator?
    var magnifier = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

    enum ZPosition: CGFloat {
        case tableView, scrollChartView, magnifier, progressIndicator
    }

    private let cellID = "cellId"
    private let padding = 6.0
    private var width: CGFloat = 0
    private var height: CGFloat = 0
    private var rowHeight: CGFloat = 0
    private var statusBarHeight: CGFloat = 0 // set using safeAreaInsets
    private var toolbarHeight: CGFloat = 0
    private var tableViewWidthVisible: CGFloat = 0
    private var lastShift: CGFloat = 0
    private var pinchCount: CGFloat = 0
    private var pinchMidpointSum: CGFloat = 0

    private var popOverNav: UINavigationController? // nav within popover
    private var doubleTapRecognizer = UITapGestureRecognizer()
    private var longPressRecognizer = UILongPressGestureRecognizer()
    private var panGestureRecognizer = UIPanGestureRecognizer()
    private var pinchGestureRecognizer = UIPinchGestureRecognizer()
    private var comparisonListToolbar = UIToolbar() // in tableView header
    private var newComparisonButton = UIBarButtonItem(systemItem: .add)
    private var toggleListButton = UIBarButtonItem(image: UIImage(named: "toggleList"))
    private var shareMenuButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"))
    private var navStockButtonToolbar = UIToolbar() // will be navigationItem.titleView

    private var scrollChartViewModel: ScrollChartViewModel!
    private var watchlistViewModel: WatchlistViewModel!
    private var scrollChartView: ScrollChartView!

    init(watchlistViewModel: WatchlistViewModel) {
        self.watchlistViewModel = watchlistViewModel
        scrollChartViewModel = watchlistViewModel.scrollChartViewModel
        scrollChartView = ScrollChartView(viewModel: scrollChartViewModel)
        super.init(style: .plain)

        self.watchlistViewModel.didBeginRequest = { [weak self] comparison in
            self?.scrollChartView.clearChart()
            self?.updateNavStockButtonToolbar(for: comparison)
        }

        self.watchlistViewModel.didDismiss = { [weak self] in
            self?.dismissPopover()
        }

        self.watchlistViewModel.didUpdate = { [weak self] selectedIndex in
            self?.tableView.reloadData() // will require reselecting the row below
            self?.tableView.selectRow(at: IndexPath(row: selectedIndex, section: 0),
                                animated: false, scrollPosition: .middle)
        }
    }

    ///  Initializer required by parent class for use with storyboards which this app doesn't use
    required convenience init?(coder: NSCoder) {
        self.init(watchlistViewModel: WatchlistViewModel(container: CoreDataStack.shared.container,
                                                         scrollChartViewModel: ScrollChartViewModel(contentsScale: 2.0)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 1 // aligns upper border with ScrollChartView divider
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        tableView.accessibilityIdentifier = AccessibilityId.Watchlist.tableView

        tableViewWidthVisible = UIDevice.current.userInterfaceIdiom == .phone ? 66 : 100
        rowHeight = UIDevice.current.userInterfaceIdiom == .phone ? 40 : 44

        scrollChartView.layer.anchorPoint = .zero // allows bounds = frame
        scrollChartView.layer.position = CGPoint(x: tableViewWidthVisible, y: 0)
        scrollChartView.layer.zPosition = ZPosition.scrollChartView.rawValue
        view.addSubview(scrollChartView)

        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.addTarget(self, action: #selector(doubleTap))
        scrollChartView.addGestureRecognizer(doubleTapRecognizer)

        magnifier.isHidden = true
        magnifier.layer.contentsScale = UIScreen.main.scale
        magnifier.layer.zPosition = ZPosition.magnifier.rawValue
        view.addSubview(magnifier)

        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.addTarget(self, action: #selector(magnify))
        scrollChartView.addGestureRecognizer(longPressRecognizer)

        panGestureRecognizer.addTarget(self, action: #selector(handlePan))
        scrollChartView.addGestureRecognizer(panGestureRecognizer)

        pinchGestureRecognizer.addTarget(self, action: #selector(handlePinch))
        scrollChartView.addGestureRecognizer(pinchGestureRecognizer)

        toggleListButton.target = self
        toggleListButton.action = #selector(toggleList)
        toggleListButton.accessibilityIdentifier = AccessibilityId.Watchlist.toggleListButton
        newComparisonButton.target = self
        newComparisonButton.action = #selector(newComparison)
        newComparisonButton.accessibilityIdentifier = AccessibilityId.Watchlist.newComparisonButton
        comparisonListToolbar.items = [newComparisonButton]
    }

    /// Update subviews now that frame size is available
    override func viewWillAppear(_ animated: Bool) {

        if isNewFrameSize(newSize: view.frame.size) {
            resizeSubviews(newSize: view.frame.size)
        }

        // Remove toolbar background and top border
        navStockButtonToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        navStockButtonToolbar.setShadowImage(UIImage(), forToolbarPosition: .any) // top border
        navStockButtonToolbar.accessibilityIdentifier = AccessibilityId.Watchlist.navStockButtonToolbar

        if scrollChartViewModel.comparison == nil { // App just launched & views are loaded, now select a row
            watchlistViewModel.didSelectRow(at: 0)
        }
        navigationItem.titleView = navStockButtonToolbar
        view.layer.setNeedsDisplay()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return watchlistViewModel.listCount
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = watchlistViewModel.title(for: indexPath.row)
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        watchlistViewModel.didSelectRow(at: indexPath.row)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return rowHeight
    }

    /// "+" add button in tableView header (wrapped in a UIToolbar)
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return comparisonListToolbar
    }

    /// Find the keyWindow and get the safeAreaInsets for the notch and other unsafe areas
    private func getSafeAreaInsets() -> UIEdgeInsets {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if let keyWindow = windowScene.keyWindow {
                    return keyWindow.safeAreaInsets
                }
            }
        }
        return .zero
    }

    /// Determine if the frame size has changed and subviews must be resized
    private func isNewFrameSize(newSize: CGSize) -> Bool {
        let newWidth = newSize.width
        var newHeight = newSize.height - padding
        let safeAreaInsets = getSafeAreaInsets()

        toolbarHeight = 44
        statusBarHeight = 20
        if safeAreaInsets.top > statusBarHeight {
            statusBarHeight = safeAreaInsets.top
        }

        newHeight = newSize.height - statusBarHeight - 2 * toolbarHeight - padding - safeAreaInsets.bottom

        if newHeight != height || newWidth != width { // iPad multitasking only reduces the width
            width = newWidth
            height = newHeight
            return true
        }
        return false
    }

    private func resizeSubviews(newSize: CGSize) {
        navStockButtonToolbar.frame = CGRect(x: 0, y: 0, width: newSize.width, height: toolbarHeight)
        tableView.reloadData()

        let delta = scrollChartView.bounds.size.width - newSize.width
        let shiftBars = Int(scrollChartView.layer.contentsScale
                            * delta/(scrollChartViewModel.xFactor * scrollChartViewModel.barUnit.rawValue))
        scrollChartViewModel.updateMaxPercentChange(barsShifted: -shiftBars) // shiftBars are + when delta is -
        scrollChartView.bounds = CGRect(x: 0, y: 0, width: width, height: height) // isNewFrameSize calculated height
        let (pxWidth, pxHeight) = scrollChartView.resize()
        scrollChartViewModel.resize(pxWidth: pxWidth, pxHeight: pxHeight)

        // ProgressIndicator doesn't resize by changing the frame property so create a new instance
        progressIndicator = ProgressIndicator(frame: CGRect(x: 0, y: 0, width: width - tableViewWidthVisible, height: 4))
        if let progressIndicator {
            progressIndicator.layer.zPosition = ZPosition.progressIndicator.rawValue
            scrollChartView.addSubview(progressIndicator)
            scrollChartView.progressIndicator = progressIndicator
        }
    }

    /// Device rotated (supported only on iPad) so update width and height properties and resize subviews
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if size.width > 0 && isNewFrameSize(newSize: size) {
            resizeSubviews(newSize: size)
        }
    }

    /// User double tapped to zoom in
    @objc func doubleTap(recognizer: UITapGestureRecognizer) {
        recognizer.cancelsTouchesInView = true

        let pinchMidpoint = recognizer.location(in: view).x - scrollChartView.layer.position.x - 5

        scrollChartView.scaleChartImage(2.0, withCenter: pinchMidpoint)
        let pxShift = scrollChartView.getPxShiftAndResetLayer()
        scrollChartViewModel.scaleChart(newScale: 2.0, pxShift: pxShift)
    }

    /// Display an enlarged screenshot of the chart under the user's finger in the magnifier subview
    @objc func magnify(recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .ended {
            magnifier.isHidden = true
            return
        }

        let xPress = recognizer.location(in: scrollChartView).x - padding
        let yPress = recognizer.location(in: scrollChartView).y
        let midpoint: CGFloat = 50
        let magnifierWidth: CGFloat = 2 * midpoint
        let magnifierHeight: CGFloat = 2 * midpoint

        magnifier.frame = CGRect(x: recognizer.location(in: view).x - midpoint,
                                 y: yPress - magnifierHeight,
                                 width: magnifierWidth,
                                 height: magnifierHeight)
        Task {
            if let image = await scrollChartView.magnifyBar(xPress: xPress, yPress: yPress) {
                // Note that this returns an image even when the user moves to the Y axis labels
                magnifier.image = image
                magnifier.layer.borderColor = UIColor.lightGray.cgColor
                magnifier.layer.borderWidth = 1
                magnifier.layer.cornerRadius = midpoint
                magnifier.layer.masksToBounds = true
                magnifier.isHidden = false
            }
        }
    }

    /// User panned to change the chart dates. Calculate shift in date bars shown and tell scrollChartViewModel to recompute the chart.
    @objc func handlePan(recognizer: UIPanGestureRecognizer) {
        recognizer.cancelsTouchesInView = true
        var deltaBars: Int = 0
        var delta: CGFloat = 0
        var currentShift: CGFloat = 0
        if recognizer.state == .cancelled {
            lastShift = 0
            return //
        } else if recognizer.state == .began {
            lastShift = 0
        }

        currentShift = recognizer.translation(in: view).x
        delta = (currentShift - lastShift) * UIScreen.main.scale
        deltaBars = Int(delta/(scrollChartViewModel.xFactor * scrollChartViewModel.barUnit.rawValue))
        if deltaBars != 0 {
            scrollChartViewModel.updateMaxPercentChange(barsShifted: deltaBars)
            lastShift = currentShift
        }
    }

    /// While the user is pinching the chart, scrollChartView.scaleChartImage(_:withCenter:) will scale horizontally.
    /// When the gesture ends, have scrollChartViewModel recompute the ChartElements with the new scale.
    @objc func handlePinch(recognizer: UIPinchGestureRecognizer) {
        recognizer.cancelsTouchesInView = true
        let pinchMidpoint = recognizer.location(in: view).x - scrollChartView.layer.position.x - padding
        if recognizer.state == .began {
            pinchCount = 0
            pinchMidpointSum = 0.0
        } else if recognizer.state == .changed {
            pinchCount += 1
            pinchMidpointSum /= pinchCount // avg smooths touch errors
            scrollChartView.scaleChartImage(recognizer.scale, withCenter: pinchMidpoint)
        } else {
            let pxShift = scrollChartView.getPxShiftAndResetLayer()
            scrollChartViewModel.scaleChart(newScale: recognizer.scale, pxShift: pxShift)
        }
    }

    /// Add toggleListButton and buttons for each stock in this comparison
    private func updateNavStockButtonToolbar(for comparison: Comparison) {
        var buttons: [UIBarButtonItem] = [toggleListButton]
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))

        if let currentStockSet = comparison.stockSet, currentStockSet.count > 0 {
            var menuActions = [UIAction]()
            for case let stock as ComparisonStock in currentStockSet {
                var buttonTitle = stock.ticker
                if currentStockSet.count == 1 || UIDevice.current.userInterfaceIdiom == .pad {
                    // Add first word from stock name if not equal to ticker
                    let nonLetters = CharacterSet.letters.inverted
                    if let firstWord = stock.name.components(separatedBy: nonLetters).first,
                       firstWord != stock.ticker { // avoid redundant EPR EPR
                        buttonTitle += " \(firstWord)"
                    } else {
                        buttonTitle = stock.name // EPR Properties
                    }
                }
                let tickerButton = UIBarButtonItem(title: buttonTitle,
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(editStock))
                tickerButton.tag = Int(stock.stockId)
                tickerButton.accessibilityIdentifier = stock.ticker
                tickerButton.tintColor = stock.upColor
                buttons.append(tickerButton)

                if stock.hasFundamentals {
                    menuActions.append(UIAction(title: "\(stock.ticker) website",
                                                handler: { _ in
                        self.openWebView("https://chartinsight.com/redirectToIR/\(stock.ticker)")
                    }))
                    menuActions.append(UIAction(title: "\(stock.ticker) SeekingAlpha",
                                                handler: { _ in
                        self.openWebView("https://seekingalpha.com/symbol/\(stock.ticker)")
                    }))
                    menuActions.append(UIAction(title: "chartinsight.com/\(stock.ticker)",
                                                handler: { _ in
                        self.openWebView("https://chartinsight.com/\(stock.ticker)")
                    }))
                }
            }
            shareMenuButton.menu = UIMenu(title: "", children: menuActions)
            shareMenuButton.accessibilityIdentifier = AccessibilityId.Watchlist.shareMenuButton

            let maxComparisonCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3

            if currentStockSet.count < maxComparisonCount {
                let compareButton = UIBarButtonItem(title: "+ compare",
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(compareStock))
                compareButton.accessibilityIdentifier = AccessibilityId.Watchlist.addToComparisonButton
                // Reduce font size of "+ compare" text
                compareButton.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10)],
                                                     for: .normal)
                compareButton.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10)],
                                                     for: .highlighted)
                buttons.append(compareButton)
            }
        }
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))
        buttons.append(shareMenuButton)
        navStockButtonToolbar.items = buttons
    }

    private func openWebView(_ urlString: String) {
        if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate {
            sceneDelegate.showWebView(urlString: urlString)
        }
    }

    /// User clicked the "+" add button in the header of the tableView to create a new stock comparison
    @objc func newComparison(button: UIBarButtonItem) {
        let addStockController = AddStockController(style: .plain)
        addStockController.delegate = watchlistViewModel
        addStockController.isNewComparison = true
        popoverPush(viewController: addStockController, from: button)
    }

    /// User clicked the "compare" button in the navStockButtonToolbar to add a stock to the current comparison
    @objc func compareStock(button: UIBarButtonItem) {
        let addStockController = AddStockController(style: .plain)
        addStockController.delegate = watchlistViewModel
        addStockController.isNewComparison = false
        popoverPush(viewController: addStockController, from: button)
    }

    /// User clicked a ticker in navStockButtonToolbar to edit settings for the stock with stock.id == button.tag
    @objc func editStock(button: UIBarButtonItem) {
        guard let currentComparison = scrollChartViewModel.comparison,
        let currentStockSet = currentComparison.stockSet else { return }
        let stockId = button.tag

        for case let stock as ComparisonStock in currentStockSet where stock.stockId == stockId {
            let chartOptionsController = ChartOptionsController(stock: stock, delegate: watchlistViewModel)
            chartOptionsController.sparklineKeys = currentComparison.sparklineKeys()
            popoverPush(viewController: chartOptionsController, from: button)
            break
        }
    }
    /// Show or hide the list of stocks by increasing the width of scrollChartView
    @objc func toggleList() {
        var delta = -1 * scrollChartView.layer.position.x

        if scrollChartView.layer.position.x < 1.0 {
            delta += tableViewWidthVisible
        }

        scrollChartView.svWidth -= delta
        scrollChartViewModel.pxWidth = UIScreen.main.scale * scrollChartView.svWidth

        scrollChartView.clearChart() // clear prior render to avoid odd animation

        scrollChartView.layer.position = CGPoint(x: scrollChartView.layer.position.x + delta,
                                                 y: scrollChartView.layer.position.y)

        let shiftBars = Int(scrollChartView.layer.contentsScale
                            * delta/(scrollChartViewModel.xFactor * scrollChartViewModel.barUnit.rawValue))

        scrollChartViewModel.updateMaxPercentChange(barsShifted: -shiftBars) // shiftBars are + when delta is -
    }

    /// On iPad, presents the viewController in a popover with an arrow to the button. On iPhone, presents modal
    private func popoverPush(viewController: UIViewController, from button: UIBarButtonItem) {
        popOverNav = UINavigationController(rootViewController: viewController)
        let isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")
        if let popOver = popOverNav {
            popOver.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
            popOver.modalPresentationStyle = .popover
            popOver.popoverPresentationController?.sourceView = view
            popOver.popoverPresentationController?.barButtonItem = button
            show(popOver, sender: self)
        }
    }

    /// remove the topmost iPhone UIViewController or iPad UIPopoverController
    @objc func dismissPopover() {
        popOverNav?.dismiss(animated: true)
        popOverNav = nil // ARC will release the UINavigationController and its child view controllers
    }
}
