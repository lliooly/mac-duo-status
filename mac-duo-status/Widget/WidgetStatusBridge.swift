//
//  WidgetStatusBridge.swift
//  mac-duo-status
//

import Foundation
import WidgetKit

@MainActor
final class WidgetStatusBridge {
    private let snapshotStore: WidgetStatusSnapshotStore
    private let nowProvider: () -> Date
    private let reloadHandler: () -> Void
    private var lastPublishedSnapshot: WidgetStatusSnapshot?
    private var lastWriteDate = Date.distantPast

    init() {
        self.snapshotStore = WidgetStatusSnapshotStore()
        self.nowProvider = { Date() }
        self.reloadHandler = { Self.reloadWidgetTimeline() }
    }

    convenience init(snapshotStore: WidgetStatusSnapshotStore) {
        self.init(
            snapshotStore: snapshotStore,
            nowProvider: { Date() },
            reloadHandler: { Self.reloadWidgetTimeline() }
        )
    }

    convenience init(
        snapshotStore: WidgetStatusSnapshotStore,
        reloadHandler: @escaping () -> Void
    ) {
        self.init(
            snapshotStore: snapshotStore,
            nowProvider: { Date() },
            reloadHandler: reloadHandler
        )
    }

    init(
        snapshotStore: WidgetStatusSnapshotStore,
        nowProvider: @escaping () -> Date,
        reloadHandler: @escaping () -> Void
    ) {
        self.snapshotStore = snapshotStore
        self.nowProvider = nowProvider
        self.reloadHandler = reloadHandler
    }

    func publish(snapshot: SystemStatusSnapshot, usesColor: Bool) {
        let now = nowProvider()
        let candidate = WidgetStatusSnapshot(
            snapshot: snapshot,
            usesColor: usesColor,
            updatedAt: now
        )
        let contentChanged = lastPublishedSnapshot.map {
            !$0.hasSameDisplayContent(as: candidate)
        } ?? true
        let heartbeatDue = now.timeIntervalSince(lastWriteDate)
            >= WidgetStatusConstants.writeHeartbeatInterval

        guard contentChanged || heartbeatDue else {
            return
        }

        guard snapshotStore.write(candidate) else {
            return
        }

        lastPublishedSnapshot = candidate
        lastWriteDate = now

        guard contentChanged else {
            return
        }

        reloadHandler()
    }

    private static func reloadWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStatusConstants.kind)
    }
}

private extension WidgetStatusSnapshot {
    init(
        snapshot: SystemStatusSnapshot,
        usesColor: Bool,
        updatedAt: Date
    ) {
        self.init(
            updatedAt: updatedAt,
            battery: Battery(
                isAvailable: snapshot.battery.availability.isAvailable,
                hasBuiltInBattery: snapshot.battery.hasBuiltInBattery,
                chargeFraction: snapshot.battery.chargeFraction,
                isCharging: snapshot.battery.isCharging,
                isLowPowerModeEnabled: snapshot.battery.isLowPowerModeEnabled
            ),
            network: Network(
                isAvailable: snapshot.network.availability.isAvailable,
                kind: WidgetNetworkKind(rawValue: snapshot.network.kind.rawValue)
                    ?? .unavailable
            ),
            healthDotCount: snapshot.health.dotCount,
            usesColor: usesColor
        )
    }
}
