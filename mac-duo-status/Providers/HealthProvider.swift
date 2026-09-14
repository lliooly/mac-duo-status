//
//  HealthProvider.swift
//  mac-duo-status
//

import Darwin
import Foundation

protocol CPUUsageReading: Sendable {
    func readUsagePercent() -> Double?
}

protocol LoadAverageReading: Sendable {
    func readLoadAverages() -> (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)?
}

final class MachCPUUsageReader: CPUUsageReading, @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: [UInt64]?

    func readUsagePercent() -> Double? {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return nil
        }

        defer {
            let address = vm_address_t(UInt(bitPattern: processorInfo))
            let size = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<natural_t>.stride)
            vm_deallocate(mach_task_self_, address, size)
        }

        let processorCountValue = Int(exactly: processorCount) ?? 0
        guard processorCountValue > 0 else {
            return nil
        }

        let currentTicks = processorInfo.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: processorCountValue
        ) { pointer in
            (0 ..< processorCountValue).flatMap { index in
                let ticks = pointer[index].cpu_ticks
                return [
                    UInt64(ticks.0),
                    UInt64(ticks.1),
                    UInt64(ticks.2),
                    UInt64(ticks.3)
                ]
            }
        }

        lock.lock()
        defer { lock.unlock() }

        guard let previousTicks, previousTicks.count == currentTicks.count else {
            self.previousTicks = currentTicks
            return nil
        }
        self.previousTicks = currentTicks

        let stateCount = max(Int(exactly: CPU_STATE_MAX) ?? 4, 1)
        let idleState = Int(exactly: CPU_STATE_IDLE) ?? 2
        var activeDelta: UInt64 = 0
        var totalDelta: UInt64 = 0
        for index in currentTicks.indices {
            let delta = currentTicks[index] >= previousTicks[index]
                ? currentTicks[index] - previousTicks[index]
                : 0
            totalDelta += delta

            let state = index % stateCount
            if state != idleState {
                activeDelta += delta
            }
        }

        guard totalDelta > 0 else {
            return nil
        }

        return min(max(Double(activeDelta) / Double(totalDelta) * 100, 0), 100)
    }
}

struct SystemLoadAverageReader: LoadAverageReading {
    func readLoadAverages() -> (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)? {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, 3)
        }

        guard count == 3, values.allSatisfy(\.isFinite) else {
            return nil
        }

        return (values[0], values[1], values[2])
    }
}

final class HealthProvider: HealthProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let cpuReader: any CPUUsageReading
    private let loadReader: any LoadAverageReading
    private let processInfo: ProcessInfo
    private let notificationCenter: NotificationCenter
    private var cpuSmoother: MovingAverageSmoother
    private var oneMinuteLoadSmoother: MovingAverageSmoother
    private var fiveMinuteLoadSmoother: MovingAverageSmoother
    private var fifteenMinuteLoadSmoother: MovingAverageSmoother
    private var changeHandler: (@Sendable () -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []

    init(
        smoothingWindowSize: Int = 3,
        cpuReader: any CPUUsageReading = MachCPUUsageReader(),
        loadReader: any LoadAverageReading = SystemLoadAverageReader(),
        processInfo: ProcessInfo = .processInfo,
        notificationCenter: NotificationCenter = .default
    ) {
        self.cpuReader = cpuReader
        self.loadReader = loadReader
        self.processInfo = processInfo
        self.notificationCenter = notificationCenter
        self.cpuSmoother = MovingAverageSmoother(windowSize: smoothingWindowSize)
        self.oneMinuteLoadSmoother = MovingAverageSmoother(windowSize: smoothingWindowSize)
        self.fiveMinuteLoadSmoother = MovingAverageSmoother(windowSize: smoothingWindowSize)
        self.fifteenMinuteLoadSmoother = MovingAverageSmoother(windowSize: smoothingWindowSize)
    }

    func read() async -> HealthStatus {
        readSynchronously()
    }

    private func readSynchronously() -> HealthStatus {
        lock.lock()
        defer { lock.unlock() }

        let cpuUsage: Double? = cpuReader.readUsagePercent().flatMap { value -> Double? in
            guard value.isFinite else { return nil }
            return cpuSmoother.append(min(max(value, 0), 100))
        }

        let loads = loadReader.readLoadAverages()
        let oneMinuteLoad = smoothedLoad(loads?.oneMinute, using: &oneMinuteLoadSmoother)
        let fiveMinuteLoad = smoothedLoad(loads?.fiveMinute, using: &fiveMinuteLoadSmoother)
        let fifteenMinuteLoad = smoothedLoad(loads?.fifteenMinute, using: &fifteenMinuteLoadSmoother)

        let logicalCPUCount = processInfo.activeProcessorCount > 0
            ? processInfo.activeProcessorCount
            : nil
        let thermalState = ThermalState(processInfo.thermalState)
        let hasReadableValue = cpuUsage != nil
            || oneMinuteLoad != nil
            || fiveMinuteLoad != nil
            || fifteenMinuteLoad != nil
            || thermalState != nil

        let loadScore: Double?
        if let oneMinuteLoad, let logicalCPUCount {
            loadScore = HealthScoreCalculator.loadScore(
                oneMinuteLoad: oneMinuteLoad,
                logicalCPUCount: logicalCPUCount
            )
        } else {
            loadScore = nil
        }

        let status = HealthStatus(
            availability: hasReadableValue
                ? .available
                : .unavailable(reason: "Health data is unavailable"),
            cpuUsagePercent: cpuUsage,
            oneMinuteLoad: oneMinuteLoad,
            fiveMinuteLoad: fiveMinuteLoad,
            fifteenMinuteLoad: fifteenMinuteLoad,
            logicalCPUCount: logicalCPUCount,
            thermalState: thermalState,
            cpuScore: cpuUsage.map(HealthScoreCalculator.cpuScore),
            loadScore: loadScore,
            thermalScore: thermalState.map(HealthScoreCalculator.thermalScore),
            selectedMetric: .cpu,
            selectedScore: nil,
            dotCount: nil
        )

        return status.selecting(.cpu)
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        // Apple requires thermalState to be accessed before registering for this notification.
        _ = processInfo.thermalState

        lock.lock()
        guard notificationTokens.isEmpty else {
            lock.unlock()
            return
        }

        changeHandler = handler
        let thermalToken = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: processInfo,
            queue: nil
        ) { [weak self] _ in
            self?.notifyChange()
        }
        let powerToken = notificationCenter.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: processInfo,
            queue: nil
        ) { [weak self] _ in
            self?.notifyChange()
        }
        notificationTokens = [thermalToken, powerToken]
        lock.unlock()
    }

    func stopObserving() {
        lock.lock()
        let tokens = notificationTokens
        notificationTokens = []
        changeHandler = nil
        lock.unlock()

        tokens.forEach(notificationCenter.removeObserver)
    }

    private func smoothedLoad(
        _ value: Double?,
        using smoother: inout MovingAverageSmoother
    ) -> Double? {
        guard let value, value.isFinite, value >= 0 else {
            return nil
        }

        return smoother.append(value)
    }

    private func notifyChange() {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?()
    }
}

private extension ThermalState {
    init?(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            return nil
        }
    }
}
