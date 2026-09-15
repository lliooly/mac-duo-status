//
//  WiFiLocationAuthorization.swift
//  mac-duo-status
//

import CoreLocation
import Foundation

@MainActor
final class WiFiLocationAuthorization: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiLocationAuthorization()

    private let locationManager: CLLocationManager
    private var pendingRequests: [CheckedContinuation<Bool, Never>] = []
    private var authorizationTimeoutTask: Task<Void, Never>?

    private static let authorizationTimeoutNanoseconds: UInt64 = 15_000_000_000

    private override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
    }

    func requestAccessIfNeeded() async -> Bool {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                pendingRequests.append(continuation)
                guard pendingRequests.count == 1 else {
                    return
                }

                authorizationTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: Self.authorizationTimeoutNanoseconds)
                    } catch {
                        return
                    }

                    guard let self else {
                        return
                    }

                    self.resolvePendingRequests(isAuthorized: false)
                }
                locationManager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else {
            return
        }

        let isAuthorized = manager.authorizationStatus == .authorized
        resolvePendingRequests(isAuthorized: isAuthorized)
    }

    private func resolvePendingRequests(isAuthorized: Bool) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil

        let requests = pendingRequests
        pendingRequests.removeAll()
        requests.forEach { $0.resume(returning: isAuthorized) }
    }
}
