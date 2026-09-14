//
//  LaunchAtLoginManager.swift
//  mac-duo-status
//

import ServiceManagement

protocol LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) throws
}

struct NoopLaunchAtLoginManager: LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) throws {}
}

@MainActor
final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool) throws {
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
