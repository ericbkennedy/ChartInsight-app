//
//  AddFundamentalController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/20/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

let sections = ["Income Statement", "Cash Flow", "Balance Sheet"]

class AddFundamentalController: UITableViewController {

    var delegate: ChartOptionsController?
    var metrics: [[[String]]] = [] // set by ChartOptionsController
    let cellID = "metricCell"

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init(style: UITableView.Style) {
        super.init(style: style)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if metrics.count > section {
            return metrics[section].count
        }
        return 0
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

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80 // Additional height for description
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        let item = metrics[indexPath.section][indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item[1]
        config.secondaryText = item[2]
        config.secondaryTextProperties.numberOfLines = 2
        config.secondaryTextProperties.lineBreakMode = .byWordWrapping
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let item = metrics[indexPath.section][indexPath.row]
        guard item.count > 0 else { return }

        let metricKey = item[0]
        self.navigationController?.popViewController(animated: false)
        delegate?.addedFundamental(key: metricKey)
    }

}
