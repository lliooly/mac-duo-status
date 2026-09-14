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

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMetric = defaults.string(forKey: Keys.healthMetric)
            .flatMap(HealthMetric.init(rawValue:))
        self.healthMetric = storedMetric ?? .cpu
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.usesColor = defaults.object(forKey: Keys.usesColor) as? Bool ?? false

        let storedSections = defaults.array(forKey: Keys.expandedSections) as? [String] ?? []
        self.expandedSections = Set(
            storedSections.compactMap(StatusSection.init(rawValue:))
        )
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
