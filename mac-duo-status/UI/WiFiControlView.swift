//
//  WiFiControlView.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct WiFiControlView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var controls: ControlCoordinator
    @EnvironmentObject private var statusStore: SystemStatusStore

    let onBack: () -> Void

    @State private var selectedCandidate: WiFiNetworkCandidate?
    @State private var showsHiddenNetwork = false
    @State private var hiddenSSID = ""

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    private var hotspots: [WiFiNetworkCandidate] {
        WiFiNetworkCandidateGrouping.hotspots(from: controls.networkCandidates)
    }

    private var knownNetworks: [WiFiNetworkCandidate] {
        WiFiNetworkCandidateGrouping.knownNetworks(from: controls.networkCandidates)
    }

    private var otherNetworks: [WiFiNetworkCandidate] {
        WiFiNetworkCandidateGrouping.otherNetworks(from: controls.networkCandidates)
    }

    var body: some View {
        Group {
            if let candidate = selectedCandidate {
                WiFiCredentialView(
                    candidate: candidate,
                    onBack: {
                        selectedCandidate = nil
                    }
                )
                .environmentObject(controls)
            } else {
                networkList
            }
        }
        .task {
            if controls.networkCandidates.isEmpty {
                await controls.scanNetworks(includeHidden: false)
            }
        }
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverPageHeader(
                title: NSLocalizedString("wifi.title", comment: ""),
                subtitle: snapshot.network.name ?? snapshot.network.kind.localizedTitle,
                onBack: onBack
            ) {
                Button {
                    Task {
                        await controls.scanNetworks(includeHidden: false)
                    }
                } label: {
                    Image(systemName: networkOperationIsPending ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(networkOperationIsPending && !reduceMotion ? 180 : 0))
                }
                .buttonStyle(DuoStatusIconButtonStyle())
                .disabled(networkOperationIsPending)
                .accessibilityLabel(NSLocalizedString("wifi.scan", comment: ""))
            }

            DuoStatusCard {
                VStack(alignment: .leading, spacing: 10) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .toggleStyle(.switch)
                    .disabled(snapshot.network.isWiFiEnabled == nil || networkOperationIsPending)
                    .accessibilityIdentifier("wifi-toggle")

                    if case let .failed(error) = controls.networkOperationState {
                        Label(
                            NSLocalizedString(error.localizationKey, comment: ""),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    }

                    if shouldShowHelperAuthorization {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("wifi.authorization.helper-description", comment: ""))
                                .font(.system(size: 11))
                                .foregroundStyle(DuoStatusStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            PowerAuthorizationView(compact: true)
                        }
                    }

                    if controls.lastNetworkRememberRequest,
                       let result = controls.lastNetworkResult,
                       !result.wasRemembered {
                        Text(NSLocalizedString("wifi.connected-not-remembered", comment: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(DuoStatusStyle.muted)
                    }
                }
            }

            DuoStatusCard {
                WiFiNetworkListView(
                    hotspots: hotspots,
                    knownNetworks: knownNetworks,
                    otherNetworks: otherNetworks,
                    currentSSIDData: snapshot.network.ssidData,
                    currentNetworkName: snapshot.network.name,
                    isPending: networkOperationIsPending,
                    onOpenNetwork: openNetwork
                )
                .equatable()
            }

            if showsHiddenNetwork {
                DuoStatusCard {
                    hiddenNetworkEntry
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            controlsRow
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : DuoStatusStyle.quickAnimation) {
                    showsHiddenNetwork.toggle()
                }
            } label: {
                Label(
                    NSLocalizedString("wifi.hidden-network", comment: ""),
                    systemImage: showsHiddenNetwork ? "minus" : "plus"
                )
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wifi-hidden-network-toggle")

            Spacer(minLength: 0)

            Button(action: SettingsWindowAccess.openWiFiSettings) {
                Text(NSLocalizedString("wifi.settings", comment: ""))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(DuoStatusStyle.muted)
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
                .accessibilityIdentifier("wifi-hidden-network-ssid")

                Button(NSLocalizedString("wifi.scan", comment: "")) {
                    let ssid = hiddenSSID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let data = ssid.data(using: .utf8), !data.isEmpty else {
                        return
                    }

                    Task {
                        await controls.scanNetworks(includeHidden: true, ssidData: data)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    hiddenSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        networkOperationIsPending
                )
                .accessibilityIdentifier("wifi-hidden-network-scan")
            }
        }
    }

    private var networkOperationIsPending: Bool {
        controls.networkOperationState.isPending
    }

    private var shouldShowHelperAuthorization: Bool {
        guard controls.helperStatus != .authorized else {
            return false
        }

        guard case let .failed(error) = controls.networkOperationState else {
            return false
        }

        return error == .authorizationRequired || error == .helperUnavailable
    }

    private func openNetwork(_ network: WiFiNetworkCandidate) {
        guard !networkOperationIsPending else {
            return
        }

        beginConnectionOrShowCredentials(for: network)
    }

    private func beginConnectionOrShowCredentials(for network: WiFiNetworkCandidate) {
        guard !networkOperationIsPending else {
            return
        }

        if network.isKnown || isOpenSecurity(network.primarySecurity) {
            Task {
                let error = await controls.connect(
                    to: network,
                    credential: nil,
                    remember: false
                )

                if error == .credentialsRequired || error == .authenticationFailed {
                    selectedCandidate = network
                }
            }
        } else {
            selectedCandidate = network
        }
    }

    private func isOpenSecurity(_ security: WiFiSecurity) -> Bool {
        switch security {
        case .open, .owe, .oweTransition:
            return true
        default:
            return false
        }
    }
}

private struct WiFiNetworkListView: View, Equatable {
    let hotspots: [WiFiNetworkCandidate]
    let knownNetworks: [WiFiNetworkCandidate]
    let otherNetworks: [WiFiNetworkCandidate]
    let currentSSIDData: Data?
    let currentNetworkName: String?
    let isPending: Bool
    let onOpenNetwork: (WiFiNetworkCandidate) -> Void

    static func == (lhs: WiFiNetworkListView, rhs: WiFiNetworkListView) -> Bool {
        lhs.hotspots == rhs.hotspots &&
            lhs.knownNetworks == rhs.knownNetworks &&
            lhs.otherNetworks == rhs.otherNetworks &&
            lhs.currentSSIDData == rhs.currentSSIDData &&
            lhs.currentNetworkName == rhs.currentNetworkName &&
            lhs.isPending == rhs.isPending
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if !hotspots.isEmpty {
                    networkSection(
                        title: NSLocalizedString("wifi.personal-hotspots", comment: ""),
                        networks: hotspots
                    )
                }

                if !knownNetworks.isEmpty {
                    networkSection(
                        title: NSLocalizedString("wifi.known-networks", comment: ""),
                        networks: knownNetworks
                    )
                }

                networkSection(
                    title: NSLocalizedString("wifi.other-networks", comment: ""),
                    networks: otherNetworks
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 320)
    }

    private func networkSection(
        title: String,
        networks: [WiFiNetworkCandidate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DuoStatusStyle.muted)
                .padding(.horizontal, 4)

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
        let isCurrent = isCurrentNetwork(network)

        return Button {
            onOpenNetwork(network)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: network.primarySecurity == .open ? "wifi" : "lock.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(network.displayName ?? NSLocalizedString("wifi.hidden", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
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
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(
                isCurrent ? DuoStatusStyle.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .accessibilityIdentifier("wifi-network-\(network.id)")
    }

    private func isCurrentNetwork(_ network: WiFiNetworkCandidate) -> Bool {
        if let currentSSIDData {
            return currentSSIDData == network.ssidData
        }

        return currentNetworkName != nil && currentNetworkName == network.displayName
    }

    private func signalSymbol(for rssi: Int) -> String {
        switch NetworkSignalMapper.level(forRSSI: rssi) {
        case 4, 3, 2:
            return "wifi"
        default:
            return "wifi.exclamationmark"
        }
    }
}
