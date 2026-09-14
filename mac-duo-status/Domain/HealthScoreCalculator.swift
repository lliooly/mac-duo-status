//
//  HealthScoreCalculator.swift
//  mac-duo-status
//

import Foundation

enum HealthScoreCalculator {
    static func cpuScore(usagePercent: Double) -> Double {
        guard usagePercent.isFinite else {
            return 0
        }

        return 1 - usagePercent / 100
    }

    static func loadScore(oneMinuteLoad: Double, logicalCPUCount: Int) -> Double {
        guard logicalCPUCount > 0, oneMinuteLoad.isFinite else {
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
        guard score.isFinite else {
            return 0
        }

        let boundedScore = min(max(score, 0), 1)
        return Int((boundedScore * 4).rounded())
    }
}

struct MovingAverageSmoother {
    let windowSize: Int
    private(set) var samples: [Double] = []

    init(windowSize: Int = 3) {
        self.windowSize = max(windowSize, 1)
    }

    mutating func append(_ value: Double) -> Double {
        samples.append(value)

        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }

        return samples.reduce(0, +) / Double(samples.count)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
