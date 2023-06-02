//
//  BigNumberFormatter.swift
//  ChartInsight
//
//  Format financial values for limited space
//
//  Created by Eric Kennedy on 5/31/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

class BigNumberFormatter : NumberFormatter {
    
    override func string(from number: NSNumber) -> String? {
        return super.string(from: number)
    }
    
    // Format string for bars of financial metrics like revenue which can be in the billions
    // maxDigits < 4 will set maximumFractionDigits=0 and avoid showing decimal point
    @objc(stringFromNumber:maxDigits:)
    func string(number: NSDecimalNumber, maxDigits: Float) -> String? {
        
        let thousand = NSDecimalNumber(mantissa: 1, exponent: 3, isNegative: false)
        let million = NSDecimalNumber(mantissa: 1, exponent: 6, isNegative: false)
        let billion = NSDecimalNumber(mantissa: 1, exponent: 9, isNegative: false)
        
        var absValue = number // will divide negative values by -1 below and update minusSign
        var minusSign = ""
        
        if absValue.compare(NSDecimalNumber.zero) == ComparisonResult.orderedAscending {
            minusSign = "-"
            let negativeOne = NSDecimalNumber(mantissa: 1, exponent: 0, isNegative: true)
            absValue = absValue.dividing(by: negativeOne)
        }
        
        if absValue.compare(thousand) == ComparisonResult.orderedAscending { // most values less than 1,000
            maximumFractionDigits = 2
            return String(format: "%@%@", minusSign, super.string(from: absValue) ?? "")
            
        } else if absValue.compare(million) == ComparisonResult.orderedAscending {
            let inThousands = absValue.dividing(by: thousand)
            if (inThousands.doubleValue > 10.0 && maxDigits < 4.0) || inThousands.doubleValue > 100.0 {
                maximumFractionDigits = 0
            } else {
                maximumFractionDigits = 1
            }
            return String(format: "%@%@K", minusSign, super.string(from: inThousands) ?? "")

        } else if absValue.compare(billion) == ComparisonResult.orderedAscending {
            let inMillions = absValue.dividing(by: million)
            if (inMillions.doubleValue > 10.0 && maxDigits < 4.0) || inMillions.doubleValue > 100.0 {
                maximumFractionDigits = 0
            } else {
                maximumFractionDigits = 1
            }
            return String(format: "%@%@M", minusSign, super.string(from: inMillions) ?? "")
        }
        let inBillions = absValue.dividing(by: billion)
        if inBillions.doubleValue > 100 {
            maximumFractionDigits = 0
        } else {
            maximumFractionDigits = 1
        }
        return String(format: "%@%@B", minusSign, super.string(from:inBillions) ?? "")
    }
}
