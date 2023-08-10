//
//  ScrollChartView.swift
//  ChartInsight
//
//  View that requests rendered stock charts from ChartRenderer
//  in an offscreen CGContext by providing ChartElements computed by StockActor.

//  Created by Eric Kennedy on 6/28/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

let padding: CGFloat = 5

final class ScrollChartView: UIView {
    public var svWidth: CGFloat

    public var viewModel: ScrollChartViewModel
    public var progressIndicator: ProgressIndicator? // reference to WatchlistVC property

    private var maxWidth: CGFloat
    private var scaleShift: CGFloat
    private var scaledWidth: CGFloat
    private var svHeight: CGFloat
    private var layerRef: CGLayer?
    private var chartRenderer: ChartRenderer?

    init(viewModel: ScrollChartViewModel) {
        (maxWidth, scaleShift, scaledWidth, svWidth, svHeight) = (0, 0, 0, 0, 0)
        self.viewModel = viewModel
        super.init(frame: .zero)
        bindToViewModel()
    }

    required convenience init?(coder: NSCoder) {
        self.init(viewModel: ScrollChartViewModel(contentsScale: UIScreen.main.scale)) // Required by UIKit but Storyboard isn't used
    }

    // MARK: - ViewModel
    /// Set closures on ViewModel to run when the VM gets updated
    private func bindToViewModel() {
        viewModel.didBeginRequest = { [weak self] in
            self?.progressIndicator?.startAnimating()
        }
        viewModel.didCancel = { [weak self] in
            self?.progressIndicator?.stopAnimating()
        }
        viewModel.didUpdate = { [weak self] chartElements in
            self?.renderCharts(stockChartElements: chartElements)
            self?.progressIndicator?.stopAnimating()
        }
        viewModel.didError = { [weak self] _ in
            self?.progressIndicator?.stopAnimating()
        }
    }

    /// Create off-screen image context and ChartRenderer
    private func createLayerContext() {
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, layer.contentsScale)
        if let currentContext = UIGraphicsGetCurrentContext() {
            layerRef = CGLayer(currentContext,
                               size: CGSize(width: layer.contentsScale * maxWidth,
                                            height: layer.contentsScale * svHeight), auxiliaryInfo: nil)
            UIGraphicsEndImageContext()
            if let layerRef {
                chartRenderer = ChartRenderer(layerRef: layerRef, contentsScale: layer.contentsScale,
                                              xFactor: viewModel.xFactor,
                                              barUnit: viewModel.barUnit,
                                              pxWidth: layer.contentsScale * svWidth - viewModel.axisPadding)
            }
        }
    }

    /// Clear prior render before resizing the chart to avoid odd animation
    public func clearChart() {
        progressIndicator?.reset()
        if let layerRef {
            layerRef.context?.clear(CGRect(x: 0, y: 0,
                                           width: layerRef.size.width,
                                           height: layerRef.size.height))
        }
        setNeedsDisplay()
    }

    /// Use ChartRenderer to render the charts in an offscreen CGContext and return a list of the chartText to render via UIGraphicsPushContext
    /// Apple deprecated the CoreGraphics function for rendering text with a specified CGContext so it is necessary
    /// to use UIGraphicsPushContext(context) to render text in the offscreen layerRef.context
    private func renderCharts(stockChartElements: [ChartElements]) {
        if var renderer = chartRenderer, let context = layerRef?.context {
            renderer.barUnit = viewModel.barUnit
            renderer.xFactor = viewModel.xFactor
            renderer.pxWidth = viewModel.pxWidth - viewModel.axisPadding

            let chartText = renderer.renderCharts(comparison: viewModel.comparison, stockChartElements: stockChartElements)

            UIGraphicsPushContext(context) // required for textData.text.draw(at: withAttributes:)
            for textData in chartText {
                let textAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: textData.size),
                                      NSAttributedString.Key.foregroundColor: textData.color]
                textData.string.draw(at: textData.position, withAttributes: textAttributes)
            }
            UIGraphicsPopContext() // remove context used to render text
            setNeedsDisplay()
        }
    }

    /// Draw the offscreen layerRef CGLayer into the context for this view
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(UIColor.systemBackground.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: layer.contentsScale * maxWidth, height: viewModel.pxHeight + 5))
        if let layerRef {
             ctx.draw(layerRef, in: CGRect(x: 5 + scaleShift, y: 5, width: scaledWidth, height: svHeight))
        }

        if layer.position.x > 0 { // Add dividing line from tableView on the left
            ctx.setStrokeColor(UIColor.lightGray.cgColor)
            ctx.setLineWidth(1.0)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0.5, y: 0.5))
            ctx.addLine(to: CGPoint(x: 0.5, y: svHeight))
            ctx.strokePath()
        }
    }

    /// Enlarged screenshot of chart under user's finger with a bar highlighted if coordinates match
    public func magnifyBar(xPress: CGFloat, yPress: CGFloat) async -> UIImage? {
        if var renderer = chartRenderer {
            renderer.barUnit = viewModel.barUnit
            renderer.xFactor = viewModel.xFactor
            renderer.pxWidth = viewModel.pxWidth - viewModel.axisPadding - layer.position.x

            let centerX = xPress * layer.contentsScale
            let centerY = yPress * layer.contentsScale
            let barOffset = Int(round(centerX / (viewModel.xFactor * viewModel.barUnit)))

            if let (barData, monthName) = await viewModel.matchedBarAtIndex(barOffset: barOffset, centerY: centerY) {
                return renderer.magnifyBar(x: xPress, y: yPress, bar: barData, monthName: monthName)
            }
        }
        return nil
    }

    /// Horizontally scale chart image during pinch/zoom gesture and calculate change in bars shown for scaleChart call
    public func scaleChartImage(_ newScale: CGFloat, withCenter touchMidpoint: CGFloat) {
        var scaleFactor = viewModel.xFactor * newScale
        var newScale = newScale

        if scaleFactor <= 0.25 {
            scaleFactor = 0.25
            newScale = 0.25 / viewModel.xFactor
        } else if scaleFactor > 50 {
            scaleFactor = 50
            newScale = 50 / viewModel.xFactor
        }

        if scaleFactor == viewModel.xFactor {
            return
        }

        scaleShift = touchMidpoint * (1 - newScale)
        scaledWidth = maxWidth * newScale

        setNeedsDisplay()
    }

    /// Returns scaleShift set by scaleChartImage(_:withCenter:) so the rendered chart matches the temporary transformation
    public func getPxShiftAndResetLayer() -> Double {
        if let layerRef {
            // clearing the layer context before renderCharts provides a better animation
            layerRef.context?.clear(CGRect(x: 0, y: 0,
                                           width: layerRef.size.width,
                                           height: layerRef.size.height))
        }
        scaledWidth = maxWidth // reset buffer output width after temporary transformation
        let pxShifted = Double(layer.contentsScale * scaleShift)
        scaleShift = 0.0
        return pxShifted
    }

    /// Create rendering context to match scrollChartViews.bounds. Called on initial load and after rotation
    @MainActor public func resize() -> (Double, Double) {
        svHeight = bounds.size.height
        maxWidth = bounds.size.width
        scaledWidth = maxWidth
        svWidth = maxWidth - layer.position.x - padding
        createLayerContext()
        return (svWidth * layer.contentsScale, svHeight * layer.contentsScale)
    }
}
