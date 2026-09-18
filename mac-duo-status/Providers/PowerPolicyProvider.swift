//
//  PowerPolicyProvider.swift
//  mac-duo-status
//

import Foundation

final class PowerPolicyProvider: PowerPolicyProviding, PowerControlProviding, @unchecked Sendable {
    private let helper: any PowerControlProviding
    private let notificationCenter: NotificationCenter
    private let lowPowerModeEnabled: @Sendable () -> Bool
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var changeHandler: (@Sendable () -> Void)?

    init(
        helper: (any PowerControlProviding)? = nil,
        notificationCenter: NotificationCenter = .default,
        lowPowerModeEnabled: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.helper = helper ?? PowerHelperClient()
        self.notificationCenter = notificationCenter
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }

    func read() async -> PowerPolicyStatus {
        let capabilities = await helper.capabilities()
        let isLowPowerModeEnabled = lowPowerModeEnabled()
        let activeMode = await helper.readActivePowerMode() ?? (
            isLowPowerModeEnabled ? .lowPower : nil
        )
        let powerModes = await helper.readPowerModes()

        return PowerPolicyStatus(
            availability: .available,
            activeMode: activeMode,
            batteryMode: powerModes.batteryMode,
            adapterMode: powerModes.adapterMode,
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
        try await helper.setPowerMode(mode, scope: scope)
    }

    func readPowerModes() async -> (batteryMode: PowerMode?, adapterMode: PowerMode?) {
        await helper.readPowerModes()
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        await helper.readPowerMode(scope: scope)
    }

    func readActivePowerMode() async -> PowerMode? {
        await helper.readActivePowerMode()
    }

    func requestHelperApproval() async -> HelperStatus {
        await helper.requestHelperApproval()
    }

    func unregisterHelper() async -> HelperStatus {
        await helper.unregisterHelper()
    }

    private func notifyChange() {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?()
    }
}
