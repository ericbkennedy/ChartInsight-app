//
//  CIBigNumberFormatterTests.swift
//  ChartInsightTests
//
//  Created by Eric Kennedy on 5/31/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import Foundation
import XCTest

final class BigNumberFormatterTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    let showFractions: Float = 4.0
    let hideFractions: Float = 3.0

    func testBigNumberFormatterZero() throws {
        let numberFormatter = BigNumberFormatter()

        let formatted = numberFormatter.string(number: NSDecimalNumber.zero, maxDigits: showFractions)
        XCTAssertTrue(formatted == "0")
    }

    func testBigNumberFormatterNegativeValues() throws {
        let numberFormatter = BigNumberFormatter()
        let oneThousand = NSDecimalNumber(mantissa: 1, exponent: 3, isNegative: true)
        var formatted = numberFormatter.string(number: oneThousand, maxDigits: showFractions)
        XCTAssert(formatted == "-1K")

        let hundredThousand = NSDecimalNumber(mantissa: 1, exponent: 5, isNegative: true)
        formatted = numberFormatter.string(number: hundredThousand, maxDigits: showFractions)
        XCTAssert(formatted == "-100K")

        let oneMillion = NSDecimalNumber(mantissa: 1, exponent: 6, isNegative: true)
        formatted = numberFormatter.string(number: oneMillion, maxDigits: showFractions)
        XCTAssert(formatted == "-1M")

        let oneBillion = NSDecimalNumber(mantissa: 1, exponent: 9, isNegative: true)
        formatted = numberFormatter.string(number: oneBillion, maxDigits: showFractions)
        XCTAssert(formatted == "-1B")

        let hundredBillion = NSDecimalNumber(mantissa: 1, exponent: 11, isNegative: true)
        formatted = numberFormatter.string(number: hundredBillion, maxDigits: showFractions)
        XCTAssert(formatted == "-100B")
    }

    func testBigNumberFormatterPositiveValues() throws {
        let numberFormatter = BigNumberFormatter()
        let oneThousand = NSDecimalNumber(mantissa: 1, exponent: 3, isNegative: false)
        var formatted = numberFormatter.string(number: oneThousand, maxDigits: showFractions)
        XCTAssert(formatted == "1K")

        let hundredThousand = NSDecimalNumber(mantissa: 1, exponent: 5, isNegative: false)
        formatted = numberFormatter.string(number: hundredThousand, maxDigits: showFractions)
        XCTAssert(formatted == "100K")

        let oneMillion = NSDecimalNumber(mantissa: 1, exponent: 6, isNegative: false)
        formatted = numberFormatter.string(number: oneMillion, maxDigits: showFractions)
        XCTAssert(formatted == "1M")

        let oneBillion = NSDecimalNumber(mantissa: 1, exponent: 9, isNegative: false)
        formatted = numberFormatter.string(number: oneBillion, maxDigits: showFractions)
        XCTAssert(formatted == "1B")

        let hundredBillion = NSDecimalNumber(mantissa: 1, exponent: 11, isNegative: false)
        formatted = numberFormatter.string(number: hundredBillion, maxDigits: showFractions)
        XCTAssert(formatted == "100B")
    }

    // maxDigits is reduced on monthly charts where formatted string must be short
    func testBigNumberFormatterHideFractions() throws {
        let numberFormatter = BigNumberFormatter()

        let marathonMeters = NSDecimalNumber(string: "42195")
        var formatted = numberFormatter.string(number: marathonMeters, maxDigits: showFractions)
        XCTAssert(formatted == "42.2K") // note rounding up

        // reducing maxDigits will drop the .2
        formatted = numberFormatter.string(number: marathonMeters, maxDigits: hideFractions)
        XCTAssert(formatted == "42K")

        // Note that maxDigits has no effect on values between -1000 and 1000
        let marathonKm = NSDecimalNumber(string: "42.195")
        formatted = numberFormatter.string(number: marathonKm, maxDigits: hideFractions)
        XCTAssert(formatted == "42.2")
    }

}
