//
//  NetworkProvider.swift
//  mac-duo-status
//

import CoreWLAN
import Foundation
import Network

enum NetworkSignalMapper {
    nonisolated static func level(forRSSI rssi: Int) -> Int {
        if rssi >= -50 {
            return 4
        }

        if rssi >= -60 {
            return 3
        }

        if rssi >= -70 {
            return 2
        }

        if rssi >= -80 {
            return 1
        }

        return 0
    }
}

final class NetworkProvider: NSObject, NetworkProviding, CWEventDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let monitorQueue = DispatchQueue(label: "com.shishishi3.duo-status.network")
    private let wifiClient = CWWiFiClient.shared()

    private var pathMonitor: NWPathMonitor?
    private var changeHandler: (@Sendable () -> Void)?

    func read() async -> NetworkStatus {
        guard let path = currentPath() else {
            return .unavailable(reason: "Network monitoring is unavailable")
        }

        guard path.status == .satisfied else {
            return NetworkStatus(
                availability: .available,
                kind: .disconnected,
                name: nil,
                rssi: nil,
                signalLevel: nil,
                hotspotConfirmed: false
            )
        }

        if path.usesInterfaceType(.wifi) {
            return readWiFiStatus()
        }

        if path.usesInterfaceType(.wiredEthernet) {
            return NetworkStatus(
                availability: .available,
                kind: .ethernet,
                name: nil,
                rssi: nil,
                signalLevel: nil,
                hotspotConfirmed: false
            )
        }

        return .unavailable(reason: "This network interface is not supported")
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        guard pathMonitor == nil else {
            lock.unlock()
            return
        }

        changeHandler = handler
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] _ in
            self?.notifyChange()
        }
        monitor.start(queue: monitorQueue)

        wifiClient.delegate = self
        for event in Self.wifiEvents {
            try? wifiClient.startMonitoringEvent(with: event)
        }
    }

    func stopObserving() {
        lock.lock()
        let monitor = pathMonitor
        pathMonitor = nil
        changeHandler = nil
        lock.unlock()

        monitor?.cancel()
        for event in Self.wifiEvents {
            try? wifiClient.stopMonitoringEvent(with: event)
        }
        wifiClient.delegate = nil
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        notifyChange()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        notifyChange()
    }

    func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        notifyChange()
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        notifyChange()
    }

    private static let wifiEvents: [CWEventType] = [
        .ssidDidChange,
        .linkDidChange,
        .linkQualityDidChange,
        .powerDidChange
    ]

    private func currentPath() -> NWPath? {
        lock.lock()
        let path = pathMonitor?.currentPath
        lock.unlock()
        return path
    }

    private func readWiFiStatus() -> NetworkStatus {
        let interface = wifiClient.interface()
        let name = interface?.ssid()?.trimmedEmptyToNil
        let rssi = interface.map { $0.rssiValue() }.flatMap { $0 == 0 ? nil : $0 }

        return NetworkStatus(
            availability: .available,
            kind: .wifi,
            name: name,
            rssi: rssi,
            signalLevel: rssi.map(NetworkSignalMapper.level(forRSSI:)),
            hotspotConfirmed: false
        )
    }

    private func notifyChange() {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?()
    }
}

private extension String {
    var trimmedEmptyToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
