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

@objcMembers
class ProgressIndicator: UIView {
    var progressView = UIProgressView()
    var timer: Timer? = nil
    var activeDownloads: Float = 0  // 1000 * active requests
    var progressNumerator: Float = 0 // divide by activeDownloads
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        progressView.frame = frame
        progressView.progressViewStyle = .bar
        isOpaque = false // only show when animating
        addSubview(progressView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
        
    func reset() {
        timer?.invalidate()
        activeDownloads = 0
        progressNumerator = 0
    }
    
    func startAnimating() {
        activeDownloads += 1000
        if (timer == nil) {
            isHidden = false
            timer = Timer(fireAt: Date(timeIntervalSinceNow: 0.1),
                          interval: 0.1,
                          target: self, selector: #selector(updateActivityIndicator),
                          userInfo: nil, repeats: true)
            if timer != nil {
                RunLoop.main.add(timer!, forMode: .common)
                RunLoop.main.add(timer!, forMode: .tracking)
            }
        }
        
        progressView.setProgress(progressNumerator/activeDownloads, animated: false)
        isHidden = false
    }
    
    func stopAnimating() {
        var progressAchieved = progressView.progress
        if activeDownloads >= 1000.0 {
            // When a download completes, subtract its share of progress
            // (progressNumerator/activeDownloads) and remove from activeDownloads
            progressNumerator -= progressNumerator/activeDownloads
            activeDownloads -= 1000.0
            
            var progressCalc: Float = 1.0
            if activeDownloads > 0 {
                progressCalc = progressNumerator / activeDownloads
            }
            progressView.setProgress(progressCalc, animated: true)
        } else {
            while progressAchieved < 1 {
                progressAchieved += 0.25
                progressView.setProgress(progressAchieved, animated: true)
            }
            isHidden = true
            timer?.invalidate()
            timer = nil
        }
    }
    
    func updateActivityIndicator(incomingTimer: Timer) {
        var progressAchieved = progressView.progress
        if progressAchieved == 1.0 {
            isHidden = true
            timer?.invalidate()
            timer = nil
        } else {
            if activeDownloads <= 1 || progressNumerator > activeDownloads {
                while progressAchieved < 1 {
                    progressAchieved += 0.25
                    progressView.setProgress(progressAchieved, animated: true)
                }
            } else if progressView.progress < 0.7 {
                progressNumerator = progressNumerator + 15
                progressAchieved = progressNumerator / activeDownloads
            } else {
                progressNumerator += 1
                progressAchieved = progressNumerator / activeDownloads
            }
            progressView.setProgress(progressAchieved, animated: true)
        }
    }
    
}
