//
//  LaunchAtLoginManager.swift
//  mac-duo-status
//

import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) async throws
}

struct NoopLaunchAtLoginManager: LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) async throws {}
}

@MainActor
final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    private let serviceQueue = DispatchQueue(
        label: "com.shishishi3.duo-status.launch-at-login.service",
        qos: .utility
    )

    func setEnabled(_ enabled: Bool) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            serviceQueue.async {
                do {
                    try Self.setEnabledSynchronously(enabled)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func setEnabledSynchronously(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled else {
                return
            }

            try service.register()
        } else {
            guard service.status != .notRegistered else {
                return
            }

            try service.unregister()
        }
    }
}
