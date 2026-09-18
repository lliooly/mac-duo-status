//
//  PowerControlView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerControlView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var controls: ControlCoordinator
    @EnvironmentObject private var statusStore: SystemStatusStore

    let onBack: () -> Void

    private var status: PowerPolicyStatus {
        statusStore.snapshot.powerPolicy
    }

    private var availableModes: [PowerMode] {
        [.automatic, .lowPower, .highPower].filter {
            status.capabilities.supportedPowerModes.contains($0)
        }
    }

    private var currentScope: PowerSourceScope? {
        switch statusStore.snapshot.battery.powerSource {
        case .battery:
            return .battery
        case .powerAdapter:
            return .powerAdapter
        case .unknown:
            return nil
        }
    }

    private var currentMode: PowerMode? {
        currentScope.flatMap(mode(for:))
    }

    private var modeReadbackUnavailable: Bool {
        guard let currentScope,
              status.capabilities.energyModeScopes.contains(currentScope)
        else {
            return true
        }

        return currentMode == nil
    }

    private var canEditModes: Bool {
        guard let currentScope else {
            return false
        }

        return status.helperStatus.isAuthorized &&
            status.capabilities.energyModeScopes.contains(currentScope) &&
            !availableModes.isEmpty &&
            currentMode != nil &&
            !controls.powerOperationState.isPending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverPageHeader(
                title: NSLocalizedString("power.title", comment: ""),
                subtitle: localizedMode(status.activeMode),
                onBack: onBack
            )

            powerSummaryCard
            energyModeControls

            DuoStatusCard {
                PowerAuthorizationView()
            }
        }
        .onAppear {
            statusStore.refreshNow()
        }
        .onChange(of: statusStore.snapshot.battery.powerSource) { _ in
            statusStore.refreshNow()
        }
    }

    private var powerSummaryCard: some View {
        DuoStatusCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: statusStore.snapshot.battery.isCharging == true
                        ? "battery.100.bolt"
                        : "battery.100")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DuoStatusStyle.success, .primary)
                        .frame(width: 28)

                    Text(NSLocalizedString("power.active-mode", comment: ""))
                        .font(.system(size: 13, weight: .semibold))

                    Spacer(minLength: 0)

                    Text(localizedMode(status.activeMode))
                        .font(.system(size: 13, weight: .semibold))
                }

                Divider()
                    .overlay(DuoStatusStyle.divider)
                    .padding(.vertical, 11)

                StatusValueRow(
                    title: NSLocalizedString("power.scope.title", comment: ""),
                    value: localizedScope(currentScope)
                )
            }
        }
    }

    @ViewBuilder
    private var energyModeControls: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.accent)

                    Text(NSLocalizedString("power.modes", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                }

                if availableModes.isEmpty || modeReadbackUnavailable {
                    readOnlyModeRows
                } else {
                    VStack(spacing: 5) {
                        ForEach(availableModes) { mode in
                            modeRow(mode, isSelected: currentMode == mode)
                        }
                    }
                }

                if !status.helperStatus.isAuthorized ||
                    availableModes.isEmpty ||
                    modeReadbackUnavailable {
                    Divider()
                        .overlay(DuoStatusStyle.divider)
                        .padding(.top, 2)

                    batterySettingsFallback
                }
            }
        }
    }

    @ViewBuilder
    private var readOnlyModeRows: some View {
        StatusValueRow(
            title: NSLocalizedString("power.current-mode", comment: ""),
            value: localizedMode(modeReadbackUnavailable ? nil : currentMode)
        )
    }

    private func modeRow(_ mode: PowerMode, isSelected: Bool) -> some View {
        Button {
            guard let currentScope else {
                return
            }

            Task {
                await controls.setPowerMode(mode, scope: currentScope)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? DuoStatusStyle.accent : DuoStatusStyle.muted)
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? DuoStatusStyle.accent.opacity(0.13)
                            : DuoStatusStyle.controlFill,
                        in: Circle()
                    )

                Text(NSLocalizedString(mode.localizationKey, comment: ""))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 40)
            .background(
                isSelected ? DuoStatusStyle.accent.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEditModes)
        .animation(reduceMotion ? nil : DuoStatusStyle.quickAnimation, value: isSelected)
        .accessibilityIdentifier("power-mode-\(mode.rawValue)")
    }

    private var batterySettingsFallback: some View {
        Button {
            SettingsWindowAccess.openBatterySettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DuoStatusStyle.muted)

                Text(NSLocalizedString("power.open-system-settings", comment: ""))
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DuoStatusStyle.muted)
            }
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("open-battery-settings")
    }

    private func mode(for scope: PowerSourceScope) -> PowerMode? {
        switch scope {
        case .battery:
            return status.batteryMode
        case .powerAdapter:
            return status.adapterMode
        }
    }

    private func localizedMode(_ mode: PowerMode?) -> String {
        guard let mode else {
            return NSLocalizedString("status.unavailable", comment: "")
        }

        return NSLocalizedString(mode.localizationKey, comment: "")
    }

    private func localizedScope(_ scope: PowerSourceScope?) -> String {
        guard let scope else {
            return NSLocalizedString("status.unavailable", comment: "")
        }

        return NSLocalizedString(scope.localizationKey, comment: "")
    }
}

private extension PowerMode {
    var systemImageName: String {
        switch self {
        case .automatic:
            return "battery.100"
        case .lowPower:
            return "battery.25"
        case .highPower:
            return "bolt.fill"
        }
    }
}
