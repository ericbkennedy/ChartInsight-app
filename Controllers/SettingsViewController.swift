//
//  SettingsViewController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/20/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

public enum SectionType: Int {
    case nightMode, stockList
}

@objcMembers
class SettingsViewController: UITableViewController {
    
    @objc var delegate: WatchlistViewController? = nil
    var list: [Comparison] = []
    let cellID = "settingsCell"
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(style: UITableView.Style) {
        super.init(style: style)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = UIColor.systemBackground
        
        tableView.setEditing(true, animated: false)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneEditing))
        navigationItem.rightBarButtonItem = doneButton
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            list = await Comparison.listAll() // reload list on each apperence so it reflects added stock
            await MainActor.run {
                tableView.reloadData()
            }
        }
    }
    
    @objc func doneEditing() {
        tabBarController?.selectedIndex = 0;
    }
    
    @objc func toggleNightDay() {
        
        let oldValue = UserDefaults.standard.bool(forKey: "darkMode")
        
        if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate {
            sceneDelegate.darkMode(isOn: !oldValue)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        
        var config = cell.defaultContentConfiguration()
        
        if indexPath.section == SectionType.nightMode.rawValue {
            config.text = "Night mode"
            let onOffSwitch = UISwitch()
            onOffSwitch.isOn = UserDefaults.standard.bool(forKey: "darkMode")
            onOffSwitch.addTarget(self, action: #selector(toggleNightDay), for: .touchUpInside)
            cell.accessoryView = onOffSwitch
                        
        } else if indexPath.row < list.count {
            let comparison = list[indexPath.row]
            config.text = comparison.title
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionType.nightMode.rawValue {
            return 1
        }
        return list.count
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == SectionType.stockList.rawValue
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if indexPath.section == SectionType.stockList.rawValue && editingStyle == .delete {
            if indexPath.row < list.count {
                let comparison = list[indexPath.row]
                comparison.deleteFromDb()
                Task {
                    list = await Comparison.listAll() // reload list on each apperence so it reflects added stock
                    await MainActor.run {
                        delegate?.needsReload = true
                        tableView.deleteRows(at: [indexPath], with: .fade)
                        tableView.reloadData()
                    }
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == SectionType.stockList.rawValue {
            return "Watchlist stocks"
        }
        return ""
    }
}

