//
//  PerformanceGovernorTests.swift
//  HyprGlideTests
//

import XCTest
@testable import HyprGlide

final class PerformanceGovernorTests: XCTestCase {
    func testEntersBudgetModeAfterSustainedLowFPS() {
        let governor = PerformanceGovernor()
        var currentTime: TimeInterval = 0
        let highDelta = 1.0 / 60.0
        
        for _ in 0..<150 {
            currentTime += highDelta
            _ = governor.registerFrame(deltaTime: highDelta, currentTime: currentTime)
        }
        XCTAssertEqual(governor.mode, .full)
        
        let lowDelta = 1.0 / 30.0
        var modeChanged = false
        for _ in 0..<90 {
            currentTime += lowDelta
            if governor.registerFrame(deltaTime: lowDelta, currentTime: currentTime) {
                modeChanged = true
                break
            }
        }
        
        XCTAssertTrue(modeChanged, "Governor should enter budget mode once FPS stays below threshold.")
        XCTAssertEqual(governor.mode, .budget)
        XCTAssertGreaterThan(governor.spawnIntervalMultiplier, 1.0)
        XCTAssertLessThan(governor.particleIntensityMultiplier, 1.0)
    }
    
    func testRecoversWhenPerformanceImproves() {
        let governor = PerformanceGovernor()
        var currentTime: TimeInterval = 0
        let lowDelta = 1.0 / 30.0
        
        // Force throttle first.
        while governor.mode == .full && currentTime < 10 {
            currentTime += lowDelta
            _ = governor.registerFrame(deltaTime: lowDelta, currentTime: currentTime)
        }
        XCTAssertEqual(governor.mode, .budget, "Governor should be in budget mode after extended low FPS.")
        
        let highDelta = 1.0 / 60.0
        var exitedBudget = false
        for _ in 0..<200 {
            currentTime += highDelta
            if governor.registerFrame(deltaTime: highDelta, currentTime: currentTime) {
                exitedBudget = true
                break
            }
        }
        
        XCTAssertTrue(exitedBudget, "Governor should exit budget mode after sustained recovery.")
        XCTAssertEqual(governor.mode, .full)
    }
}


