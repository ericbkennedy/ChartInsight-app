//
//  ColorChartSegmentedControl.swift
//  ChartInsight
//
//  Custom control because Swift's UISegmentedControl doesn't support colored images
//
//  Created by Eric Kennedy on 6/26/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import UIKit

enum ChartStyleControlType {
    case color, chartType
}

final class ChartStyleControl: UIControl {
    public weak var delegate: ChartOptionsController?
    public var type: ChartStyleControlType
    public var currentChartType: ChartType = .hlc
    public var buttons: [UIButton] = []
    public var selectedIndex: Int = 0 {
        didSet(oldValue) {
            if buttons.count > 0 && oldValue != selectedIndex { // remove shadow from old button and add to new
                buttons[oldValue].layer.shadowOpacity = 0
                buttons[oldValue].backgroundColor = UIColor.clear
                addShadow(to: buttons[selectedIndex])
            }
        }
    }
    private var stock: Stock
    private let stackView = UIStackView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))

    @objc func tappedButton(button: UIButton) {
        selectedIndex = button.tag
        if let delegate {
            if type == .color {
                stock = delegate.chartColorChanged(to: selectedIndex)
            } else {
                stock = delegate.chartTypeChanged(to: selectedIndex)
            }
        }
    }

    public init(type: ChartStyleControlType, frame: CGRect, stock: Stock) {
        self.type = type
        self.stock = stock
        super.init(frame: frame)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.spacing = 10
        addSubview(stackView)

        stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5).isActive = true
        stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: stackView.spacing).isActive = true
        stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1 * stackView.spacing).isActive = true
        createSegments(for: currentChartType)
        backgroundColor = UIColor.systemBackground
    }

    required convenience init?(coder aDecoder: NSCoder) {
        self.init(type: .color, frame: .zero, stock: Stock())
    }

    /// Add segments to StackView by rendering images and creating a button for each image.
    /// ChartOptionsController calls this method on the color ChartStyleControl
    /// when the user taps the other ChartStyleControl to change the chartType.
    public func createSegments(for newChartType: ChartType) {
        currentChartType = newChartType
        var images: [UIImage] = []
        if type == .chartType {
            for (index, chartType) in ChartType.allCases.enumerated() {
                if let miniChart = image(chartType: chartType, colorHex: .greenAndRed, showLabel: true) {
                    images.append(miniChart)
                }
                if stock.chartType == chartType {
                    selectedIndex = index
                }
            }
        } else {
            for (index, hexColor) in ChartHexColor.allCases.enumerated() {
                if let miniChart = image(chartType: currentChartType, colorHex: hexColor) {
                    images.append(miniChart)
                }
                if stock.color.hexString == hexColor.rawValue {
                    selectedIndex = index
                }
            }
        }
        buttons.removeAll() // Remove old buttons from array and stackView
        for oldButton in stackView.arrangedSubviews {
            oldButton.removeFromSuperview()  // will also remove from stackView
        }

        for (index, image) in images.enumerated() {
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            button.tag = index
            if index == selectedIndex {
                addShadow(to: button)
            }
            button.setImage(image, for: .normal)
            button.setImage(image, for: .highlighted)
            button.addTarget(self, action: #selector(tappedButton), for: .touchUpInside)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }
    }

    private func addShadow(to button: UIButton) {
        button.backgroundColor = UIColor.systemBackground
        button.layer.shadowColor = UIColor.darkGray.cgColor
        button.layer.shadowRadius = 2
        button.layer.shadowOffset = CGSize(width: 0, height: 0)
        button.layer.shadowOpacity = 0.8
        button.layer.cornerRadius = 3
    }

    /// Mini stock chart image used to change current chart type or color
    private func image(chartType: ChartType, colorHex: ChartHexColor, showLabel: Bool = false) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
        let img = renderer.image { ctx in
            let upCGColor = colorHex.color().cgColor
            let downCGColor = colorHex == .greenAndRed ? UIColor.red.cgColor : upCGColor
            ctx.cgContext.setLineWidth(1)
            ctx.cgContext.setStrokeColor(upCGColor)

            if chartType == .close {
                ctx.cgContext.setLineJoin(.round)
                ctx.cgContext.move(to: CGPoint(x: 2.5, y: 3))
                ctx.cgContext.addLine(to: CGPoint(x: 5, y: 22))
                ctx.cgContext.addLine(to: CGPoint(x: 13.5, y: 8))
                ctx.cgContext.addLine(to: CGPoint(x: 21, y: 13))
                ctx.cgContext.addLine(to: CGPoint(x: 30.5, y: 3))
                ctx.cgContext.drawPath(using: .stroke)
                ctx.cgContext.setLineJoin(.miter)
            } else {
                ctx.cgContext.move(to: CGPoint(x: 13.5, y: 3))
                ctx.cgContext.addLine(to: CGPoint(x: 13.5, y: 9))
                ctx.cgContext.drawPath(using: .stroke)

                ctx.cgContext.move(to: CGPoint(x: 13.5, y: 9))
                ctx.cgContext.addLine(to: CGPoint(x: 13.5, y: 26))
                ctx.cgContext.drawPath(using: .stroke)

                ctx.cgContext.move(to: CGPoint(x: 30.5, y: 2))
                ctx.cgContext.addLine(to: CGPoint(x: 30.5, y: 17))
                ctx.cgContext.drawPath(using: .stroke)

                if chartType == .candle {
                    ctx.cgContext.setFillColor(upCGColor)
                    ctx.cgContext.fill([CGRect(x: 11, y: 6, width: 5, height: 15),
                                        CGRect(x: 28, y: 3, width: 5, height: 12)])
                    ctx.cgContext.setFillColor(downCGColor)
                    ctx.cgContext.fill([CGRect(x: 2, y: 2, width: 6, height: 22),
                                        CGRect(x: 19, y: 7, width: 6, height: 9)])
                } else {
                    ctx.cgContext.move(to: CGPoint(x: 13.5, y: 8))
                    ctx.cgContext.addLine(to: CGPoint(x: 17.5, y: 8))
                    ctx.cgContext.drawPath(using: .stroke)

                    ctx.cgContext.move(to: CGPoint(x: 30.5, y: 5))
                    ctx.cgContext.addLine(to: CGPoint(x: 34, y: 5))
                    ctx.cgContext.drawPath(using: .stroke)

                    if chartType == .ohlc { // Add open
                        ctx.cgContext.move(to: CGPoint(x: 9.5, y: 21))
                        ctx.cgContext.addLine(to: CGPoint(x: 13.5, y: 21))
                        ctx.cgContext.drawPath(using: .stroke)

                        ctx.cgContext.move(to: CGPoint(x: 26.5, y: 13))
                        ctx.cgContext.addLine(to: CGPoint(x: 30.5, y: 13))
                        ctx.cgContext.drawPath(using: .stroke)

                        ctx.cgContext.setStrokeColor(downCGColor)
                        ctx.cgContext.move(to: CGPoint(x: 2, y: 3))
                        ctx.cgContext.addLine(to: CGPoint(x: 5, y: 3))
                        ctx.cgContext.drawPath(using: .stroke)

                        ctx.cgContext.move(to: CGPoint(x: 19, y: 8))
                        ctx.cgContext.addLine(to: CGPoint(x: 22, y: 8))
                        ctx.cgContext.drawPath(using: .stroke)
                    }
                    ctx.cgContext.setStrokeColor(downCGColor)

                    ctx.cgContext.move(to: CGPoint(x: 5, y: 3))
                    ctx.cgContext.addLine(to: CGPoint(x: 5, y: 22))
                    ctx.cgContext.drawPath(using: .stroke)

                    ctx.cgContext.move(to: CGPoint(x: 5, y: 21))
                    ctx.cgContext.addLine(to: CGPoint(x: 8, y: 21))
                    ctx.cgContext.drawPath(using: .stroke)

                    ctx.cgContext.move(to: CGPoint(x: 22, y: 13))
                    ctx.cgContext.addLine(to: CGPoint(x: 26, y: 13))
                    ctx.cgContext.drawPath(using: .stroke)
                }
                ctx.cgContext.setStrokeColor(downCGColor)
                ctx.cgContext.move(to: CGPoint(x: 22, y: 4))
                ctx.cgContext.addLine(to: CGPoint(x: 22, y: 21))
                ctx.cgContext.drawPath(using: .stroke)
            }

            if showLabel {
                let label: String = ["OHLC", "HLC", "Candle", "Close"][chartType.rawValue]
                label.draw(with: CGRect(x: 8 - label.count, y: 25, width: 32, height: 9),
                           options: .usesLineFragmentOrigin,
                           attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 9)],
                           context: nil)
            }
        }
        return img
    }
}
