//
//  AddStockController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/11/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class AddStockController: UITableViewController, UISearchBarDelegate {
    
    var delegate: WatchlistViewController? = nil
    var isNewComparison: Bool = false
    var list: [Stock] = []
    var searchBar = UISearchBar()
    let cellID = "stockCell"
    
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
        
        searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = self
        searchBar.autocorrectionType = .no
        searchBar.showsCancelButton = true // make it easier to dismiss?
        tableView.tableHeaderView = searchBar
        searchBar.sizeToFit()
        searchBar.returnKeyType = .done
        navigationItem.title = "Enter stock ticker or company name";
    }
    
    override func viewDidAppear(_ animated: Bool) {
        searchBar.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        searchBar.resignFirstResponder()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var label = ""
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        if (list.count > indexPath.row) {
            let stock = list[indexPath.row]
            if stock.ticker != "" {
                label = stock.ticker + " "
            }
            if stock.name != "" {
                label += stock.name
            }
        }
        var config = cell.defaultContentConfiguration()
        config.text = label
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return list.count
    }
        
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let searchText = searchBar.text {

            Task(priority: .high) {
                let localList = await DBActor.shared.findStock(search: searchText)
                
                await MainActor.run {
                    self.list.removeAll()
                    if (localList.isEmpty == false) {
                        self.list = localList
                    }
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    /// Clicking the done/return button or typing return on simulator will send the 1st stock in the list to the delegate
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard delegate != nil else { return }
        if (list.count > 0 && list[0].ticker.count > 0) {
            delegate?.insert(stock: list[0], isNewComparison: isNewComparison);
        }
    }
        
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.dismiss(animated: true)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard delegate != nil else { return }
        if (list.count > indexPath.row) {
            let selected = list[indexPath.row]
            
            if (selected.isKind(of: Stock.self) && selected.ticker.count > 0) {
                delegate?.insert(stock: selected, isNewComparison: isNewComparison);
            } else { // user selected placeholder for no matches so reset search
                searchBar.text = ""
                list.removeAll()
                tableView.reloadData()
            }
        }
    }
}
