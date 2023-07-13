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

class WatchlistViewController: UITableViewController {
    var progressIndicator = ProgressIndicator(frame: CGRect(x: 0, y: 0, width: 320, height: 4))
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

    private var popOverNav = UINavigationController() // nav within popover
    private var doubleTapRecognizer = UITapGestureRecognizer()
    private var longPressRecognizer = UILongPressGestureRecognizer()
    private var panGestureRecognizer = UIPanGestureRecognizer()
    private var pinchGestureRecognizer = UIPinchGestureRecognizer()
    private var addStockToolbar = UIToolbar() // in tableView header
    private var addStockButton = UIBarButtonItem(systemItem: .add)
    private var toggleListButton = UIBarButtonItem(image: UIImage(named: "toggleList"))
    private var shareMenuButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"))
    private var navStockButtonToolbar = UIToolbar() // will be navigationItem.titleView

    private var scrollChartView = ScrollChartView()

    private var list: [Comparison] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 1 // aligns upper border with ScrollChartView divider
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)

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
        addStockButton.target = self
        addStockButton.action = #selector(addStock)
        addStockToolbar.items = [addStockButton]
    }

    /// Update subviews now that frame size is available
    override func viewWillAppear(_ animated: Bool) {

        if isNewFrameSize(newSize: view.frame.size) {
            resizeSubviews(newSize: view.frame.size)
        }
        navStockButtonToolbar.frame = CGRect(x: 0, y: 0, width: width, height: toolbarHeight)

        // Remove toolbar background and top border
        navStockButtonToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        navStockButtonToolbar.setShadowImage(UIImage(), forToolbarPosition: .any) // top border

        updateNavStockButtonToolbar()
        navigationItem.titleView = navStockButtonToolbar
        view.layer.setNeedsDisplay()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.list.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.row < list.count {
            config.text = list[indexPath.row].title
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if list.count > indexPath.row {
            loadComparison(listIndex: indexPath.row)
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return rowHeight
    }

    /// "+" add button in tableView header (wrapped in a UIToolbar)
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return addStockToolbar
    }

    /// Called by WebViewController when user wants to switch from the WebView to an existing comparison in the list
    public func load(comparisonToChart: Comparison) {
        for (index, comparison) in list.enumerated() where comparison.id == comparisonToChart.id {
            tableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .middle)
            loadComparison(listIndex: index)
            break
        }
    }

    /// Called when app first loads (with listIndex == 0) or when user taps a tableView row
    private func loadComparison(listIndex: Int) {
        scrollChartView.clearChart()
        progressIndicator.startAnimating()
        Task {
            let comparison = list[listIndex]
            await scrollChartView.updateComparison(newComparison: comparison)
            updateNavStockButtonToolbar()
        }
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

        if newHeight != height {
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
                              * delta/(scrollChartView.xFactor * scrollChartView.barUnit))

        scrollChartView.updateMaxPercentChange(barsShifted: -shiftBars) // shiftBars are + when delta is -
        scrollChartView.bounds = CGRect(x: 0, y: 0, width: width, height: height) // isNewFrameSize calculated height
        scrollChartView.resize()

        // ProgressIndicator doesn't resize by changing the frame property so create a new instance
        progressIndicator = ProgressIndicator(frame: CGRect(x: 0, y: 0, width: width - tableViewWidthVisible, height: 4))
        progressIndicator.layer.zPosition = ZPosition.progressIndicator.rawValue
        scrollChartView.addSubview(progressIndicator)
        scrollChartView.progressIndicator = progressIndicator
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
        scrollChartView.scaleChart(2.0)
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

    /// User panned to change the chart dates. Calculate shift in date bars shown and tell scrollChartView to redraw the chart.
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
        deltaBars = Int(delta/(scrollChartView.xFactor * scrollChartView.barUnit))
        if deltaBars != 0 {
            scrollChartView.updateMaxPercentChange(barsShifted: deltaBars)
            lastShift = currentShift
        }
    }

    /// While the user is pinching the chart, have scrollChartView.resizeChartImage() horizontally
    /// When the gesture ends, have scrollChartView redraw the chart with the new scale.
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
            scrollChartView.scaleChart(recognizer.scale)
        }
    }

    /// Called by ChartOptionsController when chart color or type changes
    public func redraw(stock: Stock) async {
        list = await scrollChartView.updateComparison(stock: stock)
        tableView.reloadData() // avoid update(list:) as that clears the chart for a second
        if let barButtonItems = navStockButtonToolbar.items {
            for button in barButtonItems where button.tag == stock.id {
                button.tintColor = stock.upColor
            }
            await scrollChartView.redrawCharts()
        }
    }

    /// Called by ChartOptionsController when the user adds new fundamental metrics
    public func reload(stock: Stock) async {
        let updatedList = await scrollChartView.updateComparison(stock: stock)
        update(list: updatedList)
    }

    /// Called after user taps the Trash icon in ChartOptionsController to delete a stock in a comparison
    public func deleteStock(_ stock: Stock) {
        let stockCountBeforeDeletion = scrollChartView.comparison.stockList.count

        Task {
            var updatedList: [Comparison]
            if stockCountBeforeDeletion <= 1 { // all stocks in comparison were deleted
                updatedList = await scrollChartView.comparison.deleteFromDb()

            } else {  // comparison still has at least one stock left
                updatedList = await scrollChartView.removeFromComparison(stock: stock)
            }
            update(list: updatedList)
            updateNavStockButtonToolbar()
            dismissPopover()
        }
    }

    /// Callback after async comparisonList reload and by StockChangeService if user rows were updated
    public func update(list newList: [Comparison]) {
        var selectedIndex = 0
        if !newList.isEmpty && scrollChartView.comparison.id > 0 {
            for (index, comparison) in newList.enumerated() where comparison.id == scrollChartView.comparison.id {
                selectedIndex = index
            }
        }
        self.list = newList
        tableView.reloadData()
        if self.list.count > selectedIndex {
            loadComparison(listIndex: selectedIndex)
        }
    }

    /// Called by AddStockController when a new stock is added
    public func insert(stock: Stock, isNewComparison: Bool) {
        Task {
            var stock = stock
            if isNewComparison || scrollChartView.comparison.stockList.isEmpty {
                await scrollChartView.updateComparison(newComparison: Comparison())
                stock.upColor = Stock.chartColors[0] // lightGreen
                stock.color = .red
            } else {
                // Skip colors already used by other stocks in this comparison or use gray
                var otherColors = Stock.chartColors
                for otherStock in scrollChartView.comparison.stockList {
                    // end before lastIndex to always keep gray as an option
                    for index in 0 ..< otherColors.count - 1 where otherStock.hasUpColor(otherColor: otherColors[index]) {
                        otherColors.remove(at: index)
                    }
                }
                stock.upColor = otherColors[0]
                stock.color = otherColors[0]
            }

            let updatedList = await scrollChartView.addToComparison(stock: stock)
            update(list: updatedList)
            dismissPopover()
        }
    }

    /// Add toggleListButton and buttons for each stock in this comparison
    private func updateNavStockButtonToolbar() {
        var buttons: [UIBarButtonItem] = [toggleListButton]
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))

        if scrollChartView.comparison.stockList.isEmpty == false {
            var menuActions = [UIAction]()
            for stock in scrollChartView.comparison.stockList {
                var buttonTitle = stock.ticker
                if scrollChartView.comparison.stockList.count == 1 || UIDevice.current.userInterfaceIdiom == .pad {
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
                tickerButton.tag = stock.id
                tickerButton.tintColor = stock.upColor
                buttons.append(tickerButton)

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
            shareMenuButton.menu = UIMenu(title: "", children: menuActions)

            let maxComparisonCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3

            if scrollChartView.comparison.stockList.count < maxComparisonCount {
                let compareButton = UIBarButtonItem(title: "+ compare",
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(compareStock))
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
    @objc func addStock(button: UIBarButtonItem) {
        let addStockController = AddStockController(style: .plain)
        addStockController.delegate = self
        addStockController.isNewComparison = true
        popoverPush(viewController: addStockController, from: button)
    }

    /// User clicked the "compare" button in the navStockButtonToolbar to add a stock to the current comparison
    @objc func compareStock(button: UIBarButtonItem) {
        let addStockController = AddStockController(style: .plain)
        addStockController.delegate = self
        addStockController.isNewComparison = false
        popoverPush(viewController: addStockController, from: button)
    }

    /// User clicked a ticker in navStockButtonToolbar to edit settings for the stock with stock.id == button.tag
    @objc func editStock(button: UIBarButtonItem) {
        let stockId = button.tag

        for stock in scrollChartView.comparison.stockList where stock.id == stockId {
            let chartOptionsController = ChartOptionsController(stock: stock, delegate: self)
            chartOptionsController.sparklineKeys = scrollChartView.comparison.sparklineKeys()
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
        scrollChartView.pxWidth = UIScreen.main.scale * scrollChartView.svWidth

        scrollChartView.clearChart() // clear prior render to avoid odd animation

        scrollChartView.layer.position = CGPoint(x: scrollChartView.layer.position.x + delta,
                                                 y: scrollChartView.layer.position.y)

        let shiftBars = Int(scrollChartView.layer.contentsScale
                               * delta/(scrollChartView.xFactor * scrollChartView.barUnit))

        scrollChartView.updateMaxPercentChange(barsShifted: -shiftBars) // shiftBars are + when delta is -
    }

    /// On iPad, presents the viewController in a popover with an arrow to the button. On iPhone, presents modal
    private func popoverPush(viewController: UIViewController, from button: UIBarButtonItem) {
        popOverNav = UINavigationController(rootViewController: viewController)
        let isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")
        popOverNav.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        popOverNav.modalPresentationStyle = .popover
        popOverNav.popoverPresentationController?.sourceView = view
        popOverNav.popoverPresentationController?.barButtonItem = button
        present(popOverNav, animated: true)
    }

    /// remove the topmost iPhone UIViewController or iPad UIPopoverController
    @objc func dismissPopover() {
        popOverNav.dismiss(animated: true)
    }
}
