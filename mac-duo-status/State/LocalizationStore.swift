//
//  LocalizationStore.swift
//  mac-duo-status
//

import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        default:
            return rawValue
        }
    }

    var displayNameKey: String? {
        switch self {
        case .system:
            return "language.system"
        default:
            return nil
        }
    }
}

@MainActor
final class LocalizationStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }

    private let defaults: UserDefaults
    private let mainBundle: Bundle

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.defaults = defaults
        self.mainBundle = bundle
        self.language = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var locale: Locale {
        guard let localeIdentifier = language.localeIdentifier else {
            return .current
        }

        return Locale(identifier: localeIdentifier)
    }

    func string(_ key: String) -> String {
        let selectedBundle = bundle(for: language)

        if let localizedValue = value(for: key, in: selectedBundle) {
            return localizedValue
        }

        let fallbackBundle = englishBundle
        if selectedBundle.bundlePath != fallbackBundle.bundlePath,
           let fallbackValue = value(for: key, in: fallbackBundle) {
            return fallbackValue
        }

        return key
    }

    func displayName(for language: AppLanguage) -> String {
        guard let displayNameKey = language.displayNameKey else {
            return language.nativeName
        }

        return string(displayNameKey)
    }

    private func bundle(for language: AppLanguage) -> Bundle {
        guard let localeIdentifier = language.localeIdentifier,
              let path = mainBundle.path(
                  forResource: localeIdentifier,
                  ofType: "lproj"
              ),
              let localizedBundle = Bundle(path: path)
        else {
            return englishBundle
        }

        return localizedBundle
    }

    private var englishBundle: Bundle {
        guard let path = mainBundle.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return mainBundle
        }

        return bundle
    }

    private func value(for key: String, in bundle: Bundle) -> String? {
        let value = bundle.localizedString(
            forKey: key,
            value: nil,
            table: "Localizable"
        )

        return value == key ? nil : value
    }

    private enum Keys {
        static let language = "appLanguage"
    }
}
