import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case english

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }

    var displayName: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case percentage = "实时电量"
    case power = "实时功率"
    case both = "电量与功率"

    var id: Self { self }

    var displayName: String { L10n.text(rawValue) }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case dashboard = "仪表盘"
    case charging = "充电管理"
    case automation = "计划与自动化"
    case advanced = "高级"
    case about = "关于"

    var id: Self { self }

    var displayName: String { L10n.text(rawValue) }
}
