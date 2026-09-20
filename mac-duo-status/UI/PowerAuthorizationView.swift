//
//  PowerAuthorizationView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerAuthorizationView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var controls: ControlCoordinator

    var compact = false

    private var helperStatus: HelperStatus {
        controls.helperStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if !compact {
                Text(localization.string("power.advanced"))
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                Image(systemName: helperStatus == .authorized ? "checkmark.circle" : "lock")
                    .foregroundStyle(
                        helperStatus == .authorized
                            ? DuoStatusStyle.accent
                            : DuoStatusStyle.muted
                    )

                Text(localization.string(helperStatus.localizationKey))
                    .font(.system(size: 11))
                    .foregroundStyle(DuoStatusStyle.muted)

                Spacer(minLength: 0)

                if helperStatus == .authorized {
                    Button(localization.string("power.disable")) {
                        Task {
                            await controls.unregisterHelper()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(controls.powerOperationState.isPending)
                } else {
                    Button(
                        localization.string(
                            helperStatus.isRepairable ? "power.repair" : "power.enable"
                        )
                    ) {
                        Task {
                            await controls.requestHelperApproval()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(controls.powerOperationState.isPending)
                }
            }

            if case let .failed(error) = controls.powerOperationState {
                Text(localization.string(error.localizationKey))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }
}

private extension HelperStatus {
    var isRepairable: Bool {
        if case .unavailable = self {
            return true
        }
        return false
    }

    var localizationKey: String {
        switch self {
        case .notInstalled:
            return "power.helper.not-installed"
        case .requiresApproval:
            return "power.helper.requires-approval"
        case .authorized:
            return "power.helper.authorized"
        case .unavailable:
            return "power.helper.unavailable"
        case .failed:
            return "power.helper.failed"
        }
    }
}
