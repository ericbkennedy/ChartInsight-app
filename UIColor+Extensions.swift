//
//  UIColor+Extensions.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 6/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation

public enum ChartHexColor: String, CaseIterable {
    case greenAndRed = "009900" // green is the color for up bars, red will be added for down bars
    case blue = "0099ff"
    case purple = "cc99ff"
    case yellow = "ffcc00"
    case orange = "ff9900"
    case gray = "999999"

    func color() -> UIColor {
        return UIColor.init(hex: self.rawValue)! // all values in the enum are valid UIColors
    }
}

extension UIColor {
    /// RGBA tuple of a color's components
    public var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return (red, green, blue)
    }

    public var hexString: String {
        let (red, green, blue) = self.rgba

        // Multiply by 255 before UInt64 conversion to avoid round to zero
        let redUInt   = UInt64(255 * red)
        let greenUInt = UInt64(255 * green)
        let blueUInt  = UInt64(255 * blue)

        var hexNumber: UInt64 = 0

        hexNumber = (redUInt << 16) + (greenUInt << 8) + blueUInt

        return String(format: "%06x", hexNumber)
    }

    /// Parse hex RGB string (excluding # prefix)
    public convenience init?(hex: String) {
        if hex.count == 6 {
            let red, green, blue: CGFloat
            let scanner = Scanner(string: hex)
            var hexNumber: UInt64 = 0

            if scanner.scanHexInt64(&hexNumber) {
                red = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                green = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                blue = CGFloat(hexNumber & 0x0000ff) / 255

                self.init(red: red, green: green, blue: blue, alpha: 1.0)
                return
            }
        }
        return nil
    }
}
