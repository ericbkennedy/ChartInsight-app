//
//  ChildTableViewController.swift
//  ChartInsight
//
//  List of stock comparisons within parent ViewController WatchlistViewController.
//
//  Created by Eric Kennedy on 8/20/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

final class ChildTableViewController: UITableViewController {
    private let cellID = "cellId"
    private var viewModel: WatchlistViewModel!
    private var comparisonListToolbar = UIToolbar() // in tableView header
    private var newComparisonButton = UIBarButtonItem(systemItem: .add)

    /// Designated initializer
    init(watchlistViewModel: WatchlistViewModel) {
        viewModel = watchlistViewModel
        super.init(style: .plain)
    }

    /// Required for storyboards which this view controller doesn't use
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0 // aligns upper border with ScrollChartView divider
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        tableView.accessibilityIdentifier = AccessibilityId.Watchlist.tableView

        newComparisonButton.target = self // will forward to parent to keep compiler happy
        newComparisonButton.action = #selector(newComparison)
        newComparisonButton.accessibilityIdentifier = AccessibilityId.Watchlist.newComparisonButton
        comparisonListToolbar.items = [newComparisonButton]
        comparisonListToolbar.setShadowImage(UIImage(), forToolbarPosition: .any) // top border
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.listCount
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = viewModel.title(for: indexPath.row)
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.didSelectRow(at: indexPath.row)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UIDevice.current.userInterfaceIdiom == .phone ? 40 : 44
    }

    /// "+" add button in tableView header (wrapped in a UIToolbar)
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return comparisonListToolbar
    }

    /// Have the parent watchlistViewController handle the action so it can present a popover from the button on iPads
    @objc func newComparison(button: UIBarButtonItem) {
        if parent?.responds(to: #selector(newComparison)) == true {
            parent?.perform(#selector(newComparison), with: button)
        }
    }
}
