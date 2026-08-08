import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        #if SWIFT_PACKAGE
        guard resolvedLanguageIdentifier == "en" else { return key }
        return packageEnglishStrings[key] ?? key
        #else
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
        #endif
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: activeLocale, arguments: arguments)
    }

    private static var selectedLanguage: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: "interfaceLanguage"),
              let language = AppLanguage(rawValue: rawValue)
        else { return .system }
        return language
    }

    private static var activeLocale: Locale {
        selectedLanguage.locale
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static var localizedBundle: Bundle {
        guard let path = resourceBundle.path(
            forResource: resolvedLanguageIdentifier,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return resourceBundle
        }
        return bundle
    }

    private static var resolvedLanguageIdentifier: String {
        if let selectedIdentifier = selectedLanguage.localizationIdentifier {
            return selectedIdentifier
        }
        return Bundle.preferredLocalizations(
            from: ["zh-Hans", "en"],
            forPreferences: Locale.preferredLanguages
        ).first ?? "zh-Hans"
    }

    #if SWIFT_PACKAGE
    private static let packageEnglishStrings: [String: String] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [:] }

        return strings.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? [String: Any],
                  let localizations = value["localizations"] as? [String: Any],
                  let english = localizations["en"] as? [String: Any],
                  let stringUnit = english["stringUnit"] as? [String: Any],
                  let translation = stringUnit["value"] as? String
            else { return }
            result[entry.key] = translation
        }
    }()
    #endif
}
