//
//  AddStockController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/11/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class AddStockController: UITableViewController, UISearchBarDelegate {
    
    @objc var delegate: RootViewController?
    var list: [Stock]
    var searchBar : UISearchBar
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported since no storyboard or nib is used")
    }
    
    override init(style: UITableView.Style) {
        searchBar = UISearchBar()
        list = []
        delegate = nil // will be set later to RootViewController
        super.init(style: style)
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "stockCell")
        
        searchBar = UISearchBar(frame: .zero) //CGRectMake(0.0, 0.0, 300.0, 44.0))
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "stockCell", for: indexPath)
        if (list.count > indexPath.row) {
            let stock = list[indexPath.row]
            if stock.symbol != nil {
                label = stock.symbol + " "
            }
            if stock.name != nil {
                label += stock.name
            }
        }
        cell.textLabel?.text = label
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return list.count
    }
        
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let searchText = searchBar.text {
            // Avoid blocking keyboard animations by dispatching to another thread
            DispatchQueue.global(qos: .userInteractive).async {
                if let localList = Stock.find(searchText) {
                    DispatchQueue.main.async { // update UI on main
                        self.list.removeAll()
                        if (localList.isEmpty == false) {
                            self.list = localList
                        }
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    /// Clicking the done/return button or typing return on simulator will send the 1st stock in the list to the delegate
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard delegate != nil else { return }
        if (list.count > 0 && list[0].symbol.count > 0) {
            delegate?.insert(list[0]);
        }
    }
        
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.dismiss(animated: true)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard delegate != nil else { return }
        if (list.count > indexPath.row) {
            let selected = list[indexPath.row]
            
            if (selected.isKind(of: Stock.self) && selected.symbol.count > 0) {
                delegate?.insert(selected)
            } else { // user selected placeholder for no matches so reset search
                searchBar.text = ""
                list.removeAll()
                tableView.reloadData()
            }
        }
    }
}
