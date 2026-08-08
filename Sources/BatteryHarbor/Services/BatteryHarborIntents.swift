import AppIntents
import Foundation

struct GetBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "获取电池港状态"
    static let description = IntentDescription("返回当前电量、充电状态、温度和功率。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = BatteryReader().read()
        guard snapshot.isPresent else {
            return .result(value: "未检测到电池", dialog: "电池港未检测到内置电池。")
        }
        var parts = ["电量 \(snapshot.percentage)%", snapshot.stateText]
        if let temperature = snapshot.temperatureCelsius {
            parts.append("温度 \(temperature.formatted(.number.precision(.fractionLength(1))))°C")
        }
        if let power = snapshot.powerWatts {
            parts.append("功率 \(power.formatted(.number.precision(.fractionLength(1)))) W")
        }
        let status = parts.joined(separator: "，")
        return .result(value: status, dialog: IntentDialog(stringLiteral: status))
    }
}

struct SetBatteryChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "设置电池港充电上限"
    static let description = IntentDescription("保存并在安全控制可用时应用充电上限。")
    static let openAppWhenRun = false

    @Parameter(title: "充电上限", description: "50 到 100 之间的百分比", inclusiveRange: (50, 100))
    var limit: Int

    init() {
        limit = 80
    }

    init(limit: Int) {
        self.limit = limit
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(limit, forKey: "chargeLimit")
        guard ShortcutControlGate.isConfirmed else {
            return .result(dialog: "已保存 \(limit)% 上限；完成硬件确认测试后才能自动执行。")
        }
        let controller = SystemChargeController()
        guard await controller.availability().isAvailable else {
            return .result(dialog: "已保存 \(limit)% 上限，但控制模块当前不可用。")
        }
        try await controller.setChargeLimit(limit)
        return .result(dialog: "已应用 \(limit)% 充电上限。")
    }
}

struct SetChargingPausedIntent: AppIntent {
    static let title: LocalizedStringResource = "暂停或恢复电池港充电"
    static let description = IntentDescription("保持适配器供电，同时暂停或恢复电池充入。")
    static let openAppWhenRun = false

    @Parameter(title: "暂停充电")
    var paused: Bool

    init() {
        paused = true
    }

    init(paused: Bool) {
        self.paused = paused
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ShortcutControlGate.isConfirmed else {
            return .result(dialog: "尚未完成硬件确认测试，本次没有修改充电状态。")
        }
        let controller = SystemChargeController()
        guard await controller.availability().isAvailable else {
            return .result(dialog: "电池港控制模块当前不可用。")
        }
        try await controller.setChargingPaused(paused)
        return .result(dialog: paused ? "已暂停充电。" : "已恢复充电。")
    }
}

struct TemporaryFullChargeIntent: AppIntent {
    static let title: LocalizedStringResource = "电池港临时充满"
    static let description = IntentDescription("临时恢复充电，后台巡航完成后会恢复原上限。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ShortcutControlGate.isConfirmed else {
            return .result(dialog: "尚未完成硬件确认测试，本次没有修改充电状态。")
        }
        let controller = SystemChargeController()
        guard await controller.availability().isAvailable else {
            return .result(dialog: "电池港控制模块当前不可用。")
        }
        try await controller.temporaryFullCharge()
        return .result(dialog: "已开始临时充满。")
    }
}

struct BatteryHarborShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBatteryStatusIntent(),
            phrases: ["查看 \(.applicationName) 电池状态", "获取 \(.applicationName) 电量"],
            shortTitle: "电池状态",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: SetBatteryChargeLimitIntent(),
            phrases: ["设置 \(.applicationName) 充电上限"],
            shortTitle: "设置充电上限",
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: SetChargingPausedIntent(),
            phrases: ["暂停或恢复 \(.applicationName) 充电"],
            shortTitle: "暂停或恢复充电",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: TemporaryFullChargeIntent(),
            phrases: ["让 \(.applicationName) 临时充满"],
            shortTitle: "临时充满",
            systemImageName: "bolt.fill"
        )
    }
}

private enum ShortcutControlGate {
    static var isConfirmed: Bool {
        UserDefaults.standard.bool(forKey: "hasConfirmedHardwareControlV3")
    }
}
