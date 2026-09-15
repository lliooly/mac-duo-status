//
//  WiFiCredentialView.swift
//  mac-duo-status
//

import Foundation
import AppKit
import Security
import SwiftUI

struct WiFiCredentialView: View {
    @EnvironmentObject private var controls: ControlCoordinator

    let candidate: WiFiNetworkCandidate
    let onBack: () -> Void

    @State private var password = ""
    @State private var username = ""
    @State private var rememberNetwork = false
    @State private var identities: [KeychainIdentityOption] = []
    @State private var selectedIdentityIndex = -1
    @FocusState private var focusedField: CredentialField?

    private enum CredentialField: Hashable {
        case username
        case password
    }

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
        if isEnterprise {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !password.isEmpty ||
                selectedIdentityIndex >= 0
        }

        return !requiresPassword || !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common.back", comment: ""))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName ?? NSLocalizedString("wifi.hidden", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)

                    Text(security.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(DuoStatusStyle.muted)
                }

                Spacer(minLength: 0)
            }

            if isEnterprise {
                TextField(
                    NSLocalizedString("wifi.username", comment: ""),
                    text: $username
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .username)
                .accessibilityIdentifier("wifi-username")

                SecureField(
                    NSLocalizedString("wifi.password", comment: ""),
                    text: $password
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .password)
                .accessibilityIdentifier("wifi-password")

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
                .focused($focusedField, equals: .password)
                .accessibilityIdentifier("wifi-password")
            }

            Toggle(
                NSLocalizedString("wifi.remember", comment: ""),
                isOn: $rememberNetwork
            )
            .toggleStyle(.checkbox)

            if case let .failed(error) = controls.networkOperationState {
                Text(NSLocalizedString(error.localizationKey, comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer(minLength: 0)

                Button(NSLocalizedString("common.cancel", comment: "")) {
                    onBack()
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
            focusFirstField()
        }
        .onAppear {
            focusFirstField()
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
            let error = await controls.connect(
                to: candidate,
                credential: credential,
                remember: rememberNetwork
            )

            if error == nil {
                onBack()
            }
        }
    }

    private func focusFirstField() {
        let field: CredentialField?
        if isEnterprise {
            field = .username
        } else if requiresPassword {
            field = .password
        } else {
            field = nil
        }

        guard let field else {
            return
        }

        // MenuBarExtra uses a non-activating panel. Wait for the view to be laid
        // out before asking SwiftUI to bridge focus to the AppKit text field.
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.keyWindow?.makeKey()
            focusedField = field
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
