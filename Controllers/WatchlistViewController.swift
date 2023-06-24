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
    var progressIndicator: ProgressIndicator = ProgressIndicator(frame: .zero)
    var magnifier: UIImageView = UIImageView(frame: CGRectMake(0, 0, 100, 100))
    var needsReload: Bool = false // set by SettingsViewController after a comparison is deleted
    
    enum ZPosition: CGFloat {
        case tableView, scrollChartView, magnifier, progressIndicator
    }
    
    private let cellID = "cellId"
    private let padding = 5.0
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
        scrollChartView.layer.position = CGPointMake(tableViewWidthVisible, 0)
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
        navStockButtonToolbar.frame = CGRectMake(0, 0, width, toolbarHeight)
        
        // Remove toolbar background and top border
        navStockButtonToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        navStockButtonToolbar.setShadowImage(UIImage(), forToolbarPosition: .any) // top border

        if needsReload {
            reload(keepExistingComparison: true)
            needsReload = false
        }
        
        updateNavStockButtonToolbar()
        navigationItem.titleView = navStockButtonToolbar
        
        if (scrollChartView.svWidth == 0) { // initialize it on first view but not when tabs change
            scrollChartView.bounds = CGRectMake(0, 0, width, height)
            scrollChartView.resetDimensions()
            scrollChartView.createLayerContext()
            scrollChartView.setNeedsDisplay()
        }
        
        progressIndicator.layer.zPosition = ZPosition.progressIndicator.rawValue
        
        scrollChartView.progressIndicator = progressIndicator
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
    
    /// Called when app first loads (with listIndex == 0) or when user taps a tableView row
    func loadComparison(listIndex: Int) {
        scrollChartView.clearChart()
        progressIndicator.startAnimating()
        scrollChartView.comparison = list[listIndex]
        scrollChartView.loadChart()
        updateNavStockButtonToolbar()
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
    func isNewFrameSize(newSize: CGSize) -> Bool {
        let newWidth = newSize.width
        var newHeight = newSize.height - padding
        let safeAreaInsets = getSafeAreaInsets()
        
        toolbarHeight = 44
        statusBarHeight = 20
        if safeAreaInsets.top > statusBarHeight {
            statusBarHeight = safeAreaInsets.top
        }
        
        newHeight = newSize.height - statusBarHeight - 2 * toolbarHeight - padding - safeAreaInsets.bottom
        
        if (newHeight != height) {
            width = newWidth
            height = newHeight
            return true
        }
        return false
    }
    
    func resizeSubviews(newSize: CGSize) {
        navStockButtonToolbar.frame = CGRectMake(0, 0, newSize.width, toolbarHeight)
        progressIndicator.frame = CGRectMake(0, 0, newSize.width, 4)
        
        tableView.reloadData()
        
        let delta = scrollChartView.bounds.size.width - newSize.width
        let shiftBars = Int(scrollChartView.layer.contentsScale
                              * delta/(scrollChartView.xFactor * scrollChartView.barUnit))
        
        scrollChartView.updateMaxPercentChange(withBarsShifted: -shiftBars) // shiftBars are + when delta is -
        scrollChartView.bounds = CGRectMake(0, 0, width, height) // isNewFrameSize calculated height
        scrollChartView.resize()
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
        
        scrollChartView.resizeChartImage(2.0, withCenter: pinchMidpoint)
        scrollChartView.resizeChart(2.0)
    }
    
    /// Display an enlarged screenshot of the chart under the user's finger in the magnifier subview
    @objc func magnify(recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            scrollChartView.resetPressedBar()
        } else if recognizer.state == .ended {
            magnifier.isHidden = true
            return
        }
 
        let xPress = recognizer.location(in: scrollChartView).x - padding
        let yPress = recognizer.location(in: scrollChartView).y
        let midpoint: CGFloat = 50
        let magnifierWidth: CGFloat = 2 * midpoint
        let magnifierHeight: CGFloat = 2 * midpoint
        
        magnifier.frame = CGRectMake(recognizer.location(in: view).x - midpoint,
                                     yPress - magnifierHeight,
                                     magnifierWidth,
                                     magnifierHeight)
        
        magnifier.layer.borderColor = UIColor.lightGray.cgColor
        magnifier.layer.borderWidth = 1
        magnifier.layer.cornerRadius = midpoint
        magnifier.layer.masksToBounds = true
        
        // Note that this always returns some image, even when the user moves to the Y axis labels
        // the lift-up behavior should only show a context menu when the user lifts up while a bar is selected
        // SCC can handle this by setting pressedBar = nil during magnifyBarAtX
        magnifier.image = scrollChartView.magnifyBarAt(x: xPress, y: yPress)
        magnifier.isHidden = false
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
            scrollChartView.updateMaxPercentChange(withBarsShifted: deltaBars)
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
            pinchMidpointSum = pinchMidpointSum / pinchCount // avg smooths touch errors
            scrollChartView.resizeChartImage(recognizer.scale, withCenter: pinchMidpoint)
        } else {
            scrollChartView.resizeChart(recognizer.scale)
        }
    }
    
    /// Called by ChartOptionsController when chart color or type changes
    @objc func redraw(withStock: Stock) {
        if scrollChartView.comparison != nil {
            scrollChartView.comparison.saveToDb()
            if let barButtonItems = navStockButtonToolbar.items {
                for button in barButtonItems {
                    if button.tag == withStock.id {
                        button.tintColor = withStock.upColor
                    }
                }
                scrollChartView.redrawCharts()
            }
        }
    }
    
    /// Called after user taps the Trash icon in ChartOptionsController to delete a stock in a comparison
    @objc func deleteStock(_ stock: Stock) {
        let stockCountBeforeDeletion = scrollChartView.comparison.stockList.count

        scrollChartView.comparison.delete(stock: stock)
        
        if stockCountBeforeDeletion <= 1 {
            // delete comparison
            scrollChartView.comparison.deleteFromDb()
            reload(keepExistingComparison: false)
        } else {
            scrollChartView.redrawCharts()
            reload(keepExistingComparison: true)
        }
        updateNavStockButtonToolbar()
        popContainer()
    }
    
    /// Reload the stock comparison list in the tableView and redraw the scrollChartView
    @MainActor
    func reload(keepExistingComparison: Bool) {
        Task {
            list = await Comparison.listAll()
            tableView.reloadData()
            
            var comparisonToChart: Comparison? = nil
            if keepExistingComparison {
                comparisonToChart = scrollChartView.comparison
            } else if (list.count > 0) {
                comparisonToChart = list[0]
            }
            if comparisonToChart != nil {
                scrollChartView.clearChart()
                progressIndicator.startAnimating()
                scrollChartView.comparison = comparisonToChart
                updateNavStockButtonToolbar()
                scrollChartView.loadChart()
            }
        }
    }
    
    /// Callback after async comparisonList reload
    func update(list: [Comparison]) {
        self.list = list
        tableView.reloadData()
        if self.list.count > 0 {
            loadComparison(listIndex: 0)
        }
    }
    
    /// Called by AddStockController when a new stock is added
    func insert(stock: Stock, isNewComparison: Bool) {

        if isNewComparison || scrollChartView.comparison == nil {
            scrollChartView.comparison = Comparison()
            stock.upColor = Stock.chartColors[0] // lightGreen
            stock.color = .red
        } else {
            // Skip colors already used by other stocks in this comparison or use gray
            var otherColors = Stock.chartColors
            for otherStock in scrollChartView.comparison.stockList {
                for i in 0 ..< otherColors.count - 1 {  // end before last color (gray)
                    if otherStock.hasUpColor(otherColor: otherColors[i]) {
                        otherColors.remove(at: i)
                    }
                }
            }
            stock.upColor = otherColors[0]
            stock.color = otherColors[0]
        }
        
        scrollChartView.comparison.add(stock)
        reload(keepExistingComparison: true)
        popContainer()
    }
    
    /// Add toggleListButton and buttons for each stock in this comparison
    func updateNavStockButtonToolbar() {
        var buttons: [UIBarButtonItem] = [toggleListButton]
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))
        
        if scrollChartView.comparison != nil {
            for stock in scrollChartView.comparison.stockList {
                let tickerButton = UIBarButtonItem(title: stock.symbol,
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(editStock))
                tickerButton.tag = stock.id
                tickerButton.tintColor = stock.upColor
                buttons.append(tickerButton)
            }
            let maxComparisonCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3
            
            if scrollChartView.comparison.stockList.count < maxComparisonCount {
                let compareButton = UIBarButtonItem(title: "+ compare",
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(compareStock))
                // Reduce font size of "+ compare" text
                compareButton.setTitleTextAttributes([ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10) ], for: .normal)
                compareButton.setTitleTextAttributes([ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10) ], for: .highlighted)
                buttons.append(compareButton)
            }
        }
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))
        navStockButtonToolbar.items = buttons
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
                
        for stock in scrollChartView.comparison.stockList {
            if stock.id == stockId {
                let chartOptionsController = ChartOptionsController(style: .grouped)
                chartOptionsController.sparklineKeys = scrollChartView.comparison.sparklineKeys()
                chartOptionsController.stock = stock
                chartOptionsController.delegate = self
                popoverPush(viewController: chartOptionsController, from: button)
                break
            }
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
        
        scrollChartView.layer.position = CGPointMake(scrollChartView.layer.position.x + delta,
                                                     scrollChartView.layer.position.y)
                
        let shiftBars = Int(scrollChartView.layer.contentsScale
                               * delta/(scrollChartView.xFactor * scrollChartView.barUnit))
         
         scrollChartView.updateMaxPercentChange(withBarsShifted: -shiftBars) // shiftBars are + when delta is -
    }
    
    /// On iPad, this presents the viewController in a popover with an arrow to the button. On iPhone, it appears as a modal
    func popoverPush(viewController: UIViewController, from button: UIBarButtonItem) {
        popOverNav = UINavigationController(rootViewController: viewController)
        popOverNav.modalPresentationStyle = .popover
        popOverNav.popoverPresentationController?.sourceView = view
        popOverNav.popoverPresentationController?.barButtonItem = button
        present(popOverNav, animated: true)
        
    }
    
    /// remove the topmost iPhone UIViewController or iPad UIPopoverController
    @objc func popContainer() {
        popOverNav.dismiss(animated: true)
    }
}
