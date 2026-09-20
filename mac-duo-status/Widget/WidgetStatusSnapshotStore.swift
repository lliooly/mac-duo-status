//
//  WidgetStatusSnapshotStore.swift
//  mac-duo-status
//

import Foundation
import OSLog

struct WidgetStatusSnapshotStore {
    private static let logger = Logger(
        subsystem: "com.shishishi3.mac-duo-status",
        category: "WidgetSnapshot"
    )
    private let injectedDefaults: UserDefaults?
    private let injectedContainerURL: URL?

    init(defaults: UserDefaults? = nil) {
        self.injectedDefaults = defaults
        self.injectedContainerURL = nil
    }

    init(containerURL: URL) {
        self.injectedDefaults = nil
        self.injectedContainerURL = containerURL
    }

    func read() -> WidgetStatusSnapshot? {
        if let injectedDefaults {
            guard let data = injectedDefaults.data(forKey: WidgetStatusConstants.snapshotKey) else {
                return nil
            }
            return try? JSONDecoder().decode(WidgetStatusSnapshot.self, from: data)
        }

        guard let url = snapshotURL() else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WidgetStatusSnapshot.self, from: data)
        } catch {
            // A widget can be added before the main app has published its first snapshot.
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Self.logger.error("Cannot read widget snapshot: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    @discardableResult
    func write(_ snapshot: WidgetStatusSnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot)
            if let injectedDefaults {
                injectedDefaults.set(data, forKey: WidgetStatusConstants.snapshotKey)
                return true
            }

            guard let url = snapshotURL() else { return false }
            // Commit before requesting a timeline reload. Atomic replacement lets the
            // extension read either complete snapshot, never a partially written JSON.
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Self.logger.error("Cannot write widget snapshot: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func snapshotURL() -> URL? {
        // Both processes resolve the shared container through their App Group
        // entitlement. File reads avoid cfprefsd's per-process preferences cache.
        guard let container = injectedContainerURL
            ?? FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: WidgetStatusConstants.appGroupIdentifier
            )
        else {
            Self.logger.error("Widget App Group container is unavailable")
            return nil
        }
        return container.appendingPathComponent("widget-status-snapshot.json")
    }
}
