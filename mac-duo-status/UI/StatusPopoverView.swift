//
//  StatusPopoverView.swift
//  mac-duo-status
//

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
        .onChange(of: preferences.healthMetric) { newMetric in
            statusStore.setHealthMetric(newMetric)
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

                Text(NSLocalizedString("status.local-only", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    snapshot.lastUpdated,
                    format: Date.FormatStyle(date: .omitted, time: .shortened)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var batteryDetails: some View {
        if case let .unavailable(reason) = snapshot.battery.availability {
            UnavailableStatusView(reason: reason)
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
        }
    }

    @ViewBuilder
    private var networkDetails: some View {
        if case let .unavailable(reason) = snapshot.network.availability {
            UnavailableStatusView(reason: reason)
        } else {
            StatusValueRow(
                title: NSLocalizedString("network.type", comment: ""),
                value: snapshot.network.kind.localizedTitle
            )

            if let name = snapshot.network.name {
                StatusValueRow(
                    title: NSLocalizedString("network.name", comment: ""),
                    value: name
                )
            }

            if let signalLevel = snapshot.network.signalLevel {
                StatusValueRow(
                    title: NSLocalizedString("network.signal", comment: ""),
                    value: "\(signalLevel)/4"
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
                set: { preferences.healthMetric = $0 }
            )
        ) {
            ForEach(HealthMetric.allCases) { metric in
                Text(metric.localizedTitle)
                    .tag(metric)
            }
        }
        .pickerStyle(.segmented)

        if case let .unavailable(reason) = snapshot.health.availability {
            UnavailableStatusView(reason: reason)
                .padding(.top, 4)
        } else {
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
