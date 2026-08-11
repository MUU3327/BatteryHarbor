import Foundation

enum DiagnosticReportBuilder {
    static func build(
        generatedAt: Date = Date(),
        snapshot: BatterySnapshot,
        capabilities: ChargeCapabilities,
        controlState: ChargeControlState,
        helperStatus: HelperRegistrationStatus,
        helperProbe: HelperProbePayload?,
        chargeLimit: Int,
        highTemperatureProtectionEnabled: Bool,
        highTemperatureThreshold: Double,
        sleepProtectionEnabled: Bool,
        scheduleCount: Int,
        recentLogs: [ScheduleExecutionLog]
    ) -> String {
        let date = ISO8601DateFormatter().string(from: generatedAt)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let probeText = helperProbe.map {
            "root=\($0.isPrivileged), writes=\($0.writeOperationsEnabled), restoreTest=\($0.hardwareVerificationPassed), protocol=\($0.protocolVersion), pid=\($0.processIdentifier)"
        } ?? "无"
        let logs = recentLogs.prefix(10).map {
            "- \(ISO8601DateFormatter().string(from: $0.timestamp)) | \($0.scheduleName) | \($0.succeeded ? "成功" : "失败") | \($0.message)"
        }.joined(separator: "\n")

        return """
        电池港诊断报告
        生成时间: \(date)
        App 版本: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本")
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "Swift Package")
        系统: \(os)

        [硬件]
        机型: \(capabilities.modelIdentifier)
        固件: \(capabilities.firmwareVersion)
        Apple Silicon: \(capabilities.isAppleSilicon)
        AppleSMC: \(capabilities.hasAppleSMCService)
        控制后端: \(capabilities.baselineBackend.displayName)
        充电键: \(capabilities.smcChargeKeys.chargingPath.displayName)
        放电键: \(capabilities.smcChargeKeys.dischargeKey ?? "无")

        [电池快照]
        电量: \(snapshot.percentage)%
        状态: \(snapshot.stateText)
        电源: \(snapshot.powerSource.displayName)
        温度: \(value(snapshot.temperatureCelsius)) °C
        电池功率: \(signedPowerText(snapshot.powerWatts, fractionLength: 2))
        适配器输入: \(value(snapshot.adapterInputWatts)) W
        适配器电压: \(value(snapshot.adapterVoltageVolts)) V
        适配器电流: \(value(snapshot.adapterCurrentAmps)) A
        系统使用: \(value(snapshot.systemLoadWatts)) W
        健康度: \(value(snapshot.healthPercentage))%
        循环: \(snapshot.cycleCount.map(String.init) ?? "—")

        [控制]
        状态: \(controlStateText(controlState))
        Helper: \(helperStatus.displayName)
        Helper 探测: \(probeText)
        上限: \(chargeLimit)%
        高温保护: \(highTemperatureProtectionEnabled), 阈值 \(Int(highTemperatureThreshold))°C
        睡眠保护: \(sleepProtectionEnabled)
        计划数量: \(scheduleCount)

        [最近计划日志]
        \(logs.isEmpty ? "无" : logs)

        注：报告不包含电池序列号、用户文件内容或 Apple ID。
        """
    }

    private static func value(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }

    private static func controlStateText(_ state: ChargeControlState) -> String {
        switch state {
        case .ready: "就绪"
        case .applying: "正在应用"
        case let .failed(message): "失败：\(message)"
        case let .unavailable(reason): "不可用：\(reason)"
        }
    }
}
