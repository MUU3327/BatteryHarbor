import Foundation

enum BatteryCalibrationPhase: String, Codable, Equatable, Sendable {
    case chargingToFull
    case restingAtFull
    case dischargingToLow
    case chargingToFullAgain
    case completed
    case cancelled

    var title: String {
        switch self {
        case .chargingToFull: L10n.text("第一阶段：充至 100%")
        case .restingAtFull: L10n.text("第二阶段：满电静置")
        case .dischargingToLow: L10n.text("第三阶段：放电至 10%")
        case .chargingToFullAgain: L10n.text("第四阶段：重新充满")
        case .completed: L10n.text("校准已完成")
        case .cancelled: L10n.text("校准已取消")
        }
    }

    var symbol: String {
        switch self {
        case .chargingToFull, .chargingToFullAgain: "bolt.fill"
        case .restingAtFull: "pause.circle.fill"
        case .dischargingToLow: "arrow.down.circle.fill"
        case .completed: "checkmark.seal.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .chargingToFull, .restingAtFull, .dischargingToLow, .chargingToFullAgain: true
        case .completed, .cancelled: false
        }
    }
}

struct BatteryCalibrationSession: Codable, Equatable, Sendable {
    var phase: BatteryCalibrationPhase
    let startedAt: Date
    var phaseStartedAt: Date
    let originalChargeLimit: Int
    var message: String

    init(startedAt: Date = Date(), originalChargeLimit: Int) {
        self.phase = .chargingToFull
        self.startedAt = startedAt
        self.phaseStartedAt = startedAt
        self.originalChargeLimit = min(max(originalChargeLimit, 50), 100)
        self.message = L10n.text("请连接电源，电池港将先把电池充至 100%。")
    }

    var isActive: Bool { phase.isActive }

    var progress: Double {
        switch phase {
        case .chargingToFull: 0.125
        case .restingAtFull: 0.375
        case .dischargingToLow: 0.625
        case .chargingToFullAgain: 0.875
        case .completed: 1
        case .cancelled: 0
        }
    }

    mutating func advance(
        percentage: Int,
        isAdapterConnected: Bool,
        now: Date,
        fullRestDuration: TimeInterval = 3_600
    ) -> [ChargeHardwareAction] {
        guard phase.isActive else { return [] }

        switch phase {
        case .chargingToFull:
            guard isAdapterConnected else {
                message = L10n.text("等待连接电源后继续充至 100%。")
                return [.disableForceDischarge]
            }
            if percentage >= 100 {
                move(to: .restingAtFull, at: now)
                message = L10n.text("已满电，保持接电并静置 1 小时。")
                return [.disableForceDischarge, .disableCharging]
            }
            message = L10n.format("正在充至 100%%，当前 %lld%%。", percentage)
            return [.disableForceDischarge, .enableCharging]

        case .restingAtFull:
            guard isAdapterConnected else {
                message = L10n.text("静置阶段需要连接电源，请重新接入。")
                return [.disableForceDischarge]
            }
            let remaining = max(0, fullRestDuration - now.timeIntervalSince(phaseStartedAt))
            if remaining <= 0 {
                move(to: .dischargingToLow, at: now)
                message = L10n.text("正在使用强制放电降低至 10%。")
                return [.disableCharging, .enableForceDischarge]
            }
            message = L10n.format("满电静置中，还需约 %lld 分钟。", Int(ceil(remaining / 60)))
            return [.disableForceDischarge, .disableCharging]

        case .dischargingToLow:
            guard isAdapterConnected else {
                message = L10n.text("请连接电源；校准放电由适配器供电状态下安全执行。")
                return [.disableForceDischarge]
            }
            if percentage <= 10 {
                move(to: .chargingToFullAgain, at: now)
                message = L10n.format("已降至 %lld%%，开始最后一次完整充电。", percentage)
                return [.disableForceDischarge, .enableCharging]
            }
            message = L10n.format("正在放电至 10%%，当前 %lld%%。", percentage)
            return [.disableCharging, .enableForceDischarge]

        case .chargingToFullAgain:
            guard isAdapterConnected else {
                message = L10n.text("等待连接电源以完成最后一次充电。")
                return [.disableForceDischarge]
            }
            if percentage >= 100 {
                move(to: .completed, at: now)
                message = L10n.text("完整充放电循环已完成，正在恢复原充电上限。")
                return originalChargeLimit < 100
                    ? [.disableForceDischarge, .disableCharging]
                    : [.disableForceDischarge, .enableCharging]
            }
            message = L10n.format("最后一次充电中，当前 %lld%%。", percentage)
            return [.disableForceDischarge, .enableCharging]

        case .completed, .cancelled:
            return []
        }
    }

    mutating func cancel(at date: Date = Date()) {
        move(to: .cancelled, at: date)
        message = L10n.text("已停止校准并恢复常规充电策略。")
    }

    private mutating func move(to newPhase: BatteryCalibrationPhase, at date: Date) {
        phase = newPhase
        phaseStartedAt = date
    }
}
