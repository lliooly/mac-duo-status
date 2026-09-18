//
//  PMSetPowerBackend.swift
//  DuoStatusPowerHelper
//

import Foundation

struct PMSetCommandResult {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var isSuccessful: Bool {
        terminationStatus == 0 &&
            standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PMSetCommandError: Error {
    case launchFailed
    case timedOut
}

protocol PMSetCommandRunning: Sendable {
    func run(arguments: [String]) throws -> PMSetCommandResult
}

final class PMSetProcessRunner: PMSetCommandRunning, @unchecked Sendable {
    private let timeout: DispatchTimeInterval

    init(timeout: DispatchTimeInterval = .seconds(3)) {
        self.timeout = timeout
    }

    func run(arguments: [String]) throws -> PMSetCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }

        do {
            try process.run()
        } catch {
            throw PMSetCommandError.launchFailed
        }

        guard termination.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = termination.wait(timeout: .now() + .seconds(1))
            throw PMSetCommandError.timedOut
        }

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return PMSetCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

final class PMSetPowerBackend: PowerBackend, @unchecked Sendable {
    private let runner: any PMSetCommandRunning
    private let modeKey: String?
    private let writeLock = NSLock()

    let capabilities: PowerBackendCapabilities

    init(commandRunner: any PMSetCommandRunning = PMSetProcessRunner()) {
        runner = commandRunner

        let detected = Self.detectCapabilities(using: commandRunner)
        modeKey = detected.modeKey
        capabilities = detected.capabilities
    }

    func readPowerState() -> (
        batteryMode: String?,
        adapterMode: String?,
        activeMode: String?,
        chargeLimit: NSNumber?
    ) {
        guard let modeKey else {
            return (nil, nil, nil, nil)
        }

        let customOutput: PMSetCommandResult
        do {
            customOutput = try runner.run(arguments: ["-g", "custom"])
        } catch {
            return (nil, nil, nil, nil)
        }

        guard customOutput.isSuccessful,
              let scopedModes = PMSetPowerModeParser.parseScopedModes(
                  customOutput.standardOutput
              ),
              scopedModes.battery.key == modeKey,
              scopedModes.adapter.key == modeKey
        else {
            return (nil, nil, nil, nil)
        }

        let activeMode: String?
        do {
            let activeOutput = try runner.run(arguments: ["-g"])
            if activeOutput.isSuccessful,
               let activeReadout = PMSetPowerModeParser.parseActiveMode(
                   activeOutput.standardOutput
               ),
               activeReadout.key == modeKey {
                activeMode = PMSetPowerModeParser.modeName(for: activeReadout)
            } else {
                activeMode = nil
            }
        } catch {
            activeMode = nil
        }

        return (
            PMSetPowerModeParser.modeName(for: scopedModes.battery),
            PMSetPowerModeParser.modeName(for: scopedModes.adapter),
            activeMode,
            nil
        )
    }

    func setPowerMode(scope: String, mode: String) throws {
        guard let modeKey,
              capabilities.energyModeScopes.contains(scope),
              capabilities.supportedPowerModes.contains(mode),
              let value = PMSetPowerModeParser.value(for: mode, key: modeKey)
        else {
            throw PowerBackendError.unsupported
        }

        let scopeArgument: String
        switch scope {
        case "battery":
            scopeArgument = "-b"
        case "powerAdapter":
            scopeArgument = "-c"
        default:
            throw PowerBackendError.invalidParameter
        }

        writeLock.lock()
        defer { writeLock.unlock() }

        do {
            let result = try runner.run(
                arguments: [scopeArgument, modeKey, String(value)]
            )
            guard result.isSuccessful else {
                throw PowerBackendError.executionFailed
            }
        } catch let error as PowerBackendError {
            throw error
        } catch PMSetCommandError.timedOut {
            throw PowerBackendError.timeout
        } catch {
            throw PowerBackendError.executionFailed
        }
    }

    func setChargeLimit(_ percent: Int) throws {
        throw PowerBackendError.unsupported
    }

    private static func detectCapabilities(
        using runner: any PMSetCommandRunning
    ) -> (modeKey: String?, capabilities: PowerBackendCapabilities) {
        let unavailable = PowerBackendCapabilities(
            energyModeScopes: [],
            supportedPowerModes: [],
            chargeLimitMinimum: nil,
            chargeLimitMaximum: nil
        )

        guard let capabilitiesOutput = try? runner.run(arguments: ["-g", "cap"]),
              capabilitiesOutput.isSuccessful,
              let capabilityReadout = PMSetPowerModeParser.parseCapabilities(
                  capabilitiesOutput.standardOutput
              ),
              let customOutput = try? runner.run(arguments: ["-g", "custom"]),
              customOutput.isSuccessful,
              let scopedModes = PMSetPowerModeParser.parseScopedModes(
                  customOutput.standardOutput
              ),
              scopedModes.battery.key == scopedModes.adapter.key
        else {
            return (nil, unavailable)
        }

        let modeKey = scopedModes.battery.key
        let supportsLowPower = capabilityReadout.supportsLowPower ||
            modeKey == PMSetPowerModeParser.lowPowerModeKey
        let supportsHighPower = capabilityReadout.supportsHighPower &&
            modeKey == PMSetPowerModeParser.powerModeKey

        var supportedModes = ["automatic"]
        if supportsLowPower {
            supportedModes.append("lowPower")
        }
        if supportsHighPower {
            supportedModes.append("highPower")
        }

        return (
            modeKey,
            PowerBackendCapabilities(
                energyModeScopes: ["battery", "powerAdapter"],
                supportedPowerModes: supportedModes,
                chargeLimitMinimum: nil,
                chargeLimitMaximum: nil
            )
        )
    }
}
