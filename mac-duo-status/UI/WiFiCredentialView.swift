//
//  WiFiCredentialView.swift
//  mac-duo-status
//

import Foundation
import Security
import SwiftUI

struct WiFiCredentialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controls: ControlCoordinator

    let candidate: WiFiNetworkCandidate

    @State private var password = ""
    @State private var username = ""
    @State private var rememberNetwork = false
    @State private var identities: [KeychainIdentityOption] = []
    @State private var selectedIdentityIndex = -1

    private var security: WiFiSecurity {
        candidate.primarySecurity
    }

    private var isEnterprise: Bool {
        security.isEnterprise
    }

    private var requiresPassword: Bool {
        security.requiresPassphrase && !isEnterprise
    }

    private var canSubmit: Bool {
        guard security != .unknown else {
            return false
        }

        if isEnterprise {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !password.isEmpty ||
                selectedIdentityIndex >= 0
        }

        return !requiresPassword || !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(candidate.displayName ?? NSLocalizedString("wifi.hidden", comment: ""))
                .font(.system(size: 16, weight: .semibold))

            Text(security.displayName)
                .font(.system(size: 11))
                .foregroundStyle(DuoStatusStyle.muted)

            if isEnterprise {
                TextField(
                    NSLocalizedString("wifi.username", comment: ""),
                    text: $username
                )
                .textFieldStyle(.roundedBorder)

                SecureField(
                    NSLocalizedString("wifi.password", comment: ""),
                    text: $password
                )
                .textFieldStyle(.roundedBorder)

                Picker(
                    NSLocalizedString("wifi.identity", comment: ""),
                    selection: $selectedIdentityIndex
                ) {
                    Text(NSLocalizedString("wifi.identity.none", comment: ""))
                        .tag(-1)

                    ForEach(Array(identities.enumerated()), id: \.offset) { index, identity in
                        Text(identity.title)
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
            } else if requiresPassword {
                SecureField(
                    NSLocalizedString("wifi.password", comment: ""),
                    text: $password
                )
                .textFieldStyle(.roundedBorder)
            }

            Toggle(
                NSLocalizedString("wifi.remember", comment: ""),
                isOn: $rememberNetwork
            )
            .toggleStyle(.checkbox)

            if security == .unknown {
                Text(NSLocalizedString("control.error.unsupported-security", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if case let .failed(error) = controls.networkOperationState {
                Text(NSLocalizedString(error.localizationKey, comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer(minLength: 0)

                Button(NSLocalizedString("common.cancel", comment: "")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(NSLocalizedString("wifi.connect", comment: "")) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || controls.networkOperationState.isPending)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 320)
        .task {
            identities = KeychainIdentityStore.identities()
        }
    }

    private func submit() {
        let credential: WiFiCredential?
        if isEnterprise {
            let identityReference = selectedIdentityIndex >= 0
                ? identities[selectedIdentityIndex].reference
                : nil
            credential = .enterprise(
                username: username.nilIfEmpty,
                password: password.nilIfEmpty,
                identityReference: identityReference
            )
        } else if requiresPassword {
            credential = .passphrase(password)
        } else {
            credential = WiFiCredential.none
        }

        Task {
            await controls.connect(
                to: candidate,
                credential: credential,
                remember: rememberNetwork
            )

            if case .succeeded = controls.networkOperationState {
                dismiss()
            }
        }
    }
}

private struct KeychainIdentityOption: Identifiable, Sendable {
    let id: Data
    let title: String
    let reference: KeychainIdentityReference
}

private enum KeychainIdentityStore {
    static func identities() -> [KeychainIdentityOption] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecReturnPersistentRef: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return []
        }

        let references: [Data]
        if let values = result as? [Data] {
            references = values
        } else if let value = result as? Data {
            references = [value]
        } else {
            references = []
        }

        return references.enumerated().map { index, reference in
            KeychainIdentityOption(
                id: reference,
                title: "\(NSLocalizedString("wifi.identity", comment: "")) \(index + 1)",
                reference: KeychainIdentityReference(persistentReference: reference)
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
