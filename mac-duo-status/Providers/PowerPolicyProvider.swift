//
//  PowerPolicyProvider.swift
//  mac-duo-status
//

import Foundation

final class PowerPolicyProvider: PowerPolicyProviding, PowerControlProviding, @unchecked Sendable {
    private struct CachedPowerModeState {
        let state: PowerModeState
        let timestamp: UInt64
    }

    private let helper: any PowerControlProviding
    private let notificationCenter: NotificationCenter
    private let lowPowerModeEnabled: @Sendable () -> Bool
    private let powerStateRefreshIntervalNanoseconds: UInt64
    private let lock = NSLock()
    private var cachedPowerModeState: CachedPowerModeState?
    private var cacheVersion: UInt64 = 0
    private var observer: NSObjectProtocol?
    private var changeHandler: (@Sendable () -> Void)?

    init(
        helper: (any PowerControlProviding)? = nil,
        notificationCenter: NotificationCenter = .default,
        lowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        powerStateRefreshIntervalNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.helper = helper ?? PowerHelperClient()
        self.notificationCenter = notificationCenter
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.powerStateRefreshIntervalNanoseconds = powerStateRefreshIntervalNanoseconds
    }

    func read() async -> PowerPolicyStatus {
        let capabilities = await helper.capabilities()
        let isLowPowerModeEnabled = lowPowerModeEnabled()
        let powerState = await readPowerStateForStatus()
        let activeMode = powerState.activeMode ?? (
            isLowPowerModeEnabled ? .lowPower : nil
        )

        return PowerPolicyStatus(
            availability: .available,
            activeMode: activeMode,
            batteryMode: powerState.batteryMode,
            adapterMode: powerState.adapterMode,
            helperStatus: capabilities.helperStatus,
            capabilities: capabilities
        )
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        guard observer == nil else {
            lock.unlock()
            return
        }
        changeHandler = handler
        lock.unlock()

        let token = notificationCenter.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: nil
        ) { [weak self] _ in
            self?.notifyChange()
        }

        lock.lock()
        observer = token
        lock.unlock()
    }

    func stopObserving() {
        lock.lock()
        let token = observer
        observer = nil
        changeHandler = nil
        lock.unlock()

        if let token {
            notificationCenter.removeObserver(token)
        }
    }

    func capabilities() async -> PowerCapabilities {
        await helper.capabilities()
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {
        invalidatePowerStateCache()
        defer { invalidatePowerStateCache() }
        try await helper.setPowerMode(mode, scope: scope)
    }

    func readPowerState() async -> PowerModeState {
        await helper.readPowerState()
    }

    func readPowerModes() async -> (batteryMode: PowerMode?, adapterMode: PowerMode?) {
        await helper.readPowerModes()
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        await helper.readPowerMode(scope: scope)
    }

    func readPowerModeUncached(scope: PowerSourceScope) async -> PowerMode? {
        await helper.readPowerMode(scope: scope)
    }

    func readActivePowerMode() async -> PowerMode? {
        await helper.readActivePowerMode()
    }

    func requestHelperApproval() async -> HelperStatus {
        invalidatePowerStateCache()
        defer { invalidatePowerStateCache() }
        return await helper.requestHelperApproval()
    }

    func unregisterHelper() async -> HelperStatus {
        invalidatePowerStateCache()
        defer { invalidatePowerStateCache() }
        return await helper.unregisterHelper()
    }

    private func notifyChange() {
        lock.lock()
        let handler = changeHandler
        cachedPowerModeState = nil
        cacheVersion &+= 1
        lock.unlock()
        handler?()
    }

    private func readPowerStateForStatus() async -> PowerModeState {
        let now = DispatchTime.now().uptimeNanoseconds
        let cachedRead = cachedPowerModeState(at: now)
        if let state = cachedRead.state {
            return state
        }

        let state = await helper.readPowerState()
        storePowerModeState(
            state,
            timestamp: DispatchTime.now().uptimeNanoseconds,
            ifVersion: cachedRead.version
        )
        return state
    }

    private func cachedPowerModeState(
        at now: UInt64
    ) -> (state: PowerModeState?, version: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard let cachedPowerModeState,
              powerStateRefreshIntervalNanoseconds > 0,
              now >= cachedPowerModeState.timestamp,
              now - cachedPowerModeState.timestamp < powerStateRefreshIntervalNanoseconds
        else {
            return (nil, cacheVersion)
        }

        return (cachedPowerModeState.state, cacheVersion)
    }

    private func storePowerModeState(
        _ state: PowerModeState,
        timestamp: UInt64,
        ifVersion version: UInt64
    ) {
        lock.lock()
        if cacheVersion == version {
            cachedPowerModeState = CachedPowerModeState(state: state, timestamp: timestamp)
        }
        lock.unlock()
    }

    private func invalidatePowerStateCache() {
        lock.lock()
        cachedPowerModeState = nil
        cacheVersion &+= 1
        lock.unlock()
    }
}
