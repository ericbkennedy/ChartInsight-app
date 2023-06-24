//
//  WatchlistViewController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/23/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class WatchlistViewController: UITableViewController {
    var gregorian: Calendar = Calendar(identifier: .gregorian) // injected into ScrollChartView
    var progressIndicator: ProgressIndicator = ProgressIndicator(frame: .zero)
    var magnifier: UIImageView = UIImageView(frame: CGRectMake(0, 0, 100, 100))
    
    let cellID = "cellId"
    let bottomPadding = 4.0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var rowHeight: CGFloat = 0
    var statusBarHeight: CGFloat = 0 // set using safeAreaInsets
    var toolbarHeight: CGFloat = 0
    var tableViewWidthVisible: CGFloat = 0
    var lastShift: CGFloat = 0
    var pinchCount: CGFloat = 0
    var pinchMidpointSum: CGFloat = 0
    var needsReload: Bool = false // set by SettingsViewController after a comparison is deleted
    
    var popOverNav = UINavigationController() // nav within popover
    var doubleTapRecognizer = UITapGestureRecognizer()
    var longPressRecognizer = UILongPressGestureRecognizer()
    var panGestureRecognizer = UIPanGestureRecognizer()
    var pinchGestureRecognizer = UIPinchGestureRecognizer()
    var addStockButton = UIBarButtonItem(systemItem: .add)
    var addStockToolbar = UIToolbar() // in tableView header
    var toggleListButton: UIBarButtonItem? = nil
    var navStockButtonToolbar = UIToolbar() // will be navigationItem.titleView
    
    var scrollChartView = ScrollChartView()
    
    var list: [Comparison] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        
        tableViewWidthVisible = UIDevice.current.userInterfaceIdiom == .phone ? 66 : 100
        rowHeight = UIDevice.current.userInterfaceIdiom == .phone ? 40 : 44
                
        scrollChartView.layer.anchorPoint = .zero // allows bounds = frame
        scrollChartView.layer.position = CGPointMake(tableViewWidthVisible, 0)
        scrollChartView.gregorian = gregorian
        view.addSubview(scrollChartView)
        
        doubleTapRecognizer.addTarget(self, action: #selector(doubleTap))
        
        toggleListButton = UIBarButtonItem(image: UIImage(named: "toggleList"),
                                           style: .plain,
                                           target: self,
                                           action: #selector(toggleList))

        navigationItem.titleView = navStockButtonToolbar
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isNewFrameSize(newSize: view.frame.size) {
            resizeSubviews(newSize: view.frame.size)
        }
        
        scrollChartView.bounds = CGRectMake(0, 0, width, height - bottomPadding);
        scrollChartView.resetDimensions()
        scrollChartView.createLayerContext()
        scrollChartView.layer.zPosition = 1
        scrollChartView.setNeedsDisplay()
        scrollChartView.progressIndicator = progressIndicator
        scrollChartView.addGestureRecognizer(doubleTapRecognizer)
        view.layer.setNeedsDisplay()
        
        print(self.view.frame.size)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.list.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        
        var config = cell.defaultContentConfiguration()
        let comparison = self.list[indexPath.row]

        config.text = comparison.title
        cell.contentConfiguration = config
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if list.count > indexPath.row {
            loadComparisonAt(row: indexPath.row)
        }
    }
    
    func loadComparisonAt(row: Int) {
        scrollChartView.clearChart()
        progressIndicator.startAnimating()
        scrollChartView.comparison = list[row]
        scrollChartView.loadChart()
        resetToolbar()
    }
    
    /// Determine if the frame size has changed and subviews must be resized
    func isNewFrameSize(newSize: CGSize) -> Bool {
        let newWidth = newSize.width
        var newHeight = newSize.height
        
        let safeAreaInsets = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .map({$0 as? UIWindowScene})
            .compactMap({$0}).first?.windows.filter({$0.isKeyWindow}).first?.safeAreaInsets ?? .zero
        
        print(safeAreaInsets)
        
        toolbarHeight = 44
        statusBarHeight = 20
        
        if safeAreaInsets.top > statusBarHeight {
            statusBarHeight = safeAreaInsets.top
        }
        
        newHeight = newSize.height - statusBarHeight - 2 * toolbarHeight - safeAreaInsets.bottom
        
        if (newWidth != width) {
            width = newWidth
            height = newHeight
            return true
        }
        return false
    }
    
    func resizeSubviews(newSize: CGSize) {
        navStockButtonToolbar.frame = CGRectMake(0, 0, newSize.width, toolbarHeight)
        progressIndicator.frame = CGRectMake(0, 0, newSize.width, 4)
        // EK is this necessary
        scrollChartView.layer.position = CGPointMake(scrollChartView.layer.position.x, 0)
        
        tableView.reloadData()
        
        let delta = scrollChartView.bounds.size.width - newSize.width
        let shiftBars = Int(scrollChartView.layer.contentsScale
                              * delta/(scrollChartView.xFactor * scrollChartView.barUnit))
        
        scrollChartView.updateMaxPercentChange(withBarsShifted: -shiftBars) // shiftBars are + when delta is -
        scrollChartView.bounds = CGRectMake(0, 0, newSize.width, newSize.height)
        scrollChartView.resize()
    }
    
    
    func reload(stock: Stock) {
        
    }
    
    ///
    @objc func doubleTap(recognizer: UITapGestureRecognizer) {
        recognizer.cancelsTouchesInView = true
        
        let pinchMidpoint = recognizer.location(in: view).x - scrollChartView.layer.position.x - 5
        
        scrollChartView.resizeChartImage(2.0, withCenter: pinchMidpoint)
        scrollChartView.resizeChart(2.0)
        
    }
    
    /// called by ChartOptionsController when chart color or type changes
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
    
    @objc(deleteStock:)
    func delete(stock: Stock) {
        let stockCountBeforeDeletion = scrollChartView.comparison.stockList.count

        scrollChartView.comparison .delete(stock: stock)
        
        if stockCountBeforeDeletion <= 1 {
            // delete comparison
            scrollChartView.comparison.deleteFromDb()
            reload(keepExistingComparison: false)
        } else {
            scrollChartView.redrawCharts()
            reload(keepExistingComparison: true)
        }
        resetToolbar()
        popContainer()
    }
    
    @MainActor
    func reload(keepExistingComparison: Bool) {
        Task {
            list = await Comparison.listAll()
            
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
                resetToolbar()
                scrollChartView.loadChart()
            }
            
        }
        
    }
    
    /// Callback after async comparisonList reload
    func update(list: [Comparison]) {
        self.list = list
        tableView.reloadData()
        
        if self.list.count > 0 {
            let comparisonToChart = self.list[0]
            progressIndicator.startAnimating()
            scrollChartView.comparison = comparisonToChart
            resetToolbar()
            scrollChartView.loadChart()
        }
    }
    
    /// Called by AddStockController when a new stock is added
    func insert(stock: Stock, isNewComparison: Bool) {
        var otherColors = Stock.chartColors
        let lightGreen = otherColors[0]

        if isNewComparison || scrollChartView.comparison == nil {
            scrollChartView.comparison = Comparison()
        } else {
            // TODO: Use a different color than other stocks
        }
        
        stock.upColor = otherColors[0]
        if stock.hasUpColor(otherColor: lightGreen) {
            stock.color = UIColor.red
        } else {
            stock.color = otherColors[0]
        }
        
        scrollChartView.comparison.add(stock)
        reload(keepExistingComparison: true)
        popContainer()
    }
    
    func resetToolbar() {
        var buttons: [UIBarButtonItem] = []
        if toggleListButton != nil {
            buttons.append(toggleListButton!)
        }
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))
        
        let maxComparisonCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3
        
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
            
            if scrollChartView.comparison.stockList.count < maxComparisonCount {
                let compareButton = UIBarButtonItem(title: "compare",
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(compareStock))
                
                buttons.append(compareButton)
            }
        }
        buttons.append(UIBarButtonItem(systemItem: .flexibleSpace))
        navStockButtonToolbar.items = buttons
    }
    
    @objc func compareStock(button: UIBarButtonItem) {
        let addStockController = AddStockController(style: .plain)
        addStockController.delegate = self
        addStockController.isNewComparison = false
        popoverPush(viewController: addStockController, from: button)
    }
    
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
