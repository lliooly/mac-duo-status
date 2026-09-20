//
//  PowerHelperClient.swift
//  mac-duo-status
//

import Foundation
import ServiceManagement

final class PowerHelperClient: PowerControlProviding, @unchecked Sendable {
    private static let expectedHelperRevision = 5

    private struct RawPowerState: Sendable {
        let batteryMode: String?
        let adapterMode: String?
        let activeMode: String?
    }

    private let service: SMAppService
    private let machServiceName = "com.shishishi3.duo-status.power-helper"
    private let requestTimeoutNanoseconds: UInt64 = 5_000_000_000

    init(
        service: SMAppService = .daemon(
            plistName: "com.shishishi3.duo-status.power-helper.plist"
        )
    ) {
        self.service = service
    }

    func capabilities() async -> PowerCapabilities {
        await readCapabilitiesFromHelper()
    }

    private func readCapabilitiesFromHelper() async -> PowerCapabilities {
        let helperStatus = currentStatus()
        guard helperStatus == .authorized else {
            return capabilities(for: helperStatus)
        }

        let connection = XPCConnectionBox(makeConnection())
        return await withCheckedContinuation { continuation in
            let finish = Once {
                connection.invalidate()
            }
            let timeout = XPCRequestTimeout()
            timeout.start(after: requestTimeoutNanoseconds) {
                finish.run {
                    continuation.resume(returning: self.unavailableCapabilities())
                }
            }
            let proxy = connection.connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    timeout.cancel()
                    continuation.resume(returning: self.unavailableCapabilities())
                }
            } as? DuoStatusPowerHelperProtocol

            guard let proxy else {
                finish.run {
                    timeout.cancel()
                    continuation.resume(returning: self.unavailableCapabilities())
                }
                return
            }

            proxy.getHelperInfo { revision in
                guard revision.intValue == Self.expectedHelperRevision else {
                    finish.run {
                        timeout.cancel()
                        continuation.resume(returning: self.unavailableCapabilities())
                    }
                    return
                }

                proxy.getCapabilities { scopes, modes in
                    finish.run {
                        timeout.cancel()
                        let parsedScopes = Set(
                            scopes.compactMap { value in
                                (value as? String).flatMap(PowerSourceScope.init(rawValue:))
                            }
                        )
                        let parsedModes = Set(
                            modes.compactMap { value in
                                (value as? String).flatMap(PowerMode.init(rawValue:))
                            }
                        )
                        continuation.resume(
                            returning: PowerCapabilities(
                                energyModeScopes: parsedScopes,
                                supportedPowerModes: parsedModes,
                                requiresHelper: true,
                                helperStatus: .authorized
                            )
                        )
                    }
                }
            }
        }
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {
        let capabilities = await capabilities()
        guard capabilities.helperStatus.isAuthorized else {
            throw error(for: capabilities.helperStatus)
        }
        guard capabilities.energyModeScopes.contains(scope),
              capabilities.supportedPowerModes.contains(mode)
        else {
            throw ControlError.temporarilyUnavailable
        }

        let connection = XPCConnectionBox(makeConnection())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finish = Once {
                connection.invalidate()
            }
            let timeout = XPCRequestTimeout()
            timeout.start(after: requestTimeoutNanoseconds) {
                finish.run {
                    continuation.resume(throwing: ControlError.operationTimeout)
                }
            }
            let proxy = connection.connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    timeout.cancel()
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    timeout.cancel()
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
                return
            }

            proxy.setPowerMode(scope.rawValue as NSString, mode: mode.rawValue as NSString) { error in
                finish.run {
                    timeout.cancel()
                    if let error {
                        continuation.resume(throwing: self.map(error: error))
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    func readPowerModes() async -> (batteryMode: PowerMode?, adapterMode: PowerMode?) {
        guard let state = await readPowerState() else {
            return (nil, nil)
        }

        return (
            state.batteryMode.flatMap(PowerMode.init(rawValue:)),
            state.adapterMode.flatMap(PowerMode.init(rawValue:))
        )
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        let modes = await readPowerModes()
        return scope == .battery ? modes.batteryMode : modes.adapterMode
    }

    func readActivePowerMode() async -> PowerMode? {
        await readPowerState()?.activeMode.flatMap(PowerMode.init(rawValue:))
    }

    private func readPowerState() async -> RawPowerState? {
        guard currentStatus() == .authorized else {
            return nil
        }

        let connection = XPCConnectionBox(makeConnection())
        return await withCheckedContinuation { continuation in
            let finish = Once {
                connection.invalidate()
            }
            let timeout = XPCRequestTimeout()
            timeout.start(after: requestTimeoutNanoseconds) {
                finish.run {
                    continuation.resume(returning: nil)
                }
            }
            let proxy = connection.connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    timeout.cancel()
                    continuation.resume(returning: nil)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    timeout.cancel()
                    continuation.resume(returning: nil)
                }
                return
            }

            proxy.readPowerState { batteryMode, adapterMode, activeMode in
                finish.run {
                    timeout.cancel()
                    continuation.resume(
                        returning: RawPowerState(
                            batteryMode: batteryMode.map { String($0) },
                            adapterMode: adapterMode.map { String($0) },
                            activeMode: activeMode.map { String($0) }
                        )
                    )
                }
            }
        }
    }

    func requestHelperApproval() async -> HelperStatus {
        do {
            if currentStatus() == .authorized {
                return await reloadHelper()
            }

            try service.register()
            return currentStatus()
        } catch {
            return .failed(reason: "Unable to register the power helper")
        }
    }

    func unregisterHelper() async -> HelperStatus {
        do {
            try await service.unregister()
            return currentStatus()
        } catch {
            return .failed(reason: "Unable to unregister the power helper")
        }
    }

    private func reloadHelper() async -> HelperStatus {
        do {
            try await service.unregister()
            try service.register()
            return currentStatus()
        } catch {
            return .failed(reason: "Unable to reload the power helper")
        }
    }

    private func currentStatus() -> HelperStatus {
        switch service.status {
        case .notRegistered, .notFound:
            return .notInstalled
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            return .authorized
        @unknown default:
            return .unavailable(reason: "The power helper status is unknown")
        }
    }

    private func unavailableCapabilities() -> PowerCapabilities {
        capabilities(for: .unavailable(reason: "The power helper is unavailable"))
    }

    private func capabilities(for status: HelperStatus) -> PowerCapabilities {
        PowerCapabilities(
            energyModeScopes: [],
            supportedPowerModes: [],
            requiresHelper: true,
            helperStatus: status
        )
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: DuoStatusPowerHelperProtocol.self
        )
        connection.resume()
        return connection
    }

    private func error(for status: HelperStatus) -> ControlError {
        switch status {
        case .requiresApproval:
            return .authorizationRequired
        case .notInstalled, .authorized, .unavailable, .failed:
            return .helperUnavailable
        }
    }

    private func map(error: NSError) -> ControlError {
        if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
            return .cancelled
        }

        return .failed
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    init(_ action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    private let action: @Sendable () -> Void

    func run(_ body: () -> Void) {
        lock.lock()
        guard !hasRun else {
            lock.unlock()
            return
        }
        hasRun = true
        lock.unlock()
        action()
        body()
    }
}

private final class XPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        connection.invalidate()
    }
}

private final class XPCRequestTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?

    func start(
        after nanoseconds: UInt64,
        action: @escaping @Sendable () -> Void
    ) {
        let workItem = DispatchWorkItem(block: action)
        lock.lock()
        self.workItem = workItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .nanoseconds(Int(nanoseconds)),
            execute: workItem
        )
    }

    func cancel() {
        lock.lock()
        let workItem = self.workItem
        lock.unlock()
        workItem?.cancel()
    }
}
