//
//  ProgressIndicator.swift
//  ChartInsight
//
//  Displays progress across multiple requests
//
//  Created by Eric Kennedy on 6/21/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class ProgressIndicator: UIView {
    var progressView = UIProgressView()
    var timer: Timer?
    var activeDownloads: Double = 0
    var progressNumerator: Double = 0 // divide by activeDownloads to get progress

    override init(frame: CGRect) {
        super.init(frame: frame)
        progressView.frame = frame
        progressView.progressViewStyle = .bar
        isHidden = true  // only show when animating
        addSubview(progressView)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isHidden = true
        activeDownloads = 0
        progressNumerator = 0
        progressView.setProgress(0, animated: false)
    }

    /// Update progressView with ratio of progressNumerator divided by activeDownloads
    func updateDownloadProgress() {
        progressView.setProgress(Float(progressNumerator / activeDownloads), animated: true)
    }

    func startAnimating() {
        activeDownloads += 1
        if timer == nil {
            isHidden = false
            let timer = Timer.scheduledTimer(timeInterval: 0.1,
                                         target: self,
                                         selector: #selector(updateActivityIndicator),
                                         userInfo: nil,
                                         repeats: true)
            RunLoop.main.add(timer, forMode: .common)
        }

        updateDownloadProgress()
        isHidden = false
    }

    func stopAnimating() {
        if activeDownloads >= 1 {
            // When a download completes, subtract its share of progress
            // (progressNumerator/activeDownloads) and remove from activeDownloads
            progressNumerator -= progressNumerator/activeDownloads
            activeDownloads -= 1

            var progressCalc: Float = 1.0
            if activeDownloads > 0 {
                progressCalc = Float(progressNumerator / activeDownloads)
            }
            progressView.setProgress(progressCalc, animated: true)
        } else {
            progressView.setProgress(1.0, animated: true)
            reset()
        }
    }

    @objc func updateActivityIndicator(incomingTimer: Timer) {
        if progressView.progress == 1.0 {
            reset()
        } else {
            if activeDownloads <= 1 || progressNumerator > activeDownloads {
                progressView.setProgress(1.0, animated: true)
            } else if progressView.progress < 0.7 {
                progressNumerator += 0.015
                updateDownloadProgress()
            } else {
                progressNumerator += 0.001
                updateDownloadProgress()
            }
        }
    }

}
