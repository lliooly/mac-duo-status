//
//  WiFiControlView.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct WiFiControlView: View {
    @EnvironmentObject private var controls: ControlCoordinator
    @EnvironmentObject private var statusStore: SystemStatusStore

    let onBack: () -> Void

    @State private var selectedCandidate: WiFiNetworkCandidate?
    @State private var accessPointCandidate: WiFiNetworkCandidate?
    @State private var showsAccessPointSelection = false
    @State private var showsHiddenNetwork = false
    @State private var hiddenSSID = ""

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    private var hotspots: [WiFiNetworkCandidate] {
        controls.networkCandidates.filter {
            $0.hotspotConfirmation == .confirmed
        }
    }

    private var knownNetworks: [WiFiNetworkCandidate] {
        controls.networkCandidates.filter {
            $0.isKnown && $0.hotspotConfirmation != .confirmed
        }
    }

    private var otherNetworks: [WiFiNetworkCandidate] {
        controls.networkCandidates.filter {
            !$0.isKnown && $0.hotspotConfirmation != .confirmed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()
                .overlay(DuoStatusStyle.divider)

            Toggle(
                NSLocalizedString("wifi.title", comment: ""),
                isOn: Binding(
                    get: { snapshot.network.isWiFiEnabled ?? false },
                    set: { enabled in
                        Task {
                            await controls.setWiFiEnabled(enabled)
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .disabled(snapshot.network.isWiFiEnabled == nil || networkOperationIsPending)
            .accessibilityIdentifier("wifi-toggle")

            if case let .failed(error) = controls.networkOperationState {
                Text(NSLocalizedString(error.localizationKey, comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if controls.lastNetworkRememberRequest,
               let result = controls.lastNetworkResult,
               !result.wasRemembered {
                Text(NSLocalizedString("wifi.connected-not-remembered", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(DuoStatusStyle.muted)
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !hotspots.isEmpty {
                        networkSection(
                            title: NSLocalizedString("wifi.personal-hotspots", comment: ""),
                            networks: hotspots
                        )
                    }

                    networkSection(
                        title: NSLocalizedString("wifi.known-networks", comment: ""),
                        networks: knownNetworks
                    )

                    networkSection(
                        title: NSLocalizedString("wifi.other-networks", comment: ""),
                        networks: otherNetworks
                    )

                    if showsHiddenNetwork {
                        hiddenNetworkEntry
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)

            controlsRow
        }
        .task {
            if controls.networkCandidates.isEmpty {
                await controls.scanNetworks(includeHidden: false)
            }
        }
        .sheet(item: $selectedCandidate) { candidate in
            WiFiCredentialView(candidate: candidate)
                .environmentObject(controls)
        }
        .confirmationDialog(
            NSLocalizedString("wifi.choose-access-point", comment: ""),
            isPresented: $showsAccessPointSelection,
            titleVisibility: .visible
        ) {
            if let candidate = accessPointCandidate {
                ForEach(candidate.selectableAccessPoints) { accessPoint in
                    Button {
                        selectedCandidate = candidate.selectingAccessPoint(accessPoint)
                        accessPointCandidate = nil
                    } label: {
                        HStack {
                            Text(accessPoint.bssid)
                            Spacer(minLength: 12)
                            if let rssi = accessPoint.rssi {
                                Text("\(rssi) dBm")
                                    .foregroundStyle(DuoStatusStyle.muted)
                            }
                        }
                    }
                    .accessibilityIdentifier("wifi-bssid-\(accessPoint.id)")
                }
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                accessPointCandidate = nil
            }
        }
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

            Text(NSLocalizedString("wifi.title", comment: ""))
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 0)

            Button {
                Task {
                    await controls.scanNetworks(includeHidden: false)
                }
            } label: {
                Image(systemName: networkOperationIsPending ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(networkOperationIsPending)
            .accessibilityLabel(NSLocalizedString("wifi.scan", comment: ""))
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsHiddenNetwork.toggle()
                }
            } label: {
                Label(
                    NSLocalizedString("wifi.hidden-network", comment: ""),
                    systemImage: "plus"
                )
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text(NSLocalizedString("wifi.settings", comment: ""))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DuoStatusStyle.muted)
    }

    private func networkSection(
        title: String,
        networks: [WiFiNetworkCandidate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            if networks.isEmpty {
                Text(NSLocalizedString("wifi.no-networks", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(DuoStatusStyle.muted)
                    .padding(.vertical, 4)
            } else {
                ForEach(networks) { network in
                    networkRow(network)
                }
            }
        }
    }

    private func networkRow(_ network: WiFiNetworkCandidate) -> some View {
        let isUnavailable = network.isKnown && network.rssi == nil
        let isCurrent = isCurrentNetwork(network)

        return Button {
            guard !isUnavailable else {
                return
            }
            openNetwork(network)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: network.primarySecurity == .open ? "wifi" : "lock.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isUnavailable ? DuoStatusStyle.muted : .primary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(network.displayName ?? NSLocalizedString("wifi.hidden", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if isUnavailable {
                        Text(NSLocalizedString("wifi.not-found", comment: ""))
                            .font(.system(size: 9))
                            .foregroundStyle(DuoStatusStyle.muted)
                    }
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                } else if let rssi = network.rssi {
                    Image(systemName: signalSymbol(for: rssi))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DuoStatusStyle.muted)
                }

                if network.selectableAccessPoints.count > 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isUnavailable ? 0.52 : 1)
        .disabled(isUnavailable)
        .accessibilityIdentifier("wifi-network-\(network.id)")
    }

    private var hiddenNetworkEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("wifi.hidden-network", comment: ""))
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 6) {
                TextField(
                    NSLocalizedString("wifi.ssid-placeholder", comment: ""),
                    text: $hiddenSSID
                )
                .textFieldStyle(.roundedBorder)

                Button(NSLocalizedString("wifi.scan", comment: "")) {
                    guard let data = hiddenSSID.data(using: .utf8), !data.isEmpty else {
                        return
                    }

                    Task {
                        await controls.scanNetworks(includeHidden: true, ssidData: data)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(hiddenSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var networkOperationIsPending: Bool {
        controls.networkOperationState.isPending
    }

    private func openNetwork(_ network: WiFiNetworkCandidate) {
        if network.selectableAccessPoints.count > 1 {
            accessPointCandidate = network
            showsAccessPointSelection = true
        } else {
            selectedCandidate = network
        }
    }

    private func isCurrentNetwork(_ network: WiFiNetworkCandidate) -> Bool {
        if let ssidData = snapshot.network.ssidData {
            return ssidData == network.ssidData
        }

        return snapshot.network.name != nil && snapshot.network.name == network.displayName
    }

    private func signalSymbol(for rssi: Int) -> String {
        switch NetworkSignalMapper.level(forRSSI: rssi) {
        case 4:
            return "wifi"
        case 3:
            return "wifi"
        case 2:
            return "wifi"
        default:
            return "wifi.exclamationmark"
        }
    }
}
