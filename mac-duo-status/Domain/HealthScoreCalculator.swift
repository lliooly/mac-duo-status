//
//  HealthScoreCalculator.swift
//  mac-duo-status
//

import Foundation

enum HealthScoreCalculator {
    static func cpuScore(usagePercent: Double) -> Double {
        1 - usagePercent / 100
    }

    static func loadScore(oneMinuteLoad: Double, logicalCPUCount: Int) -> Double {
        guard logicalCPUCount > 0 else {
            return 0
        }

        return 1 - oneMinuteLoad / Double(logicalCPUCount)
    }

    static func thermalScore(for state: ThermalState) -> Double {
        switch state {
        case .nominal:
            return 1.00
        case .fair:
            return 0.67
        case .serious:
            return 0.33
        case .critical:
            return 0
        }
    }

    static func dotCount(for score: Double) -> Int {
        Int((score * 4).rounded())
    }
}

struct MovingAverageSmoother {
    let windowSize: Int
    private(set) var samples: [Double] = []

    init(windowSize: Int) {
        self.windowSize = max(windowSize, 1)
    }

    mutating func append(_ value: Double) -> Double {
        samples.append(value)

        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }

        return samples.reduce(0, +) / Double(samples.count)
    }
}
