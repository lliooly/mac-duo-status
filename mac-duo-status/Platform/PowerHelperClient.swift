//
//  PowerHelperClient.swift
//  mac-duo-status
//

import Foundation
import ServiceManagement

final class PowerHelperClient: PowerControlProviding, @unchecked Sendable {
    private let service: SMAppService
    private let machServiceName = "com.shishishi3.duo-status.power-helper"

    init(
        service: SMAppService = .daemon(
            plistName: "com.shishishi3.duo-status.power-helper.plist"
        )
    ) {
        self.service = service
    }

    func capabilities() async -> PowerCapabilities {
        let helperStatus = currentStatus()
        guard helperStatus == .authorized else {
            return PowerCapabilities(
                energyModeScopes: [],
                supportedPowerModes: [],
                chargeLimitValues: [],
                requiresHelper: true,
                helperStatus: helperStatus
            )
        }

        let connection = makeConnection()
        return await withCheckedContinuation { continuation in
            let finish = Once {
                connection.invalidate()
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    continuation.resume(returning: self.unavailableCapabilities())
                }
            } as? DuoStatusPowerHelperProtocol

            guard let proxy else {
                finish.run {
                    continuation.resume(returning: self.unavailableCapabilities())
                }
                return
            }

            proxy.getCapabilities { scopes, modes, minimum, maximum in
                finish.run {
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
                    let chargeLimitValues: Set<Int>
                    if let minimum = minimum?.intValue, let maximum = maximum?.intValue {
                        chargeLimitValues = Set(minimum...maximum)
                    } else {
                        chargeLimitValues = []
                    }

                    continuation.resume(
                        returning: PowerCapabilities(
                            energyModeScopes: parsedScopes,
                            supportedPowerModes: parsedModes,
                            chargeLimitValues: chargeLimitValues,
                            requiresHelper: true,
                            helperStatus: .authorized
                        )
                    )
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

        let connection = makeConnection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finish = Once {
                connection.invalidate()
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
                return
            }

            proxy.setPowerMode(scope.rawValue as NSString, mode: mode.rawValue as NSString) { error in
                finish.run {
                    if let error {
                        continuation.resume(throwing: self.map(error: error))
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        guard currentStatus() == .authorized else {
            return nil
        }

        let connection = makeConnection()
        return await withCheckedContinuation { continuation in
            let finish = Once {
                connection.invalidate()
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    continuation.resume(returning: nil)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    continuation.resume(returning: nil)
                }
                return
            }

            proxy.readPowerState { batteryMode, adapterMode, _, _ in
                finish.run {
                    let rawValue = scope == .battery ? batteryMode : adapterMode
                    continuation.resume(
                        returning: rawValue.flatMap { PowerMode(rawValue: String($0)) }
                    )
                }
            }
        }
    }

    func setChargeLimit(_ percent: Int) async throws {
        guard (80...100).contains(percent) else {
            throw ControlError.invalidChargeLimit
        }

        let capabilities = await capabilities()
        guard capabilities.helperStatus.isAuthorized else {
            throw error(for: capabilities.helperStatus)
        }
        guard capabilities.chargeLimitValues.contains(percent) else {
            throw ControlError.invalidChargeLimit
        }

        let connection = makeConnection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finish = Once {
                connection.invalidate()
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    continuation.resume(throwing: ControlError.helperUnavailable)
                }
                return
            }

            proxy.setChargeLimit(percent as NSNumber) { error in
                finish.run {
                    if let error {
                        continuation.resume(throwing: self.map(error: error))
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    func readChargeLimit() async -> Int? {
        guard currentStatus() == .authorized else {
            return nil
        }

        let connection = makeConnection()
        return await withCheckedContinuation { continuation in
            let finish = Once {
                connection.invalidate()
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                finish.run {
                    continuation.resume(returning: nil)
                }
            } as? DuoStatusPowerHelperProtocol
            guard let proxy else {
                finish.run {
                    continuation.resume(returning: nil)
                }
                return
            }

            proxy.readChargeLimit { value in
                finish.run {
                    continuation.resume(returning: value?.intValue)
                }
            }
        }
    }

    func requestHelperApproval() async -> HelperStatus {
        do {
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
        PowerCapabilities(
            energyModeScopes: [],
            supportedPowerModes: [],
            chargeLimitValues: [],
            requiresHelper: true,
            helperStatus: .unavailable(reason: "The power helper is unavailable")
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
