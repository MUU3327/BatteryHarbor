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

    /// A native SF Symbol that approximates the current level without implying
    /// a full battery merely because charging is active. The exact percentage
    /// remains in the adjacent menu-bar text because SF Symbols only provides
    /// quarter-level battery glyphs.
    var nativeBatteryLevelSymbol: String {
        guard isPresent else { return "battery.0percent.slash" }
        switch percentage {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

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

enum AdapterConnectionState: Equatable, Sendable {
    case unavailable
    case disconnected
    case connected

    var displayName: String {
        switch self {
        case .unavailable: L10n.text("不可用")
        case .disconnected: L10n.text("未连接")
        case .connected: L10n.text("已连接")
        }
    }

    var symbol: String {
        switch self {
        case .unavailable: "questionmark.circle"
        case .disconnected: "powerplug"
        case .connected: "powerplug.fill"
        }
    }
}

enum PowerNegotiationState: Equatable, Sendable {
    case notApplicable
    case waiting
    case established

    var displayName: String {
        switch self {
        case .notApplicable: L10n.text("不适用")
        case .waiting: L10n.text("等待参数")
        case .established: L10n.text("已建立")
        }
    }

    var symbol: String {
        switch self {
        case .notApplicable: "minus"
        case .waiting: "ellipsis"
        case .established: "checkmark"
        }
    }
}

enum SystemSupplyState: Equatable, Sendable {
    case unknown
    case battery
    case adapter
    case transitioning

    var displayName: String {
        switch self {
        case .unknown: L10n.text("未知")
        case .battery: L10n.text("电池供电")
        case .adapter: L10n.text("适配器供电")
        case .transitioning: L10n.text("正在切换")
        }
    }

    var symbol: String {
        switch self {
        case .unknown: "questionmark"
        case .battery: "battery.75percent"
        case .adapter: "powerplug.fill"
        case .transitioning: "arrow.triangle.2.circlepath"
        }
    }
}

enum BatteryFlowState: Equatable, Sendable {
    case unavailable
    case discharging
    case charging
    case temporaryCharging
    case pausedManually
    case pausedForTemperature
    case pausedForSleep
    case reachedLimit
    case hysteresisHold
    case forceDischarging
    case heldBySystem
    case dischargingOnAdapter

    var displayName: String {
        switch self {
        case .unavailable: L10n.text("不可用")
        case .discharging: L10n.text("正在放电")
        case .charging: L10n.text("正在充电")
        case .temporaryCharging: L10n.text("临时充满中")
        case .pausedManually: L10n.text("手动暂停")
        case .pausedForTemperature: L10n.text("高温保护")
        case .pausedForSleep: L10n.text("睡眠保护")
        case .reachedLimit: L10n.text("达到上限")
        case .hysteresisHold: L10n.text("回差保持")
        case .forceDischarging: L10n.text("自动放电")
        case .heldBySystem: L10n.text("系统暂缓")
        case .dischargingOnAdapter: L10n.text("外接电源下放电")
        }
    }

    var symbol: String {
        switch self {
        case .unavailable: "questionmark.circle"
        case .discharging: "arrow.down"
        case .charging, .temporaryCharging: "bolt.fill"
        case .pausedManually, .pausedForTemperature, .pausedForSleep,
             .reachedLimit, .hysteresisHold, .heldBySystem: "pause.fill"
        case .forceDischarging, .dischargingOnAdapter: "arrow.down"
        }
    }

    var menuBarAccessorySymbol: String? {
        switch self {
        // Charging uses SF Symbols' native battery-with-bolt glyph as the
        // primary icon. Keeping the bolt inside the battery is both clearer
        // and closer to macOS than drawing a tiny badge outside the icon.
        case .charging, .temporaryCharging: nil
        case .pausedManually, .pausedForTemperature, .pausedForSleep,
             .reachedLimit, .hysteresisHold, .heldBySystem: "pause.fill"
        case .forceDischarging, .dischargingOnAdapter: "arrow.down"
        case .unavailable: "exclamationmark"
        case .discharging: nil
        }
    }

    func menuBarBatterySymbol(levelSymbol: String) -> String {
        switch self {
        case .charging, .temporaryCharging:
            "battery.100percent.bolt"
        default:
            levelSymbol
        }
    }
}

enum ChargingDiagnosticLevel: Equatable, Sendable {
    case normal
    case informational
    case warning
}

struct BatteryChargingDiagnostic: Equatable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    let level: ChargingDiagnosticLevel
}

struct ChargingPathStatus: Equatable, Sendable {
    let connection: AdapterConnectionState
    let negotiation: PowerNegotiationState
    let systemSupply: SystemSupplyState
    let batteryFlow: BatteryFlowState
    let diagnostic: BatteryChargingDiagnostic
}

enum ChargingStateAnalyzer {
    static func status(
        snapshot: BatterySnapshot,
        targetLimit: Int,
        chargingAllowed: Bool?,
        forceDischargeEnabled: Bool?,
        isManuallyPaused: Bool,
        isTemporaryFullChargeActive: Bool,
        isTemperatureProtectionActive: Bool,
        isSystemSleeping: Bool,
        isControlAvailable: Bool
    ) -> ChargingPathStatus {
        guard snapshot.isPresent else {
            return ChargingPathStatus(
                connection: .unavailable,
                negotiation: .notApplicable,
                systemSupply: .unknown,
                batteryFlow: .unavailable,
                diagnostic: BatteryChargingDiagnostic(
                    title: L10n.text("未检测到电池"),
                    detail: L10n.text("当前无法读取电池与充电链路状态。"),
                    symbol: "exclamationmark.triangle.fill",
                    level: .warning
                )
            )
        }

        let adapterConnected = snapshot.powerSource == .adapter
        let effectiveLimit = isTemporaryFullChargeActive ? 100 : min(max(targetLimit, 50), 100)
        let lowerLimit = max(5, effectiveLimit - 3)
        let batteryPower = snapshot.powerWatts ?? 0
        let batteryIsCharging = snapshot.isCharging || batteryPower > 0.8
        let hasAdapterParameters = (snapshot.adapterRatedWatts ?? 0) > 0
            || (snapshot.adapterVoltageVolts ?? 0) > 4
            || (snapshot.adapterInputWatts ?? 0) > 0.5

        let negotiation: PowerNegotiationState = adapterConnected
            ? (hasAdapterParameters ? .established : .waiting)
            : .notApplicable
        let systemSupply: SystemSupplyState
        if !adapterConnected {
            systemSupply = .battery
        } else if hasAdapterParameters || snapshot.systemLoadWatts != nil {
            systemSupply = .adapter
        } else {
            systemSupply = .transitioning
        }

        let flow: BatteryFlowState
        if !adapterConnected {
            flow = .discharging
        } else if isTemperatureProtectionActive {
            flow = .pausedForTemperature
        } else if isSystemSleeping {
            flow = .pausedForSleep
        } else if isManuallyPaused {
            flow = .pausedManually
        } else if forceDischargeEnabled == true {
            flow = .forceDischarging
        } else if batteryIsCharging {
            flow = isTemporaryFullChargeActive ? .temporaryCharging : .charging
        } else if snapshot.percentage >= effectiveLimit {
            flow = .reachedLimit
        } else if chargingAllowed == false, snapshot.percentage > lowerLimit {
            flow = .hysteresisHold
        } else if batteryPower < -0.8 {
            flow = .dischargingOnAdapter
        } else {
            flow = .heldBySystem
        }

        return ChargingPathStatus(
            connection: adapterConnected ? .connected : .disconnected,
            negotiation: negotiation,
            systemSupply: systemSupply,
            batteryFlow: flow,
            diagnostic: diagnostic(
                snapshot: snapshot,
                flow: flow,
                targetLimit: effectiveLimit,
                lowerLimit: lowerLimit,
                hasAdapterParameters: hasAdapterParameters,
                isControlAvailable: isControlAvailable
            )
        )
    }

    private static func diagnostic(
        snapshot: BatterySnapshot,
        flow: BatteryFlowState,
        targetLimit: Int,
        lowerLimit: Int,
        hasAdapterParameters: Bool,
        isControlAvailable: Bool
    ) -> BatteryChargingDiagnostic {
        let batteryWatts = abs(snapshot.powerWatts ?? 0)
            .formatted(.number.precision(.fractionLength(1)))

        switch flow {
        case .unavailable:
            return BatteryChargingDiagnostic(
                title: L10n.text("充电状态不可用"),
                detail: L10n.text("当前无法读取电池与充电链路状态。"),
                symbol: "exclamationmark.triangle.fill",
                level: .warning
            )
        case .discharging:
            return BatteryChargingDiagnostic(
                title: L10n.text("当前由电池供电"),
                detail: L10n.text("未检测到外接电源，电池正在为系统供电。"),
                symbol: "battery.75percent",
                level: .informational
            )
        case .pausedManually:
            return BatteryChargingDiagnostic(
                title: L10n.text("充电已手动暂停"),
                detail: L10n.text("适配器继续为系统供电，电池暂不接受充电。"),
                symbol: "pause.circle.fill",
                level: .informational
            )
        case .pausedForTemperature:
            return BatteryChargingDiagnostic(
                title: L10n.text("高温保护已暂停充电"),
                detail: L10n.text("电池温度达到保护条件，降温后将按当前上限恢复。"),
                symbol: "thermometer.high",
                level: .warning
            )
        case .pausedForSleep:
            return BatteryChargingDiagnostic(
                title: L10n.text("睡眠保护已暂停充电"),
                detail: L10n.text("Mac 唤醒后将重新评估当前充电上限。"),
                symbol: "moon.zzz.fill",
                level: .informational
            )
        case .reachedLimit:
            return BatteryChargingDiagnostic(
                title: L10n.text("已达到充电上限"),
                detail: L10n.format("适配器正为系统供电，电池保持在 %lld%% 上限附近。", targetLimit),
                symbol: "checkmark.circle.fill",
                level: .normal
            )
        case .hysteresisHold:
            return BatteryChargingDiagnostic(
                title: L10n.text("正在避免频繁启停"),
                detail: L10n.format("充电将在电量降至 %lld%% 时恢复。", lowerLimit),
                symbol: "arrow.left.and.right.circle.fill",
                level: .normal
            )
        case .forceDischarging:
            return BatteryChargingDiagnostic(
                title: L10n.text("正在自动放电至上限"),
                detail: L10n.format("适配器仍连接，电池当前输出 %@ W。", batteryWatts),
                symbol: "arrow.down.circle.fill",
                level: .informational
            )
        case .temporaryCharging:
            return BatteryChargingDiagnostic(
                title: L10n.text("正在临时充满"),
                detail: L10n.format("当前充入电池 %@ W，完成后恢复常规上限。", batteryWatts),
                symbol: "bolt.circle.fill",
                level: .normal
            )
        case .charging:
            let ratedWatts = snapshot.adapterRatedWatts ?? 0
            let lowChargingPower = ratedWatts >= 30
                && snapshot.percentage < targetLimit - 10
                && batteryWattsValue(snapshot) < max(4, Double(ratedWatts) * 0.12)
            if lowChargingPower {
                return BatteryChargingDiagnostic(
                    title: L10n.text("当前充电功率偏低"),
                    detail: L10n.format(
                        "适配器额定 %lld W，当前充入电池 %@ W；可能由线材、温度、系统负载或 macOS 策略限制。",
                        ratedWatts,
                        batteryWatts
                    ),
                    symbol: "exclamationmark.triangle.fill",
                    level: .warning
                )
            }
            return BatteryChargingDiagnostic(
                title: L10n.text("正在正常充电"),
                detail: L10n.format("当前充入电池 %@ W；接近目标电量时功率下降属于正常现象。", batteryWatts),
                symbol: "bolt.circle.fill",
                level: .normal
            )
        case .heldBySystem:
            if !hasAdapterParameters {
                return BatteryChargingDiagnostic(
                    title: L10n.text("正在识别外接电源"),
                    detail: L10n.text("已连接适配器，正在等待 macOS 发布供电参数。"),
                    symbol: "arrow.triangle.2.circlepath",
                    level: .informational
                )
            }
            return BatteryChargingDiagnostic(
                title: L10n.text(isControlAvailable ? "macOS 暂缓充电" : "当前未进行硬件控制"),
                detail: L10n.text("适配器正在为系统供电，电池当前未接受充电；高电量或系统电池管理可能暂缓补电。"),
                symbol: "pause.circle.fill",
                level: .informational
            )
        case .dischargingOnAdapter:
            return BatteryChargingDiagnostic(
                title: L10n.text("外接电源尚未完全接管系统"),
                detail: L10n.format("电池仍在输出 %@ W，请检查适配器、线材或供电协商状态。", batteryWatts),
                symbol: "exclamationmark.triangle.fill",
                level: .warning
            )
        }
    }

    private static func batteryWattsValue(_ snapshot: BatterySnapshot) -> Double {
        max(snapshot.powerWatts ?? 0, 0)
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
