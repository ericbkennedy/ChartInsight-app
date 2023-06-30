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

class ChartStyleControl: UIControl {
    let stock: Stock
    let stackView = UIStackView(frame: CGRectMake(0, 0, 320, 44))
    var delegate: ChartOptionsController?
    var type: ChartStyleControlType
    var currentChartType: ChartType = .hlc
    var buttons: [UIButton] = []
    var selectedIndex: Int = 0 {
        didSet(oldValue) {
            if buttons.count > 0 && oldValue != selectedIndex { // remove shadow from old button and add to new
                buttons[oldValue].layer.shadowOpacity = 0
                buttons[oldValue].backgroundColor = UIColor.clear
                addShadow(to: buttons[selectedIndex])
            }
        }
    }
    
    @objc func tappedButton(button: UIButton) {
        selectedIndex = button.tag
        if type == .color {
            delegate?.chartColorChanged(to: selectedIndex)
        } else {
            delegate?.chartTypeChanged(to: selectedIndex)
        }
    }
    
    init(type: ChartStyleControlType, frame: CGRect, stock: Stock) {
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
    func createSegments(for newChartType: ChartType) {
        currentChartType = newChartType
        var images: [UIImage] = []
        if type == .chartType {
            for (i, chartType) in ChartType.allCases.enumerated() {
                if let miniChart = image(chartType: chartType, colorIndex: 0, showLabel: true) {
                    images.append(miniChart)
                }
                if stock.chartType == chartType {
                    selectedIndex = i
                }
            }
        } else {
            for (i, color) in Stock.chartColors.enumerated() {
                if let miniChart = image(chartType: currentChartType, colorIndex: i) {
                    images.append(miniChart)
                }
                if stock.hasUpColor(otherColor: color) {
                    selectedIndex = i
                }
            }
        }
        buttons.removeAll() // Remove old buttons from array and stackView
        for oldButton in stackView.arrangedSubviews {
            oldButton.removeFromSuperview()  // will also remove from stackView
        }
        
        for (i, image) in images.enumerated() {
            let button = UIButton(type: .custom)
            button.frame = CGRectMake(0, 0, 36, 36)
            button.tag = i
            if i == selectedIndex {
                addShadow(to: button)
            }
            button.setImage(image, for: .normal)
            button.setImage(image, for: .highlighted)
            button.addTarget(self, action: #selector(tappedButton), for: .allEvents)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }
    }
    
    func addShadow(to button: UIButton) {
        button.backgroundColor = UIColor.systemBackground
        button.layer.shadowColor = UIColor.darkGray.cgColor
        button.layer.shadowRadius = 2
        button.layer.shadowOffset = CGSize(width: 0, height: 0)
        button.layer.shadowOpacity = 0.8
        button.layer.cornerRadius = 3
    }
    
    /// Mini stock chart image used to change current chart type or color
    func image(chartType: ChartType, colorIndex: Int, showLabel: Bool = false) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
        let img = renderer.image { ctx in
            let upCGColor = Stock.chartColors[colorIndex].cgColor
            let downCGColor = colorIndex > 0 ? upCGColor : UIColor.red.cgColor
            ctx.cgContext.setLineWidth(1)
            ctx.cgContext.setStrokeColor(upCGColor)
            
            if chartType == .close {
                ctx.cgContext.setLineJoin(.round)
                ctx.cgContext.move(to: CGPointMake(2.5, 3))
                ctx.cgContext.addLine(to: CGPointMake(5, 22))
                ctx.cgContext.addLine(to: CGPointMake(13.5, 8))
                ctx.cgContext.addLine(to: CGPointMake(21, 13))
                ctx.cgContext.addLine(to: CGPointMake(30.5, 3))
                ctx.cgContext.drawPath(using: .stroke)
            } else {
                ctx.cgContext.move(to: CGPointMake(13.5, 3))
                ctx.cgContext.addLine(to: CGPointMake(13.5, 9))
                ctx.cgContext.drawPath(using: .stroke)
                
                ctx.cgContext.move(to: CGPointMake(13.5, 9))
                ctx.cgContext.addLine(to: CGPointMake(13.5, 26))
                ctx.cgContext.drawPath(using: .stroke)
                
                ctx.cgContext.move(to: CGPointMake(30.5, 2))
                ctx.cgContext.addLine(to: CGPointMake(30.5, 17))
                ctx.cgContext.drawPath(using: .stroke)
                
                if chartType == .candle {
                    ctx.cgContext.setFillColor(upCGColor)
                    ctx.cgContext.fill([CGRectMake(11, 6, 5, 15), CGRectMake(28, 3, 5, 12)])
                    ctx.cgContext.setFillColor(downCGColor)
                    ctx.cgContext.fill([CGRectMake(2, 2, 6, 22), CGRectMake(19, 7, 6, 9)])
                } else {
                    ctx.cgContext.move(to: CGPointMake(13.5, 8))
                    ctx.cgContext.addLine(to: CGPointMake(17.5, 8))
                    ctx.cgContext.drawPath(using: .stroke)
                    
                    ctx.cgContext.move(to: CGPointMake(30.5, 5))
                    ctx.cgContext.addLine(to: CGPointMake(34, 5))
                    ctx.cgContext.drawPath(using: .stroke)
                    
                    if chartType == .ohlc { // Add open
                        ctx.cgContext.move(to: CGPointMake(9.5, 21))
                        ctx.cgContext.addLine(to: CGPointMake(13.5, 21))
                        ctx.cgContext.drawPath(using: .stroke)
                        
                        ctx.cgContext.move(to: CGPointMake(26.5, 13))
                        ctx.cgContext.addLine(to: CGPointMake(30.5, 13))
                        ctx.cgContext.drawPath(using: .stroke)
                        
                        ctx.cgContext.setStrokeColor(downCGColor)
                        ctx.cgContext.move(to: CGPointMake(2, 3))
                        ctx.cgContext.addLine(to: CGPointMake(5, 3))
                        ctx.cgContext.drawPath(using: .stroke)
 
                        ctx.cgContext.move(to: CGPointMake(19, 8))
                        ctx.cgContext.addLine(to: CGPointMake(22, 8))
                        ctx.cgContext.drawPath(using: .stroke)
                    }
                    ctx.cgContext.setStrokeColor(downCGColor)
                    
                    ctx.cgContext.move(to: CGPointMake(5, 3))
                    ctx.cgContext.addLine(to: CGPointMake(5, 22))
                    ctx.cgContext.drawPath(using: .stroke)
                    
                    ctx.cgContext.move(to: CGPointMake(5, 21))
                    ctx.cgContext.addLine(to: CGPointMake(8, 21))
                    ctx.cgContext.drawPath(using: .stroke)
                    
                    ctx.cgContext.move(to: CGPointMake(22, 13))
                    ctx.cgContext.addLine(to: CGPointMake(26, 13))
                    ctx.cgContext.drawPath(using: .stroke)
                }
                ctx.cgContext.setStrokeColor(downCGColor)
                ctx.cgContext.move(to: CGPointMake(22, 4))
                ctx.cgContext.addLine(to: CGPointMake(22, 21))
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

