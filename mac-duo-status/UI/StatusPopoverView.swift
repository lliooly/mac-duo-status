//
//  StatusPopoverView.swift
//  mac-duo-status
//

import Foundation
import SwiftUI

struct StatusPopoverView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary

                Divider()

                StatusSectionView(
                    section: .battery,
                    isExpanded: sectionBinding(for: .battery)
                ) {
                    batteryDetails
                }

                StatusSectionView(
                    section: .network,
                    isExpanded: sectionBinding(for: .network)
                ) {
                    networkDetails
                }

                StatusSectionView(
                    section: .systemHealth,
                    isExpanded: sectionBinding(for: .systemHealth)
                ) {
                    healthDetails
                }
            }
            .padding(16)
        }
        .frame(width: 360)
        .onAppear {
            statusStore.refreshNow()
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            CombinedStatusIcon(
                snapshot: snapshot,
                size: 64,
                usesColor: preferences.usesColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Duo Status")
                    .font(.title3.weight(.semibold))

                Text(
                    "\(NSLocalizedString("status.updated", comment: "")) " +
                    snapshot.lastUpdated.formatted(date: .omitted, time: .shortened)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var batteryDetails: some View {
        if snapshot.battery.availability.reason != nil {
            UnavailableStatusView(reason: nil)
        } else if !snapshot.battery.hasBuiltInBattery {
            UnavailableStatusView(
                reason: NSLocalizedString("battery.no-built-in", comment: "")
            )
        } else {
            if let chargeFraction = snapshot.battery.chargeFraction {
                StatusValueRow(
                    title: NSLocalizedString("battery.charge", comment: ""),
                    value: "\(Int((chargeFraction * 100).rounded()))%"
                )
            }

            if let isCharging = snapshot.battery.isCharging {
                StatusValueRow(
                    title: NSLocalizedString("battery.charging", comment: ""),
                    value: isCharging
                        ? NSLocalizedString("common.yes", comment: "")
                        : NSLocalizedString("common.no", comment: "")
                )
            }

            StatusValueRow(
                title: NSLocalizedString("battery.power-source", comment: ""),
                value: snapshot.battery.powerSource.localizedTitle
            )

            if let isLowPowerModeEnabled = snapshot.battery.isLowPowerModeEnabled {
                StatusValueRow(
                    title: NSLocalizedString("battery.low-power-mode", comment: ""),
                    value: isLowPowerModeEnabled
                        ? NSLocalizedString("common.yes", comment: "")
                        : NSLocalizedString("common.no", comment: "")
                )
            }
        }
    }

    @ViewBuilder
    private var networkDetails: some View {
        if snapshot.network.availability.reason != nil {
            UnavailableStatusView(reason: nil)
        } else {
            StatusValueRow(
                title: NSLocalizedString("network.type", comment: ""),
                value: snapshot.network.kind.localizedTitle
            )

            if snapshot.network.kind == .wifi || snapshot.network.kind == .hotspot {
                StatusValueRow(
                    title: NSLocalizedString("network.name", comment: ""),
                    value: snapshot.network.name
                        ?? NSLocalizedString("status.unavailable", comment: "")
                )
            }

            if snapshot.network.shouldShowWiFiSignal {
                StatusValueRow(
                    title: NSLocalizedString("network.signal", comment: ""),
                    value: snapshot.network.signalLevel.map { "\($0)/4" }
                        ?? NSLocalizedString("status.unavailable", comment: "")
                )
            }
        }
    }

    @ViewBuilder
    private var healthDetails: some View {
        Picker(
            NSLocalizedString("health.metric", comment: ""),
            selection: Binding(
                get: { preferences.healthMetric },
                set: { statusStore.setHealthMetric($0) }
            )
        ) {
            ForEach(HealthMetric.allCases) { metric in
                Text(metric.localizedTitle)
                    .tag(metric)
            }
        }
        .pickerStyle(.segmented)

        if let details = selectedMetricDetails {
            StatusValueRow(title: details.title, value: details.value)

            if let score = snapshot.health.selectedScore {
                StatusValueRow(
                    title: NSLocalizedString("health.score", comment: ""),
                    value: String(format: "%.2f", score)
                )
            }

            if let dotCount = snapshot.health.dotCount {
                StatusValueRow(
                    title: NSLocalizedString("health.dots", comment: ""),
                    value: "\(dotCount)/4"
                )
            }
        } else {
            UnavailableStatusView(reason: nil)
                .padding(.top, 4)
        }
    }

    private var selectedMetricDetails: (title: String, value: String)? {
        switch preferences.healthMetric {
        case .cpu:
            guard let usage = snapshot.health.cpuUsagePercent else {
                return nil
            }

            return (
                NSLocalizedString("health.metric.cpu", comment: ""),
                String(format: "%.0f%%", usage)
            )
        case .thermal:
            guard let thermalState = snapshot.health.thermalState else {
                return nil
            }

            return (
                NSLocalizedString("health.metric.thermal", comment: ""),
                thermalState.localizedTitle
            )
        case .load:
            guard let load = snapshot.health.oneMinuteLoad else {
                return nil
            }

            return (
                NSLocalizedString("health.load.one-minute", comment: ""),
                String(format: "%.2f", load)
            )
        }
    }

    private func sectionBinding(for section: StatusSection) -> Binding<Bool> {
        Binding(
            get: {
                preferences.isExpanded(section)
            },
            set: { newValue in
                preferences.setExpanded(newValue, for: section)
            }
        )
    }
}

private extension PowerSource {
    var localizedTitle: String {
        switch self {
        case .battery:
            return NSLocalizedString("battery.power-source.battery", comment: "")
        case .powerAdapter:
            return NSLocalizedString("battery.power-source.adapter", comment: "")
        case .unknown:
            return NSLocalizedString("status.unavailable", comment: "")
        }
    }
}

private extension ThermalState {
    var localizedTitle: String {
        switch self {
        case .nominal:
            return NSLocalizedString("health.thermal.nominal", comment: "")
        case .fair:
            return NSLocalizedString("health.thermal.fair", comment: "")
        case .serious:
            return NSLocalizedString("health.thermal.serious", comment: "")
        case .critical:
            return NSLocalizedString("health.thermal.critical", comment: "")
        }
    }
}

private extension NetworkKind {
    var localizedTitle: String {
        switch self {
        case .wifi:
            return NSLocalizedString("network.kind.wifi", comment: "")
        case .ethernet:
            return NSLocalizedString("network.kind.ethernet", comment: "")
        case .hotspot:
            return NSLocalizedString("network.kind.hotspot", comment: "")
        case .disconnected:
            return NSLocalizedString("network.kind.disconnected", comment: "")
        case .unavailable:
            return NSLocalizedString("status.unavailable", comment: "")
        }
    }
}
