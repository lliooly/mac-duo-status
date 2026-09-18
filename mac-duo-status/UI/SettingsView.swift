//
//  SettingsView.swift
//  mac-duo-status
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore
    @EnvironmentObject private var controls: ControlCoordinator
    @EnvironmentObject private var wifiAuthorization: LocalAuthenticationWiFiAuthorizer

    @State private var isAuthorizingWiFi = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString("settings.launch-at-login", comment: ""),
                    isOn: $preferences.launchAtLogin
                )

                Toggle(
                    NSLocalizedString("settings.colored-icon", comment: ""),
                    isOn: $preferences.usesColor
                )
            } header: {
                Text(NSLocalizedString("settings.general", comment: ""))
            }

            Section {
                HealthMetricSelector(
                    selection: $preferences.healthMetric
                )
                .onChange(of: preferences.healthMetric) { newMetric in
                    statusStore.setHealthMetric(newMetric)
                }
            } header: {
                Text(NSLocalizedString("settings.indicators", comment: ""))
            }

            Section {
                ForEach(StatusSection.allCases) { section in
                    Toggle(
                        section.localizedTitle,
                        isOn: sectionBinding(for: section)
                    )
                }
            } header: {
                Text(NSLocalizedString("settings.default-sections", comment: ""))
            }

            Section {
                PowerAuthorizationView(compact: true)
            } header: {
                Text(NSLocalizedString("power.advanced", comment: ""))
            }

            Section {
                HStack(spacing: 8) {
                    Image(
                        systemName: wifiAuthorization.isAuthorized
                            ? "checkmark.shield"
                            : "lock.shield"
                    )
                    .foregroundStyle(
                        wifiAuthorization.isAuthorized
                            ? DuoStatusStyle.accent
                            : DuoStatusStyle.muted
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("wifi.authorization.title", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                        Text(
                            NSLocalizedString(
                                wifiAuthorization.isAuthorized
                                    ? "wifi.authorization.authorized"
                                    : "wifi.authorization.not-authorized",
                                comment: ""
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(DuoStatusStyle.muted)
                    }

                    Spacer(minLength: 0)

                    if wifiAuthorization.isAuthorized {
                        Button(NSLocalizedString("wifi.authorization.revoke", comment: "")) {
                            wifiAuthorization.revoke()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                    } else {
                        Button {
                            authorizeWiFi()
                        } label: {
                            if isAuthorizingWiFi {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(NSLocalizedString("wifi.authorization.authorize", comment: ""))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAuthorizingWiFi)
                    }
                }

                Text(NSLocalizedString("wifi.authorization.description", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(DuoStatusStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(NSLocalizedString("settings.wifi", comment: ""))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
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

    private func authorizeWiFi() {
        guard !isAuthorizingWiFi else {
            return
        }

        isAuthorizingWiFi = true
        Task {
            _ = await wifiAuthorization.ensureAuthorized()
            isAuthorizingWiFi = false
        }
    }
}
