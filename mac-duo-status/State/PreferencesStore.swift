//
//  PreferencesStore.swift
//  mac-duo-status
//

import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var healthMetric: HealthMetric {
        didSet {
            defaults.set(healthMetric.rawValue, forKey: Keys.healthMetric)
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var isUpdatingLaunchAtLogin = false

    @Published var usesColor: Bool {
        didSet {
            defaults.set(usesColor, forKey: Keys.usesColor)
        }
    }

    @Published var expandedSections: Set<StatusSection> {
        didSet {
            defaults.set(
                expandedSections.map { $0.rawValue },
                forKey: Keys.expandedSections
            )
        }
    }

    private let defaults: UserDefaults
    private let launchAtLoginManager: any LaunchAtLoginManaging

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil
    ) {
        self.defaults = defaults
        self.launchAtLoginManager = launchAtLoginManager ?? NoopLaunchAtLoginManager()

        let storedMetric = defaults.string(forKey: Keys.healthMetric)
            .flatMap(HealthMetric.init(rawValue:))
        self.healthMetric = storedMetric ?? .cpu
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.usesColor = defaults.object(forKey: Keys.usesColor) as? Bool ?? false

        let storedSections = defaults.array(forKey: Keys.expandedSections) as? [String] ?? []
        self.expandedSections = Set(
            storedSections.compactMap(StatusSection.init(rawValue:))
        )

        if launchAtLogin {
            let manager = self.launchAtLoginManager
            Task { @MainActor in
                try? await manager.setEnabled(true)
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard enabled != launchAtLogin,
              !isUpdatingLaunchAtLogin
        else {
            return
        }

        let previousValue = launchAtLogin
        launchAtLogin = enabled
        isUpdatingLaunchAtLogin = true

        do {
            try await launchAtLoginManager.setEnabled(enabled)
            defaults.set(enabled, forKey: Keys.launchAtLogin)
        } catch {
            launchAtLogin = previousValue
            defaults.set(previousValue, forKey: Keys.launchAtLogin)
        }

        isUpdatingLaunchAtLogin = false
    }

    func isExpanded(_ section: StatusSection) -> Bool {
        expandedSections.contains(section)
    }

    func setExpanded(_ expanded: Bool, for section: StatusSection) {
        if expanded {
            expandedSections.insert(section)
        } else {
            expandedSections.remove(section)
        }
    }

    private enum Keys {
        static let healthMetric = "healthMetric"
        static let launchAtLogin = "launchAtLogin"
        static let usesColor = "usesColor"
        static let expandedSections = "expandedSections"
    }
}
