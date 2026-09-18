//
//  PowerControlView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerControlView: View {
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
            header

            StatusValueRow(
                title: NSLocalizedString("power.active-mode", comment: ""),
                value: localizedMode(status.activeMode),
                showsDivider: false
            )

            currentPowerSourceRow
            energyModeControls

            if !status.helperStatus.isAuthorized ||
                availableModes.isEmpty ||
                modeReadbackUnavailable {
                batterySettingsFallback
            }

            PowerAuthorizationView()
                .padding(.top, 2)
        }
        .onAppear {
            statusStore.refreshNow()
        }
        .onChange(of: statusStore.snapshot.battery.powerSource) { _ in
            statusStore.refreshNow()
        }
    }

    private var currentPowerSourceRow: some View {
        StatusValueRow(
            title: NSLocalizedString("power.scope.title", comment: ""),
            value: localizedScope(currentScope),
            showsDivider: true
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("common.back", comment: ""))

            Text(NSLocalizedString("power.title", comment: ""))
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var energyModeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("power.modes", comment: ""))
                .font(.system(size: 12, weight: .semibold))

            if availableModes.isEmpty || modeReadbackUnavailable {
                readOnlyModeRows
            } else {
                VStack(spacing: 2) {
                    ForEach(availableModes) { mode in
                        modeRow(mode, isSelected: currentMode == mode)
                    }
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : DuoStatusStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected
                            ? DuoStatusStyle.accent
                            : Color.primary.opacity(0.08),
                        in: Circle()
                    )

                Text(NSLocalizedString(mode.localizationKey, comment: ""))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEditModes)
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
