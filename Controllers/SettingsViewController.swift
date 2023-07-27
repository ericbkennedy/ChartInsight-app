//
//  SettingsViewController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/20/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import MessageUI

public enum SectionType: Int, CaseIterable {
    case nightMode, stockList, contactSupport
}

class SettingsViewController: UITableViewController, MFMailComposeViewControllerDelegate {
    public var delegate: WatchlistViewController?
    private var list: [Comparison] = []
    private let cellID = "settingsCell"

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
            list = await DBActor.shared.comparisonList() // reload list on each apperence so it reflects added stock
            await MainActor.run {
                tableView.reloadData()
            }
        }
    }

    @objc func doneEditing() {
        tabBarController?.selectedIndex = 0
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
        } else if indexPath.section == SectionType.contactSupport.rawValue {
            config.text = "Contact Support"
            cell.accessoryType = .detailDisclosureButton
        } else if indexPath.row < list.count {
            let comparison = list[indexPath.row]
            config.text = comparison.title
        }

        cell.contentConfiguration = config
        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        let allSections = SectionType.allCases.count
        if MFMailComposeViewController.canSendMail() == false {
            return allSections - 1 // can't send mail so avoid showing Contact Support section
        }
        return allSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section != SectionType.stockList.rawValue {
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
                Task {
                    list = await comparison.deleteFromDb()
                    await MainActor.run {
                        delegate?.update(list: list)
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
        } else if section == SectionType.contactSupport.rawValue {
            return "Help"
        }
        return ""
    }

    /// User tapped accessory button to contact support -- use mailto instead of
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.section == SectionType.contactSupport.rawValue else { return }

        let composeVC = MFMailComposeViewController()
        composeVC.mailComposeDelegate = self

        // Configure the fields of the interface.
        composeVC.setToRecipients(["support@chartinsight.com"])
        composeVC.setSubject("ChartInsight App Feedback")

        let appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] ?? ""
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

        let messageBody = "\n\nApp Version: \(appVersion)\nDevice: \(deviceType)\niOS: \(UIDevice.current.systemVersion)"

        composeVC.setMessageBody(messageBody, isHTML: false)

        show(composeVC, sender: self)
    }

    /// Mail compose modal must be dismissed explicitly by the delegate
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        // Dismiss the mail compose view controller.
        controller.dismiss(animated: true, completion: nil)
    }
}
