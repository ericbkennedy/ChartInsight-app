//
//  WebViewController.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/30/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    var progressView = UIProgressView(progressViewStyle: .default)
    private var webObservation: NSKeyValueObservation?
    var delegate: WatchlistViewController?
    var backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: nil, action: #selector(goBack))
    var watchlistButton = UIBarButtonItem(title: "View on Watchlist", style: .plain, target: nil, action: #selector(viewOnWatchlist))
    var refreshButton: UIBarButtonItem!
    var comparison: Comparison? // if the user browses a stock part of an existing comparison
    var stock: Stock? // if the user browses a stock on chartinsight.com that isn't in the watchlist
    let defaultURLString: String = "https://www.chartinsight.com"
    var urlString: String = ""

    override func loadView() {
        edgesForExtendedLayout = [] // don't let webView underlap tab bar as cookie dialogs appear half-hidden
        let configuration = WKWebViewConfiguration()
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            configuration.applicationNameForUserAgent = "ChartInsight/\(version)"
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        view = webView
        webView.navigationDelegate = self

        backButton.target = self
        watchlistButton.target = self
        refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: webView, action: #selector(webView.reload))
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [self.backButton, spacer, refreshButton]
        navigationController?.isToolbarHidden = false
        navigationController?.navigationBar.isHidden = true // hide navigation bar since the lower toolbar is easier to access
    }

    override func viewDidLoad() {
        view.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false // will add constraints manually
        progressView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        progressView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        progressView.layoutIfNeeded()

        webView.insetsLayoutMarginsFromSafeArea = true
        // Inset scrollable area of webView so it doesn't underlap the tabBar
        webView.scrollView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: tabBarController!.tabBar.frame.height, right: 0.0)
        webView.allowsBackForwardNavigationGestures = false
        webView.uiDelegate = self // open all links in main frame with @objc(webView:createWebViewWithConfiguration...)
        backButton.isEnabled = false

        // Uncomment to enable passing messages from web JS to Swift
        // let contentController = webView.configuration.userContentController
        // contentController.add(self, name: "ciAppHandler")
    }

    override func viewDidAppear(_ animated: Bool) {
        webObservation = webView.observe(\WKWebView.estimatedProgress, options: .new) { _, change in
            if let currentProgress = change.newValue {
                if currentProgress < 1 {
                    self.progressView.progress = Float(currentProgress)
                } else {
                    self.progressView.isHidden = true
                }
            }
        }
        if urlString.isEmpty {
            urlString = defaultURLString // switching to another tab and back will load defaultURLString
        }
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Clear urlString so a non-empty urlString in a future viewDidAppear is a signal to load the URL
    override func viewDidDisappear(_ animated: Bool) {
        urlString = ""
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progressView.isHidden = false
    }

    /// If the user is browsing chartinsight.com, search for a stock ticker and update toolbar with a button to add to watchlist
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.absoluteString.contains("chartinsight.com") == true else { return }
        backButton.isEnabled = webView.canGoBack
        progressView.isHidden = true
        watchlistButton.title = "" // reset and allow the evaluateJavaScript closure to set association if found
        comparison = nil
        stock = nil

        webView.evaluateJavaScript("document.querySelector('#leftTickTicker')?.innerHTML") { (result, error) in
            guard error == nil, let ticker = result as? String else { return }

            Task {
                var buttonText = ""
                let comparisonList = await DBActor.shared.comparisonList(ticker: ticker)
                if comparisonList.isEmpty {
                    if let stock = await DBActor.shared.getStock(ticker: ticker) {
                        buttonText = "Add \(ticker) to Watchlist"
                        self.stock = stock
                    }
                } else {
                    self.comparison = comparisonList[0]
                    buttonText = "View \(ticker) on Watchlist"
                }

                if buttonText.count > 0 {
                    await MainActor.run {
                        self.watchlistButton.title = buttonText
                        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
                        self.toolbarItems = [self.backButton, spacer, self.watchlistButton, spacer, self.refreshButton]
                    }
                }
            }
        }
    }

    @objc func goBack() {
        webView.goBack()
    }

    /// User clicked button to add a new stock to the watchlist or view an existing stock comparison
    @objc func viewOnWatchlist() {
        if let comparison = comparison {
            delegate?.load(comparisonToChart: comparison)
        } else if let stock = stock {
            delegate?.insert(stock: stock, isNewComparison: true)
        }
        tabBarController?.selectedIndex = 0 // switch to watchlist
    }

    /// Open all links in the current window (instead of an error for links with target=_blank)
    @objc func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                       for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let frame = navigationAction.targetFrame,
            frame.isMainFrame {
            return nil
        }
        webView.load(navigationAction.request)
        return nil
    }

    deinit {
        webObservation = nil
    }
}

// Uncomment contentController = webView.configuration.userContentController in viewDidLoad along with the following to
// allow sending messages from JS on chartinsight.com to Swift. This will probably used for authentication
// extension WebViewController: WKScriptMessageHandler {
//    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
//        guard let dict = message.body as? [String : AnyObject] else { return }
//        // should be // ["ticker": AAPL, "name": Apple]
//
//        if let ticker = dict["ticker"], let name = dict["name"] {
//            print(ticker, name)
//        }
//    }
// }
