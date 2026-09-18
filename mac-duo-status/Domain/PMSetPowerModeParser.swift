//
//  PMSetPowerModeParser.swift
//  mac-duo-status
//

import Foundation

struct PMSetModeReadout: Equatable, Sendable {
    let key: String
    let value: Int
}

struct PMSetScopedModeReadout: Equatable, Sendable {
    let battery: PMSetModeReadout
    let adapter: PMSetModeReadout
}

struct PMSetCapabilityReadout: Equatable, Sendable {
    let supportsLowPower: Bool
    let supportsHighPower: Bool
}

enum PMSetPowerModeParser {
    static let powerModeKey = "powermode"
    static let lowPowerModeKey = "lowpowermode"
    private static let capabilityHeaders = [
        "Capabilities for Battery Power:",
        "Capabilities for AC Power:"
    ]

    static func parseCapabilities(_ output: String) -> PMSetCapabilityReadout? {
        let lines = normalizedLines(from: output)
        var hasCapabilitiesHeader = false
        var lowPower = false
        var highPower = false

        for line in lines {
            if capabilityHeaders.contains(line) {
                guard !hasCapabilitiesHeader else {
                    return nil
                }

                hasCapabilitiesHeader = true
                continue
            }

            guard hasCapabilitiesHeader else {
                continue
            }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let firstToken = tokens.first else {
                continue
            }

            switch firstToken {
            case Substring(lowPowerModeKey):
                guard tokens.count == 1 else {
                    return nil
                }
                lowPower = true
            case Substring("highpowermode"):
                guard tokens.count == 1 else {
                    return nil
                }
                highPower = true
            default:
                continue
            }
        }

        guard hasCapabilitiesHeader else {
            return nil
        }

        return PMSetCapabilityReadout(
            supportsLowPower: lowPower || highPower,
            supportsHighPower: highPower
        )
    }

    static func parseScopedModes(_ output: String) -> PMSetScopedModeReadout? {
        enum Section {
            case battery
            case adapter
        }

        let lines = normalizedLines(from: output)
        var currentSection: Section?
        var hasBatterySection = false
        var hasAdapterSection = false
        var batteryMode: PMSetModeReadout?
        var adapterMode: PMSetModeReadout?

        for line in lines {
            switch line {
            case "Battery Power:":
                guard !hasBatterySection else {
                    return nil
                }

                hasBatterySection = true
                currentSection = .battery
                continue
            case "AC Power:":
                guard !hasAdapterSection else {
                    return nil
                }

                hasAdapterSection = true
                currentSection = .adapter
                continue
            default:
                break
            }

            guard let firstToken = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
                  let currentSection
            else {
                continue
            }

            let key = String(firstToken)
            guard key == powerModeKey || key == lowPowerModeKey else {
                continue
            }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count == 2,
                  let value = Int(tokens[1]),
                  isValid(value: value, for: key)
            else {
                return nil
            }

            let readout = PMSetModeReadout(key: key, value: value)
            switch currentSection {
            case .battery:
                guard batteryMode == nil else {
                    return nil
                }
                batteryMode = readout
            case .adapter:
                guard adapterMode == nil else {
                    return nil
                }
                adapterMode = readout
            }
        }

        guard hasBatterySection,
              hasAdapterSection,
              let batteryMode,
              let adapterMode
        else {
            return nil
        }

        return PMSetScopedModeReadout(
            battery: batteryMode,
            adapter: adapterMode
        )
    }

    static func parseActiveMode(_ output: String) -> PMSetModeReadout? {
        let lines = normalizedLines(from: output)
        guard lines.contains("Currently in use:") else {
            return nil
        }

        var readout: PMSetModeReadout?
        for line in lines {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let firstToken = tokens.first else {
                continue
            }

            let key = String(firstToken)
            guard key == powerModeKey || key == lowPowerModeKey else {
                continue
            }

            guard tokens.count == 2,
                  let value = Int(tokens[1]),
                  isValid(value: value, for: key),
                  readout == nil
            else {
                return nil
            }

            readout = PMSetModeReadout(key: key, value: value)
        }

        return readout
    }

    static func modeName(for readout: PMSetModeReadout) -> String? {
        switch (readout.key, readout.value) {
        case (powerModeKey, 0), (lowPowerModeKey, 0):
            return "automatic"
        case (powerModeKey, 1), (lowPowerModeKey, 1):
            return "lowPower"
        case (powerModeKey, 2):
            return "highPower"
        default:
            return nil
        }
    }

    static func value(for mode: String, key: String) -> Int? {
        switch (key, mode) {
        case (powerModeKey, "automatic"), (lowPowerModeKey, "automatic"):
            return 0
        case (powerModeKey, "lowPower"), (lowPowerModeKey, "lowPower"):
            return 1
        case (powerModeKey, "highPower"):
            return 2
        default:
            return nil
        }
    }

    private static func normalizedLines(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isValid(value: Int, for key: String) -> Bool {
        switch key {
        case powerModeKey:
            return (0...2).contains(value)
        case lowPowerModeKey:
            return (0...1).contains(value)
        default:
            return false
        }
    }
}
