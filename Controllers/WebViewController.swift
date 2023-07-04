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
    var refreshButton: UIBarButtonItem?
    var comparison: Comparison? // if the user browses a stock part of an existing comparison
    var stock: Stock? // if the user browses a stock on chartinsight.com that isn't in the watchlist

    override func loadView() {
        webView = WKWebView()
        view = webView
        webView.navigationDelegate = self
        backButton.target = self
        watchlistButton.target = self
        refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: webView, action: #selector(webView.reload))
    }

    override func viewDidLoad() {
        if let url = URL(string: "http://www.chartinsight.com") {

            webView.load(URLRequest(url: url))
           // webView.allowsBackForwardNavigationGestures = false
            webView.uiDelegate = self // open all links in main frame with @objc(webView:createWebViewWithConfiguration...)
            backButton.isEnabled = false
            view.addSubview(progressView)
            progressView.sizeToFit()

            navigationController?.navigationBar.isHidden = true // hide navigation bar since the lower toolbar is easier to access

            // Uncomment to enable passing messages from web JS to Swift
            // let contentController = webView.configuration.userContentController
            // contentController.add(self, name: "ciAppHandler")
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progressView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.absoluteString.contains("chartinsight.com") == true else { return }
        backButton.isEnabled = webView.canGoBack
        progressView.isHidden = true

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

                        if let refresh = self.refreshButton {
                            self.toolbarItems = [self.backButton, spacer, self.watchlistButton, spacer, refresh]
                            self.navigationController?.isToolbarHidden = false
                        }
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

    override func viewDidAppear(_ animated: Bool) {
        webObservation = webView.observe(\WKWebView.estimatedProgress, options: .new) { _, change in
            if let currentProgress = change.newValue {
                self.progressView.progress = Float(currentProgress)
            }
        }
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
