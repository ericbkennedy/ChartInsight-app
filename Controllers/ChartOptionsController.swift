//
//  ChartOptionsController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/25/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class ChartOptionsController: UITableViewController {
    var stock: Stock
    var delegate: WatchlistViewController?
    var sparklineKeys: [String] = []

    private enum SectionType: Int {
        case chartType, chartColor, financials, technicals, setDefaults
    }

    private enum TechnicalType: String, CaseIterable {
        case sma50, sma200, bollingerBand220
    }

    private var normalCellId = "normalCell"
    private var chartStyleControlCellId = "chartStyleControlCell"

    private var defaultsActionText = "Use These Settings For New Charts" // will be updated after tap
    private var doneButton = UIBarButtonItem(systemItem: .done)
    private var sections = ["", "Color", "Financials", "Technicals", "Defaults"]
    private var fundamentalDescription = "EarningsPerShareBasic,CIRevenuePerShare,CINetCashFromOpsPerShare"
    private var addFundamentalRowIndex = -1 // Hide Add Fundamental row unless current list is less than max
    private var segmentFrame = CGRect(x: 0, y: 0, width: 320, height: 44) // min size (iPad portrait)
    private var typeSegmentedControl: ChartStyleControl
    private var colorSegmentedControl: ChartStyleControl
    private var listedMetricKeyString = ""
    private var listedMetricKeys: [String] = []
    private var listedMetricsEnabled: [Bool] = [] // parallel array to preseve sort

    /// Desiginated initializer set stock and delegate to avoid optional values
    init(stock: Stock, delegate: WatchlistViewController) {
        self.stock = stock
        self.delegate = delegate
        typeSegmentedControl = ChartStyleControl(type: .chartType, frame: segmentFrame, stock: stock)
        colorSegmentedControl = ChartStyleControl(type: .color, frame: segmentFrame, stock: stock)
        super.init(style: .plain)
        typeSegmentedControl.delegate = self
        colorSegmentedControl.delegate = self
    }

    ///  Initializer required by parent class for use with storyboards
    required convenience init?(coder aDecoder: NSCoder) {
        self.init(stock: Stock(), delegate: WatchlistViewController())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(stock.ticker) Chart Options"
        view.backgroundColor = UIColor.systemGroupedBackground

        // Add metrics from other chart in the comparison set
        for key in sparklineKeys {
            listedMetricKeyString.append("\(key), ")
        }
        listedMetricKeyString.append(stock.fundamentalList)
        updateListedMetrics()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: normalCellId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: chartStyleControlCellId)
        tableView.backgroundColor = UIColor.secondarySystemGroupedBackground
        tableView.separatorStyle = .none

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissPopover))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteStock))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.red
    }

    /// User clicked Trash icon
    @objc func deleteStock() {
        delegate?.deleteStock(stock)
    }

    /// User clicked Done button (they can also dismiss the popover manually)
    @objc func dismissPopover() {
        delegate?.dismissPopover()
    }

    /// AddFundamentalViewController will call this with the metric key after the user has selected another metric
    func addedFundamental(key: String) {
        stock.addToFundamentals(key)
        listedMetricKeys.removeAll()
        listedMetricsEnabled.removeAll()
        listedMetricKeyString = listedMetricKeyString.appending(key)
        updateListedMetrics()

        tableView.reloadData()
        delegate?.reload(withStock: stock)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cellType = normalCellId
        if indexPath.section == SectionType.chartType.rawValue || indexPath.section == SectionType.chartColor.rawValue {
            cellType = chartStyleControlCellId
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: cellType, for: indexPath)

        if indexPath.section == SectionType.chartType.rawValue {
            typeSegmentedControl.frame = segmentFrame
            cell.addSubview(typeSegmentedControl)
        } else if indexPath.section == SectionType.chartColor.rawValue {
            colorSegmentedControl.frame = segmentFrame
            cell.addSubview(colorSegmentedControl)
        } else {
            var config = cell.defaultContentConfiguration()
            if indexPath.section == SectionType.financials.rawValue {
                if indexPath.row == addFundamentalRowIndex {
                    config.text = "        + Add Financial Metric"
                    cell.accessoryView = nil
                } else if indexPath.row < listedMetricKeys.count {
                    cell.selectionStyle = .none
                    config.text = Metrics.shared.title(for: listedMetricKeys[indexPath.row])
                    if let image = image(isMovingAverage: false, color: stock.upColorHalfAlpha) {
                        config.image = image
                    }
                    let onOffSwitch = UISwitch()
                    onOffSwitch.addTarget(self, action: #selector(fundamentalToggled), for: .touchUpInside)
                    onOffSwitch.tag = indexPath.row
                    if indexPath.row < listedMetricsEnabled.count && listedMetricsEnabled[indexPath.row] {
                        onOffSwitch.isOn = true
                    }
                    cell.accessoryView = onOffSwitch
                }
            } else if indexPath.section == SectionType.technicals.rawValue {
                cell.selectionStyle = .none
                let onOffSwitch = UISwitch()
                onOffSwitch.addTarget(self, action: #selector(technicalToggled), for: .touchUpInside)
                onOffSwitch.tag = indexPath.row
                cell.accessoryView = onOffSwitch
                if indexPath.row == 0 {
                    config.text = "50 Period Simple Moving Avg"
                    if let image = image(isMovingAverage: true, color: stock.colorInverseHalfAlpha) {
                        config.image = image
                    }
                    onOffSwitch.isOn = stock.technicalList.contains(TechnicalType.sma50.rawValue)
                } else if indexPath.row == 1 {
                    config.text = "200 Period Simple Moving Avg"
                    if let image = image(isMovingAverage: true, color: stock.upColorHalfAlpha) {
                        config.image = image
                    }
                    onOffSwitch.isOn = stock.technicalList.contains(TechnicalType.sma200.rawValue)
                } else {
                    config.text = "Bollinger Bands 2, 20"
                    if let image = image(isMovingAverage: true, color: stock.upColorHalfAlpha) {
                        config.image = image
                    }
                    onOffSwitch.isOn = stock.technicalList.contains(TechnicalType.bollingerBand220.rawValue)
                }
            } else if indexPath.section == SectionType.setDefaults.rawValue {
                config.text = defaultsActionText
                cell.accessoryView = nil
            }
            cell.contentConfiguration = config
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    /// User tapped a row - either toggle a switch, push the AddFundamentalController onto the navigation stack
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == SectionType.financials.rawValue && indexPath.row == addFundamentalRowIndex {
            addMetric()
        } else if indexPath.section == SectionType.setDefaults.rawValue {
            updateDefaults()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionType.financials.rawValue && stock.hasFundamentals {
            var fundamentalRows = listedMetricKeys.count
            let maxFundamentals = UIDevice.current.userInterfaceIdiom == .pad ? 10 : 5
             if maxFundamentals > fundamentalRows || addFundamentalRowIndex > 0 {
                 addFundamentalRowIndex = fundamentalRows // index value before adding
                 fundamentalRows += 1 // allow adding another fundamental
             }
             return fundamentalRows
        } else if section == SectionType.technicals.rawValue {
            return TechnicalType.allCases.count
        }
        return 1
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section < sections.count {
            return sections[section]
        }
        return ""
    }

    @objc func technicalToggled(onOffSwitch: UISwitch) {
        let index = onOffSwitch.tag
        guard index < TechnicalType.allCases.count else { return }

        let typeToggled = TechnicalType.allCases[index].rawValue
        if stock.technicalList.contains(typeToggled) {
            stock.removeFromTechnicals(typeToggled)
        } else {
            stock.addToTechnicals(typeToggled)
        }
        tableView.reloadData()
        delegate?.redraw(withStock: stock)
    }

    @objc func fundamentalToggled(onOffSwitch: UISwitch) {
        let index = onOffSwitch.tag
        guard index >= 0 && index < listedMetricKeys.count else { return }

        let typeToggled = listedMetricKeys[index]
        if stock.fundamentalList.contains(typeToggled) {
            listedMetricsEnabled[index] = false
            stock.removeFromFundamentals(typeToggled)
        } else {
            listedMetricsEnabled[index] = true
            stock.addToFundamentals(typeToggled)
        }
        tableView.reloadData()
        delegate?.reload(withStock: stock)  // requires call to server for new fundamental
    }

    /// Thumbnail image of moving average curve or fundamental bars
    func image(isMovingAverage: Bool, color: UIColor) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let img = renderer.image { ctx in
            if isMovingAverage {
                ctx.cgContext.setStrokeColor(color.cgColor)
                ctx.cgContext.setLineJoin(.round)
                ctx.cgContext.setLineWidth(1)
                ctx.cgContext.move(to: CGPoint(x: 1, y: 20))
                ctx.cgContext.addCurve(to: CGPoint(x: 40, y: 13),
                                       control1: CGPoint(x: 15, y: 32),
                                       control2: CGPoint(x: 25, y: 15))
                ctx.cgContext.drawPath(using: .stroke)
            } else { // Fundamental bars shown above the stock chart
                ctx.cgContext.setFillColor(UIColor(red: 1, green: 0, blue: 0, alpha: 0.6).cgColor)
                ctx.cgContext.addRect(CGRect(x: 13, y: 20, width: 5, height: 3))
                ctx.cgContext.fill([CGRect(x: 13, y: 20, width: 5, height: 3)])
                ctx.cgContext.setFillColor(color.cgColor)
                ctx.cgContext.fill([CGRect(x: 1, y: 13, width: 5, height: 7),
                                    CGRect(x: 7, y: 16, width: 5, height: 4),
                                    CGRect(x: 19, y: 10, width: 5, height: 10),
                                    CGRect(x: 25, y: 8, width: 5, height: 12),
                                    CGRect(x: 31, y: 5, width: 5, height: 15)])
            }
        }
        return img
    }

    /// Update the array of metric keys and parallel array listedMetricsEnabled indicating if the metric is enabled.
    func updateListedMetrics() {
        for category in Metrics.shared.metrics {
            for metric in category {
                let key = metric[0]
                if listedMetricKeyString.contains(key) {
                    let isEnabled = stock.fundamentalList.contains(key)
                    listedMetricKeys.append(key)
                    listedMetricsEnabled.append(isEnabled)
                }
            }
        }
    }

    /// User clicked on Update defaults row
    @objc func updateDefaults() {
        UserDefaults.standard.setValue(stock.chartType.rawValue, forKey: "chartTypeDefault")
        UserDefaults.standard.setValue(stock.technicalList, forKey: "technicalDefaults")
        UserDefaults.standard.setValue(stock.fundamentalList, forKey: "fundamentalDefaults")
        defaultsActionText = "Default Chart Settings Saved"
        tableView.reloadData()
    }

    /// User clicked on chartStyleControl to change the chart type
    @objc func chartTypeChanged(to chartTypeIndex: Int) {
        if let newChartType = ChartType(rawValue: chartTypeIndex) {
            stock.chartType = newChartType
            colorSegmentedControl.createSegments(for: newChartType)
            tableView.reloadData()
            delegate?.redraw(withStock: stock)
        }
    }

    /// User clicked on chartStyleControl to change the chart color
    @objc func chartColorChanged(to colorIndex: Int) {
        if colorIndex == 0 {
            stock.upColor = Stock.chartColors[0]
            stock.color = UIColor.red
        } else if colorIndex < Stock.chartColors.count {
            stock.upColor = Stock.chartColors[colorIndex]
            stock.color = stock.upColor
        }
        tableView.reloadData()
        delegate?.redraw(withStock: stock)
    }

    /// User tapped "Add Financial Metric" button so present AddFundamentalController
    @objc func addMetric() {
        let addFundamentalController = AddFundamentalController(style: .plain)
        addFundamentalController.delegate = self
        var otherMetrics: [[[String]]] = []
        for category in Metrics.shared.metrics {
            var availableMetrics: [[String]] = []
            for metric in category {
                let key = metric[0]
                if listedMetricKeyString.contains(key) == false {
                    // Only allow adding metrics which aren't listed on ChartOptionsController
                    if stock.hasFundamentals {
                        availableMetrics.append(metric)
                    }
                }
            }
            otherMetrics.append(availableMetrics)
        }
        addFundamentalController.metrics = otherMetrics
        navigationController?.pushViewController(addFundamentalController, animated: true)
    }
}
