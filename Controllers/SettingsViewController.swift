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
    private let nightModeCellID = "nightModeCell"
    private let stockCellID = "stockCell"
    private let supportCellID = "supportCell"
    private var viewModel: WatchlistViewModel!

    /// Designated initializer
    init(watchlistViewModel: WatchlistViewModel) {
        viewModel = watchlistViewModel
        super.init(style: .plain)
    }

    /// Required for storyboards which are not used for this view controller
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = UIColor.systemBackground

        tableView.setEditing(true, animated: false)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: nightModeCellID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: stockCellID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: supportCellID)
        tableView.accessibilityIdentifier = AccessibilityId.Settings.tableView

        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneEditing))
        navigationItem.rightBarButtonItem = doneButton
    }

    /// Reload the tableView each time the view appears to ensure it is in sync with the viewModel data source
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData()
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

        var cell: UITableViewCell

        if indexPath.section == SectionType.nightMode.rawValue {
            cell = tableView.dequeueReusableCell(withIdentifier: nightModeCellID, for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Night mode"
            let onOffSwitch = UISwitch()
            onOffSwitch.isOn = UserDefaults.standard.bool(forKey: "darkMode")
            onOffSwitch.addTarget(self, action: #selector(toggleNightDay), for: .touchUpInside)
            cell.accessoryView = onOffSwitch
            cell.contentConfiguration = config

        } else if indexPath.section == SectionType.contactSupport.rawValue {
            cell = tableView.dequeueReusableCell(withIdentifier: nightModeCellID, for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = AccessibilityId.Settings.contactSupport
            cell.accessoryType = .detailDisclosureButton
            cell.contentConfiguration = config

        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: stockCellID, for: indexPath)
            var config = cell.defaultContentConfiguration()
            if indexPath.row < viewModel.listCount {
                config.text = viewModel.title(for: indexPath.row)
            }
            cell.contentConfiguration = config
        }
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
        return viewModel.listCount
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == SectionType.stockList.rawValue
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == SectionType.stockList.rawValue {
            return .delete
        }
        return .none
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == SectionType.stockList.rawValue else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [unowned self] _, _, completionHandler in
            viewModel.delete(at: indexPath.row)
            // Note: viewDidAppear() must call tableView.reloadData() to ensure tableView is in sync with viewModel
            tableView.deleteRows(at: [indexPath], with: .fade)
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == SectionType.stockList.rawValue {
            return AccessibilityId.Settings.watchlistSection
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
