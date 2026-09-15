//
//  StatusPopoverView.swift
//  mac-duo-status
//

import Foundation
import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore

    private let popoverWidth: CGFloat = 320

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary

            popoverDivider

            StatusSectionView(
                section: .battery,
                isExpanded: sectionBinding(for: .battery)
            ) {
                batteryDetails
            }
            .frame(maxWidth: .infinity)

            StatusSectionView(
                section: .network,
                isExpanded: sectionBinding(for: .network)
            ) {
                networkDetails
            }
            .frame(maxWidth: .infinity)

            StatusSectionView(
                section: .systemHealth,
                isExpanded: sectionBinding(for: .systemHealth)
            ) {
                healthDetails
            }
            .frame(maxWidth: .infinity)

            settingsAction
                .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: popoverWidth)
        .background(popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 10)
        .tint(DuoStatusStyle.accent)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            statusStore.refreshNow()
        }
    }

    @ViewBuilder
    private var popoverBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.46, green: 0.73, blue: 1.0, opacity: 0.34),
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.28, green: 0.60, blue: 1.0, opacity: 0.24),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 280
                        )
                    )
            }
        }
    }

    private var popoverDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.56))
            .frame(height: 1)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var settingsAction: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    settingsActionLabel
                }
                .buttonStyle(ActivateApplicationBeforeActionButtonStyle())
            } else {
                Button(action: SettingsWindowAccess.openLegacySettings) {
                    settingsActionLabel
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityIdentifier("open-settings")
    }

    private var settingsActionLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DuoStatusStyle.muted)
                .frame(width: 20)

            Text(NSLocalizedString("settings.open", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DuoStatusStyle.muted)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var summary: some View {
        HStack(spacing: 8) {
            CombinedStatusIcon(
                snapshot: snapshot,
                size: 50,
                usesColor: preferences.usesColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Duo Status")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text(
                    "\(NSLocalizedString("status.updated", comment: "")) " +
                    snapshot.lastUpdated.formatted(date: .omitted, time: .shortened)
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DuoStatusStyle.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    value: "\(Int((chargeFraction * 100).rounded()))%",
                    showsDivider: true
                )
            }

            if let isCharging = snapshot.battery.isCharging {
                StatusValueRow(
                    title: NSLocalizedString("battery.charging", comment: ""),
                    value: isCharging
                        ? NSLocalizedString("common.yes", comment: "")
                        : NSLocalizedString("common.no", comment: ""),
                    showsDivider: true
                )
            }

            StatusValueRow(
                title: NSLocalizedString("battery.power-source", comment: ""),
                value: snapshot.battery.powerSource.localizedTitle,
                showsDivider: true
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
                value: snapshot.network.kind.localizedTitle,
                showsDivider: true
            )

            if snapshot.network.kind == .wifi || snapshot.network.kind == .hotspot {
                StatusValueRow(
                    title: NSLocalizedString("network.name", comment: ""),
                    value: snapshot.network.name
                        ?? NSLocalizedString("status.unavailable", comment: ""),
                    showsDivider: true
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
        HealthMetricSelector(
            selection: Binding(
                get: { preferences.healthMetric },
                set: { statusStore.setHealthMetric($0) }
            )
        )
        .padding(.bottom, 8)

        if let details = selectedMetricDetails {
            StatusValueRow(
                title: details.title,
                value: details.value,
                showsDivider: true
            )

            if let score = snapshot.health.selectedScore {
                StatusValueRow(
                    title: NSLocalizedString("health.score", comment: ""),
                    value: String(format: "%.2f", score),
                    showsDivider: true
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
