import Foundation

struct BatterySnapshot: Equatable, Sendable {
    enum PowerSource: String, Sendable {
        case battery
        case adapter
        case unknown

        var displayName: String {
            switch self {
            case .battery: L10n.text("电池供电")
            case .adapter: L10n.text("电源适配器")
            case .unknown: L10n.text("未知电源")
            }
        }
    }

    var timestamp = Date()
    var percentage = 0
    var isCharging = false
    var isFullyCharged = false
    var isPresent = false
    var powerSource: PowerSource = .unknown
    var timeRemainingMinutes: Int?
    var temperatureCelsius: Double?
    var voltageVolts: Double?
    var currentAmps: Double?
    var powerWatts: Double?
    var adapterInputWatts: Double?
    var adapterVoltageVolts: Double?
    var adapterCurrentAmps: Double?
    var systemLoadWatts: Double?
    var adapterEfficiencyLossWatts: Double?
    var adapterRatedWatts: Int?
    var cycleCount: Int?
    var designCapacityMAh: Int?
    var fullChargeCapacityMAh: Int?
    var remainingCapacityMAh: Int?
    var healthPercentage: Double?

    static let unavailable = BatterySnapshot()

    var menuBarSymbol: String {
        if !isPresent { return "battery.0percent.slash" }
        if isCharging { return "battery.100percent.bolt" }

        switch percentage {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 10...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var stateText: String {
        if !isPresent { return L10n.text("未检测到电池") }
        if isFullyCharged { return L10n.text("已充满") }
        if isCharging { return L10n.text("正在充电") }
        return powerSource == .adapter
            ? L10n.text("已接电源，未充电")
            : L10n.text("正在放电")
    }

    var timeRemainingText: String? {
        guard let minutes = timeRemainingMinutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0
            ? L10n.format("约 %lld 小时 %lld 分钟", hours, remainder)
            : L10n.format("约 %lld 分钟", remainder)
    }

    var powerBalanceText: String? {
        guard let adapterInputWatts, let systemLoadWatts, let powerWatts else { return nil }
        let difference = adapterInputWatts - systemLoadWatts - max(powerWatts, 0)
        return L10n.format("平衡误差 %@ W", abs(difference).formatted(.number.precision(.fractionLength(2))))
    }
}

struct PowerSample: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let watts: Double

    init(id: UUID = UUID(), timestamp: Date, watts: Double) {
        self.id = id
        self.timestamp = timestamp
        self.watts = watts
    }
}
