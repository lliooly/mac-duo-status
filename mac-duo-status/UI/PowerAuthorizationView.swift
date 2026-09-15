//
//  PowerAuthorizationView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerAuthorizationView: View {
    @EnvironmentObject private var controls: ControlCoordinator

    var compact = false

    private var helperStatus: HelperStatus {
        controls.helperStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if !compact {
                Text(NSLocalizedString("power.advanced", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                Image(systemName: helperStatus == .authorized ? "checkmark.circle" : "lock")
                    .foregroundStyle(
                        helperStatus == .authorized
                            ? DuoStatusStyle.accent
                            : DuoStatusStyle.muted
                    )

                Text(helperStatus.localizedTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DuoStatusStyle.muted)

                Spacer(minLength: 0)

                if helperStatus == .authorized {
                    Button(NSLocalizedString("power.disable", comment: "")) {
                        Task {
                            await controls.unregisterHelper()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(controls.powerOperationState.isPending)
                } else {
                    Button(NSLocalizedString("power.enable", comment: "")) {
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
                Text(NSLocalizedString(error.localizationKey, comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }
}

private extension HelperStatus {
    var localizedTitle: String {
        switch self {
        case .notInstalled:
            return NSLocalizedString("power.helper.not-installed", comment: "")
        case .requiresApproval:
            return NSLocalizedString("power.helper.requires-approval", comment: "")
        case .authorized:
            return NSLocalizedString("power.helper.authorized", comment: "")
        case .unavailable:
            return NSLocalizedString("power.helper.unavailable", comment: "")
        case .failed:
            return NSLocalizedString("power.helper.failed", comment: "")
        }
    }
}
