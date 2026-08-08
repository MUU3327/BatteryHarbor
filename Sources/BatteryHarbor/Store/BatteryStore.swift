import Combine
import AppKit
import Foundation
import ServiceManagement

@MainActor
final class BatteryStore: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot = .unavailable
    @Published private(set) var samples: [PowerSample] = []
    @Published private(set) var controlState: ChargeControlState = .unavailable(reason: "正在检测…")
    @Published private(set) var capabilities: ChargeCapabilities
    @Published private(set) var appEnergyRanking: [AppEnergyUsage] = []
    @Published private(set) var appEnergyHistory: [AppEnergyHistorySample] = []
    @Published private(set) var isEnergyRankingSampling = false
    @Published private(set) var helperRegistrationStatus: HelperRegistrationStatus = .unknown
    @Published private(set) var helperProbe: HelperProbePayload?
    @Published private(set) var helperActionMessage: String?
    @Published private(set) var chargeLimitActionMessage: String?
    @Published private(set) var chargingCommandMessage: String?
    @Published private(set) var historyActionMessage: String?
    @Published private(set) var diagnosticActionMessage: String?
    @Published private(set) var isHelperActionInProgress = false
    @Published private(set) var isHardwareVerificationInProgress = false
    @Published private(set) var isChargingCommandInProgress = false
    @Published private(set) var hardwareVerificationResult: HardwareVerificationPayload?
    @Published var chargeLimit: Double
    @Published var isChargingPaused = false
    @Published var automaticallyDischarges: Bool {
        didSet { UserDefaults.standard.set(automaticallyDischarges, forKey: "automaticallyDischarges") }
    }
    @Published var selectedSection: DashboardSection = .overview
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode") }
    }
    @Published var interfaceLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
            guard interfaceLanguage != oldValue else { return }
            chargeLimitActionMessage = nil
            chargingCommandMessage = nil
            helperActionMessage = nil
            historyActionMessage = nil
            diagnosticActionMessage = nil
            refreshHelperStatus(probeWhenEnabled: true)
        }
    }
    @Published var highTemperatureProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(highTemperatureProtectionEnabled, forKey: "highTemperatureProtectionEnabled") }
    }
    @Published var highTemperatureThreshold: Double {
        didSet { UserDefaults.standard.set(highTemperatureThreshold, forKey: "highTemperatureThreshold") }
    }
    @Published var sleepChargingProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(sleepChargingProtectionEnabled, forKey: "sleepChargingProtectionEnabled") }
    }
    @Published private(set) var isHighTemperatureProtectionActive = false
    @Published private(set) var isSystemSleeping = false
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var hasConfirmedHardwareControl: Bool
    @Published private(set) var schedules: [ChargeSchedule] = []
    @Published private(set) var scheduleLogs: [ScheduleExecutionLog] = []
    @Published private(set) var scheduleBeingEdited: ChargeSchedule?
    @Published private(set) var scheduleEditorSessionID = UUID()
    @Published private(set) var calibrationSession: BatteryCalibrationSession?
    @Published private(set) var temporaryFullChargeUntil: Date?

    private let reader: any BatteryReading
    private let chargeController: any ChargeControlling
    private var samplingTask: Task<Void, Never>?
    private let maximumSamples = 180
    private let energyMonitor = AppEnergyMonitor()
    private let energyHistoryArchive = EnergyHistoryArchive()
    private var energySamplingTask: Task<Void, Never>?
    private var historyLoadTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var sleepProtectionDidPause = false
    private var isPolicyApplying = false
    private var knownChargingEnabled: Bool?
    private var knownForceDischargeEnabled: Bool?
    private static let schedulesDefaultsKey = "chargeSchedulesV1"
    private static let scheduleLogsDefaultsKey = "chargeScheduleLogsV1"
    private static let calibrationDefaultsKey = "batteryCalibrationV1"
    private static let temporaryFullChargeDefaultsKey = "temporaryFullChargeUntil"
    private static let legacyPreferencesMigrationKey = "migratedPreferencesFromComBatteryHarborApp"

    init(
        reader: any BatteryReading = BatteryReader(),
        chargeController: any ChargeControlling = SystemChargeController(),
        capabilityProbe: any HardwareCapabilityProbing = HardwareCapabilityProbe()
    ) {
        self.reader = reader
        self.chargeController = chargeController
        Self.migrateLegacyPreferencesIfNeeded()
        self.capabilities = capabilityProbe.probe()
        let storedLimit = UserDefaults.standard.double(forKey: "chargeLimit")
        self.chargeLimit = storedLimit == 0 ? 80 : storedLimit
        self.automaticallyDischarges = UserDefaults.standard.bool(forKey: "automaticallyDischarges")
        self.menuBarDisplayMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? ""
        ) ?? .percentage
        self.interfaceLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? ""
        ) ?? .system
        self.highTemperatureProtectionEnabled = UserDefaults.standard.object(
            forKey: "highTemperatureProtectionEnabled"
        ) as? Bool ?? true
        let storedTemperatureThreshold = UserDefaults.standard.double(forKey: "highTemperatureThreshold")
        self.highTemperatureThreshold = storedTemperatureThreshold == 0 ? 38 : storedTemperatureThreshold
        self.sleepChargingProtectionEnabled = UserDefaults.standard.object(
            forKey: "sleepChargingProtectionEnabled"
        ) as? Bool ?? true
        self.hasConfirmedHardwareControl = UserDefaults.standard.bool(
            forKey: "hasConfirmedHardwareControlV3"
        )
        if let data = UserDefaults.standard.data(forKey: Self.calibrationDefaultsKey) {
            self.calibrationSession = try? JSONDecoder().decode(BatteryCalibrationSession.self, from: data)
        } else {
            self.calibrationSession = nil
        }
        self.temporaryFullChargeUntil = UserDefaults.standard.object(
            forKey: Self.temporaryFullChargeDefaultsKey
        ) as? Date

        refresh()
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }

        energySamplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.isEnergyRankingSampling = true
                let sampledAt = Date()
                let ranking = await self.energyMonitor.sample()
                self.appEnergyRanking = ranking
                if await self.energyHistoryArchive.record(appUsages: ranking, at: sampledAt) {
                    self.appEnergyHistory.append(AppEnergyHistorySample(timestamp: sampledAt, usages: ranking))
                    let cutoff = sampledAt.addingTimeInterval(-24 * 60 * 60)
                    self.appEnergyHistory.removeAll { $0.timestamp < cutoff }
                }
                self.isEnergyRankingSampling = false
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        historyLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let history = await self.energyHistoryArchive.load()
            let mergedSamples = Dictionary(
                (history.powerSamples + self.samples).map { ($0.id, $0) },
                uniquingKeysWith: { _, newest in newest }
            ).values.sorted { $0.timestamp < $1.timestamp }
            self.samples = Array(
                mergedSamples.suffix(self.maximumSamples)
            )
            self.appEnergyHistory = history.appSamples
        }

        refreshHelperStatus(probeWhenEnabled: true)
        refreshLaunchAtLoginStatus()
        loadSchedules()
        loadScheduleLogs()
        observeWorkspacePowerEvents()
        scheduleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.evaluateSchedules(at: Date())
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyPreferencesMigrationKey) else { return }

        let legacyDomain = defaults.persistentDomain(forName: "com.batteryharbor.app") ?? [:]
        let safeKeys = [
            "chargeLimit",
            "automaticallyDischarges",
            "menuBarDisplayMode",
            "interfaceLanguage",
            "highTemperatureProtectionEnabled",
            "highTemperatureThreshold",
            "sleepChargingProtectionEnabled",
            schedulesDefaultsKey,
            scheduleLogsDefaultsKey
        ]

        for key in safeKeys where defaults.object(forKey: key) == nil {
            if let value = legacyDomain[key] {
                defaults.set(value, forKey: key)
            }
        }

        // A new Bundle ID and Mach service form a new trust boundary. Never
        // carry an old hardware-unlock decision or active calibration command
        // into the migrated app; the new Helper must pass self-test again.
        defaults.set(false, forKey: "hasConfirmedHardwareControlV3")
        defaults.removeObject(forKey: calibrationDefaultsKey)
        defaults.removeObject(forKey: temporaryFullChargeDefaultsKey)
        defaults.set(true, forKey: legacyPreferencesMigrationKey)
    }

    deinit {
        samplingTask?.cancel()
        energySamplingTask?.cancel()
        historyLoadTask?.cancel()
        scheduleTask?.cancel()
    }

    var menuBarTitle: String {
        guard snapshot.isPresent else { return "--" }
        let percentage = "\(snapshot.percentage)%"
        let power = snapshot.powerWatts.map {
            abs($0).formatted(.number.precision(.fractionLength(1))) + " W"
        } ?? "— W"
        switch menuBarDisplayMode {
        case .percentage: return percentage
        case .power: return power
        case .both: return "\(percentage)  \(power)"
        }
    }

    var controlUnavailableReason: String? {
        if case let .unavailable(reason) = controlState { return reason }
        return nil
    }

    var chargeLimitStatusText: String {
        if let chargeLimitActionMessage { return chargeLimitActionMessage }
        return switch controlState {
        case .ready: L10n.text("控制已就绪，拖动后会实际应用到电池")
        case .applying: L10n.text("正在向充电控制模块应用设置…")
        case let .failed(message): L10n.format("应用失败：%@", message)
        case .unavailable: L10n.text("当前仅保存数值，尚未实际限制充电")
        }
    }

    var chargeLimitStatusSymbol: String {
        switch controlState {
        case .ready: "checkmark.shield.fill"
        case .applying: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .unavailable: "lock.fill"
        }
    }

    var isTemporaryFullChargeActive: Bool {
        guard let temporaryFullChargeUntil else { return false }
        return temporaryFullChargeUntil > Date() && snapshot.percentage < 100
    }

    var temporaryFullChargeStatusText: String? {
        guard let deadline = temporaryFullChargeUntil, deadline > Date() else { return nil }
        if snapshot.percentage >= 100 { return L10n.text("已达到 100%，即将恢复原上限") }
        let minutes = max(1, Int(deadline.timeIntervalSinceNow / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0
            ? L10n.format("最长剩余 %lld 小时 %lld 分", hours, remainder)
            : L10n.format("最长剩余 %lld 分钟", remainder)
    }

    func refresh() {
        snapshot = reader.read()
        if let watts = snapshot.powerWatts {
            let sample = PowerSample(timestamp: snapshot.timestamp, watts: watts)
            samples.append(sample)
            if samples.count > maximumSamples {
                samples.removeFirst(samples.count - maximumSamples)
            }
            Task { [energyHistoryArchive] in
                await energyHistoryArchive.record(power: sample)
            }
        }
        evaluateMaintenancePolicy(at: snapshot.timestamp)
    }

    func refreshHelperStatus(probeWhenEnabled: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let status = await chargeController.helperRegistrationStatus()
            helperRegistrationStatus = status
            let detectedState = await chargeController.availability()
            if detectedState.isAvailable, !hasConfirmedHardwareControl {
                controlState = .unavailable(reason: L10n.text("写入后端已就绪，等待写入后立即恢复的人工确认测试"))
            } else {
                controlState = detectedState
            }
            if probeWhenEnabled, status == .enabled {
                await performHelperProbe()
            }
        }
    }

    func registerHelper() {
        performHelperAction(successMessage: L10n.text("控制模块注册请求已提交")) { controller in
            try await controller.registerHelper()
        }
    }

    func unregisterHelper() {
        performHelperAction(successMessage: L10n.text("控制模块已移除")) { controller in
            try await controller.unregisterHelper()
        }
    }

    func probeHelper() {
        Task { [weak self] in
            await self?.performHelperProbe()
        }
    }

    func openHelperApprovalSettings() {
        Task { [chargeController] in
            await chargeController.openApprovalSettings()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginMessage = nil
        } catch {
            launchAtLoginMessage = error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }

    func updateChargeLimit() {
        let rounded = Int(chargeLimit.rounded())
        UserDefaults.standard.set(rounded, forKey: "chargeLimit")
        guard controlState.isAvailable else {
            chargeLimitActionMessage = L10n.format("已保存 %lld%%，但安全控制未就绪，当前不会停止充电", rounded)
            return
        }

        Task {
            do {
                chargeLimitActionMessage = nil
                controlState = .applying
                try await chargeController.setChargeLimit(rounded)
                knownForceDischargeEnabled = false
                if snapshot.percentage >= rounded {
                    knownChargingEnabled = false
                } else if snapshot.percentage <= rounded - 3 {
                    knownChargingEnabled = true
                }
                controlState = .ready
                if snapshot.percentage >= rounded {
                    let reflected = await waitForChargingTelemetry(expectedCharging: false)
                    chargeLimitActionMessage = reflected
                        ? L10n.format("已应用 %lld%% 上限，系统已停止充电", rounded)
                        : L10n.format("已写入 %lld%% 上限，等待 macOS 更新电池状态", rounded)
                } else if snapshot.percentage <= rounded - 3 {
                    let reflected = await waitForChargingTelemetry(expectedCharging: true)
                    chargeLimitActionMessage = reflected
                        ? L10n.format("已应用 %lld%% 上限，系统已恢复充电", rounded)
                        : L10n.text("已允许充电；高电量或系统电池管理可能暂缓补电")
                } else {
                    chargeLimitActionMessage = L10n.format("已应用 %lld%% 上限，当前处于 3%% 回差区间", rounded)
                }
            } catch {
                controlState = .failed(message: error.localizedDescription)
                chargeLimitActionMessage = L10n.format("%lld%% 未能应用：%@", rounded, error.localizedDescription)
            }
        }
    }

    func runHardwareVerification() {
        guard !isHardwareVerificationInProgress else { return }
        guard helperRegistrationStatus == .enabled,
              helperProbe?.isPrivileged == true,
              helperProbe?.writeOperationsEnabled == true
        else {
            helperActionMessage = L10n.text("自检无法开始：请先安装、批准控制模块并完成安全握手")
            return
        }
        isHardwareVerificationInProgress = true
        hardwareVerificationResult = nil
        helperActionMessage = L10n.text("正在执行 CHTE 写入、回读和立即恢复…")
        Task {
            do {
                let result = try await chargeController.verifyHardwareControl()
                hardwareVerificationResult = result
                hasConfirmedHardwareControl = true
                UserDefaults.standard.set(true, forKey: "hasConfirmedHardwareControlV3")
                helperActionMessage = result.message
            } catch {
                hasConfirmedHardwareControl = false
                UserDefaults.standard.set(false, forKey: "hasConfirmedHardwareControlV3")
                helperActionMessage = L10n.format("安全自检失败：%@", error.localizedDescription)
            }
            isHardwareVerificationInProgress = false
            // Refresh the helper's process-scoped verification flag without
            // replacing the self-test result with the generic handshake text.
            await performHelperProbe(updateActionMessage: false)
            refreshHelperStatus(probeWhenEnabled: false)
        }
    }

    func lockHardwareControl() {
        hasConfirmedHardwareControl = false
        UserDefaults.standard.set(false, forKey: "hasConfirmedHardwareControlV3")
        hardwareVerificationResult = nil
        controlState = .unavailable(reason: L10n.text("硬件控制已由用户重新锁定"))
        chargeLimitActionMessage = L10n.text("安全控制已锁定，当前上限仅保存")
    }

    func toggleChargingPaused() {
        setChargingPaused(!isChargingPaused)
    }

    func setChargingPaused(_ intendedState: Bool) {
        guard controlState.isAvailable, !isChargingCommandInProgress else { return }

        isChargingCommandInProgress = true
        chargingCommandMessage = L10n.text(intendedState ? "正在提交暂停充电命令…" : "正在提交恢复充电命令…")
        Task {
            do {
                controlState = .applying
                try await chargeController.setChargingPaused(intendedState)
                isChargingPaused = intendedState
                knownChargingEnabled = !intendedState
                knownForceDischargeEnabled = false
                controlState = .ready
                let reflected = await waitForChargingTelemetry(expectedCharging: !intendedState)
                if intendedState {
                    chargingCommandMessage = reflected
                        ? L10n.text("Helper 写入已确认，macOS 已显示暂停充电")
                        : L10n.text("Helper 已确认暂停；等待 macOS 更新电池状态")
                } else {
                    chargingCommandMessage = reflected
                        ? L10n.text("Helper 写入已确认，macOS 已显示正在充电")
                        : L10n.text("Helper 已允许充电；高电量时 macOS 可能暂缓补电")
                }
            } catch {
                controlState = .failed(message: error.localizedDescription)
                chargingCommandMessage = L10n.format("充电控制失败：%@", error.localizedDescription)
            }
            isChargingCommandInProgress = false
        }
    }

    func temporaryFullCharge() {
        guard controlState.isAvailable, !isChargingCommandInProgress else { return }
        temporaryFullChargeUntil = Date().addingTimeInterval(24 * 60 * 60)
        UserDefaults.standard.set(temporaryFullChargeUntil, forKey: Self.temporaryFullChargeDefaultsKey)
        isChargingPaused = false
        isChargingCommandInProgress = true
        chargingCommandMessage = L10n.text("正在提交临时充满命令…")
        Task {
            do {
                controlState = .applying
                try await chargeController.temporaryFullCharge()
                knownChargingEnabled = true
                knownForceDischargeEnabled = false
                controlState = .ready
                let reflected = await waitForChargingTelemetry(expectedCharging: true)
                chargingCommandMessage = reflected
                    ? L10n.text("临时充满已启用，macOS 已显示正在充电")
                    : L10n.text("Helper 已允许临时充满；高电量时 macOS 可能暂缓补电")
            } catch {
                controlState = .failed(message: error.localizedDescription)
                chargingCommandMessage = L10n.format("临时充满失败：%@", error.localizedDescription)
            }
            isChargingCommandInProgress = false
        }
    }

    func cancelTemporaryFullCharge() {
        temporaryFullChargeUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.temporaryFullChargeDefaultsKey)
        knownChargingEnabled = nil
        knownForceDischargeEnabled = nil
        chargeLimitActionMessage = L10n.format("临时充满已结束，正在恢复 %lld%% 上限", Int(chargeLimit.rounded()))
        chargingCommandMessage = L10n.text("临时充满已结束，正在恢复原上限")
        evaluateMaintenancePolicy(at: Date())
    }

    /// The SMC transaction is already write-verified by the helper. This short
    /// poll only closes the visual gap while macOS publishes the new battery
    /// state through IOPowerSources, which can lag behind the firmware write.
    private func waitForChargingTelemetry(expectedCharging: Bool) async -> Bool {
        for _ in 0..<24 {
            let latestSnapshot = reader.read()
            snapshot = latestSnapshot
            if latestSnapshot.isPresent,
               latestSnapshot.powerSource == .adapter,
               latestSnapshot.isCharging == expectedCharging {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    func exportEnergyHistory() {
        Task {
            let data = await energyHistoryArchive.csvData()
            let panel = NSSavePanel()
            panel.title = L10n.text("导出电池港能耗历史")
            panel.nameFieldStringValue = "BatteryHarbor-EnergyHistory.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                historyActionMessage = L10n.format("能耗历史已导出到 %@", url.lastPathComponent)
            } catch {
                historyActionMessage = L10n.format("导出失败：%@", error.localizedDescription)
            }
        }
    }

    func clearEnergyHistory() {
        Task {
            await energyHistoryArchive.clear()
            samples.removeAll()
            appEnergyHistory.removeAll()
            historyActionMessage = L10n.text("24 小时历史已清除")
        }
    }

    func exportDiagnosticReport() {
        let report = DiagnosticReportBuilder.build(
            snapshot: snapshot,
            capabilities: capabilities,
            controlState: controlState,
            helperStatus: helperRegistrationStatus,
            helperProbe: helperProbe,
            chargeLimit: Int(chargeLimit.rounded()),
            automaticallyDischarges: automaticallyDischarges,
            highTemperatureProtectionEnabled: highTemperatureProtectionEnabled,
            highTemperatureThreshold: highTemperatureThreshold,
            sleepProtectionEnabled: sleepChargingProtectionEnabled,
            scheduleCount: schedules.count,
            recentLogs: scheduleLogs
        )
        let panel = NSSavePanel()
        panel.title = L10n.text("导出电池港诊断报告")
        panel.nameFieldStringValue = "BatteryHarbor-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report.utf8).write(to: url, options: .atomic)
            diagnosticActionMessage = L10n.format("诊断报告已导出到 %@", url.lastPathComponent)
        } catch {
            diagnosticActionMessage = L10n.format("导出失败：%@", error.localizedDescription)
        }
    }

    func startCalibration() {
        guard controlState.isAvailable else { return }
        calibrationSession = BatteryCalibrationSession(
            originalChargeLimit: Int(chargeLimit.rounded())
        )
        isChargingPaused = false
        temporaryFullChargeUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.temporaryFullChargeDefaultsKey)
        knownChargingEnabled = nil
        knownForceDischargeEnabled = nil
        saveCalibration()
        evaluateMaintenancePolicy(at: Date())
    }

    func cancelCalibration() {
        guard var session = calibrationSession, session.isActive else { return }
        session.cancel()
        calibrationSession = session
        saveCalibration()
        applyPolicyActions([.disableForceDischarge])
    }

    func clearCalibrationResult() {
        guard calibrationSession?.isActive != true else { return }
        calibrationSession = nil
        UserDefaults.standard.removeObject(forKey: Self.calibrationDefaultsKey)
    }

    func energyRanking(since cutoff: Date) -> [AppEnergyUsage] {
        EnergyHistoryArchive.aggregate(appEnergyHistory, since: cutoff)
    }

    func beginCreatingSchedule() {
        scheduleBeingEdited = nil
        scheduleEditorSessionID = UUID()
    }

    func beginEditingSchedule(_ schedule: ChargeSchedule) {
        scheduleBeingEdited = schedule
        scheduleEditorSessionID = UUID()
    }

    func saveScheduleFromEditor(_ schedule: ChargeSchedule) {
        if schedules.contains(where: { $0.id == schedule.id }) {
            updateSchedule(schedule)
        } else {
            addSchedule(schedule)
        }
        scheduleBeingEdited = nil
    }

    func cancelScheduleEditing() {
        scheduleBeingEdited = nil
    }

    func addSchedule(_ schedule: ChargeSchedule) {
        schedules.append(schedule)
        schedules.sort { ($0.hour, $0.minute, $0.name) < ($1.hour, $1.minute, $1.name) }
        saveSchedules()
    }

    func deleteSchedule(_ id: UUID) {
        schedules.removeAll { $0.id == id }
        saveSchedules()
    }

    func updateSchedule(_ schedule: ChargeSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
        schedules.sort { ($0.hour, $0.minute, $0.name) < ($1.hour, $1.minute, $1.name) }
        saveSchedules()
    }

    func setScheduleEnabled(_ id: UUID, enabled: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled = enabled
        saveSchedules()
    }

    func clearScheduleLogs() {
        scheduleLogs.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.scheduleLogsDefaultsKey)
    }

    private func performHelperAction(
        successMessage: String,
        operation: @escaping @Sendable (any ChargeControlling) async throws -> Void
    ) {
        guard !isHelperActionInProgress else { return }
        isHelperActionInProgress = true
        helperActionMessage = nil
        Task { [weak self, chargeController] in
            do {
                try await operation(chargeController)
                guard let self else { return }
                helperActionMessage = successMessage
            } catch {
                guard let self else { return }
                helperActionMessage = error.localizedDescription
            }
            guard let self else { return }
            isHelperActionInProgress = false
            refreshHelperStatus(probeWhenEnabled: true)
        }
    }

    private func performHelperProbe(updateActionMessage: Bool = true) async {
        do {
            let probe = try await chargeController.probeHelper()
            helperProbe = probe
            if !probe.hardwareVerificationPassed {
                hasConfirmedHardwareControl = false
                UserDefaults.standard.set(false, forKey: "hasConfirmedHardwareControlV3")
            }
            if updateActionMessage {
                helperActionMessage = L10n.text("安全握手成功")
            }
        } catch {
            helperProbe = nil
            if updateActionMessage {
                helperActionMessage = error.localizedDescription
            }
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func observeWorkspacePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleSystemWillSleep() }
            }
            .store(in: &workspaceCancellables)
        center.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleSystemDidWake() }
            }
            .store(in: &workspaceCancellables)
    }

    private func handleSystemWillSleep() {
        isSystemSleeping = true
        guard sleepChargingProtectionEnabled, controlState.isAvailable else { return }
        sleepProtectionDidPause = true
        applyPolicyActions([.disableForceDischarge, .disableCharging])
    }

    private func handleSystemDidWake() {
        isSystemSleeping = false
        guard sleepProtectionDidPause else { return }
        sleepProtectionDidPause = false
        knownChargingEnabled = nil
        knownForceDischargeEnabled = nil
        evaluateMaintenancePolicy(at: Date())
    }

    private func loadSchedules() {
        guard let data = UserDefaults.standard.data(forKey: Self.schedulesDefaultsKey),
              let decoded = try? JSONDecoder().decode([ChargeSchedule].self, from: data)
        else { return }
        schedules = decoded
    }

    private func saveSchedules() {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: Self.schedulesDefaultsKey)
    }

    private func loadScheduleLogs() {
        guard let data = UserDefaults.standard.data(forKey: Self.scheduleLogsDefaultsKey),
              let decoded = try? JSONDecoder().decode([ScheduleExecutionLog].self, from: data)
        else { return }
        scheduleLogs = decoded
    }

    private func appendScheduleLog(_ log: ScheduleExecutionLog) {
        scheduleLogs.insert(log, at: 0)
        if scheduleLogs.count > 100 { scheduleLogs.removeLast(scheduleLogs.count - 100) }
        if let data = try? JSONEncoder().encode(scheduleLogs) {
            UserDefaults.standard.set(data, forKey: Self.scheduleLogsDefaultsKey)
        }
    }

    private func saveCalibration() {
        guard let calibrationSession,
              let data = try? JSONEncoder().encode(calibrationSession)
        else {
            UserDefaults.standard.removeObject(forKey: Self.calibrationDefaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.calibrationDefaultsKey)
    }

    private func evaluateMaintenancePolicy(at date: Date) {
        guard controlState.isAvailable, !isPolicyApplying, snapshot.isPresent else { return }

        let previousTemperatureProtection = isHighTemperatureProtectionActive
        let temperatureDecision = BatteryTemperatureProtection().decision(
            temperatureCelsius: snapshot.temperatureCelsius,
            threshold: highTemperatureThreshold,
            wasActive: previousTemperatureProtection,
            isEnabled: highTemperatureProtectionEnabled
        )
        isHighTemperatureProtectionActive = temperatureDecision.isActive
        if temperatureDecision.isActive {
            applyPolicyActions(temperatureDecision.actions)
            return
        } else if previousTemperatureProtection {
            knownChargingEnabled = nil
            knownForceDischargeEnabled = nil
        }

        guard !isSystemSleeping else { return }

        if var session = calibrationSession, session.isActive {
            let actions = session.advance(
                percentage: snapshot.percentage,
                isAdapterConnected: snapshot.powerSource == .adapter,
                now: date
            )
            calibrationSession = session
            if session.phase == .completed {
                chargeLimit = Double(session.originalChargeLimit)
                UserDefaults.standard.set(session.originalChargeLimit, forKey: "chargeLimit")
            }
            saveCalibration()
            applyPolicyActions(actions)
            return
        }

        if let deadline = temporaryFullChargeUntil,
           deadline <= date || snapshot.percentage >= 100 {
            temporaryFullChargeUntil = nil
            UserDefaults.standard.removeObject(forKey: Self.temporaryFullChargeDefaultsKey)
        }

        let input = ChargePolicyInput(
            percentage: snapshot.percentage,
            isAdapterConnected: snapshot.powerSource == .adapter,
            isChargingEnabled: knownChargingEnabled ?? snapshot.isCharging,
            isForceDischargeEnabled: knownForceDischargeEnabled,
            upperLimit: Int(chargeLimit.rounded()),
            lowerLimitDelta: 3,
            isPaused: isChargingPaused,
            automaticallyDischarges: automaticallyDischarges,
            temporaryFullChargeUntil: temporaryFullChargeUntil,
            now: date
        )
        applyPolicyActions(ChargePolicy().actions(for: input))
    }

    private func applyPolicyActions(_ actions: [ChargeHardwareAction]) {
        let neededActions = actions.filter { action in
            switch action {
            case .enableCharging: knownChargingEnabled != true
            case .disableCharging: knownChargingEnabled != false
            case .enableForceDischarge: knownForceDischargeEnabled != true
            case .disableForceDischarge: knownForceDischargeEnabled != false
            }
        }
        guard !neededActions.isEmpty, controlState.isAvailable, !isPolicyApplying else { return }
        isPolicyApplying = true
        Task {
            do {
                controlState = .applying
                try await chargeController.applyHardwareActions(neededActions)
                updateKnownHardwareState(after: neededActions)
                controlState = .ready
            } catch {
                controlState = .failed(message: error.localizedDescription)
            }
            isPolicyApplying = false
        }
    }

    private func updateKnownHardwareState(after actions: [ChargeHardwareAction]) {
        for action in actions {
            switch action {
            case .enableCharging: knownChargingEnabled = true
            case .disableCharging: knownChargingEnabled = false
            case .enableForceDischarge: knownForceDischargeEnabled = true
            case .disableForceDischarge: knownForceDischargeEnabled = false
            }
        }
    }

    private func evaluateSchedules(at date: Date) async {
        let dueSchedules = schedules.filter { $0.isDue(at: date) }
        for schedule in dueSchedules {
            guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { continue }
            schedules[index].lastTriggeredAt = date
            guard controlState.isAvailable else {
                schedules[index].lastResult = L10n.text("安全控制未就绪，本次已跳过")
                appendScheduleLog(ScheduleExecutionLog(
                    scheduleID: schedule.id,
                    scheduleName: schedule.name,
                    action: schedule.action,
                    timestamp: date,
                    succeeded: false,
                    message: L10n.text("安全控制未就绪，本次已跳过")
                ))
                continue
            }

            do {
                controlState = .applying
                try await executeScheduledAction(schedule)
                controlState = .ready
                if let currentIndex = schedules.firstIndex(where: { $0.id == schedule.id }) {
                    schedules[currentIndex].lastResult = L10n.format("执行成功 · %@", schedule.timeText)
                }
                appendScheduleLog(ScheduleExecutionLog(
                    scheduleID: schedule.id,
                    scheduleName: schedule.name,
                    action: schedule.action,
                    timestamp: date,
                    succeeded: true,
                    message: L10n.text("执行成功")
                ))
            } catch {
                controlState = .failed(message: error.localizedDescription)
                if let currentIndex = schedules.firstIndex(where: { $0.id == schedule.id }) {
                    schedules[currentIndex].lastResult = L10n.format("执行失败：%@", error.localizedDescription)
                }
                appendScheduleLog(ScheduleExecutionLog(
                    scheduleID: schedule.id,
                    scheduleName: schedule.name,
                    action: schedule.action,
                    timestamp: date,
                    succeeded: false,
                    message: error.localizedDescription
                ))
            }
            saveSchedules()
        }
        if !dueSchedules.isEmpty { saveSchedules() }
    }

    private func executeScheduledAction(_ schedule: ChargeSchedule) async throws {
        switch schedule.action {
        case .applyLimit:
            let limit = schedule.chargeLimit ?? 80
            chargeLimit = Double(limit)
            UserDefaults.standard.set(limit, forKey: "chargeLimit")
            try await chargeController.setChargeLimit(limit)
            knownForceDischargeEnabled = false
            knownChargingEnabled = snapshot.percentage >= limit ? false : nil
        case .pauseCharging:
            try await chargeController.setChargingPaused(true)
            isChargingPaused = true
            knownChargingEnabled = false
            knownForceDischargeEnabled = false
        case .resumeCharging:
            try await chargeController.setChargingPaused(false)
            isChargingPaused = false
            knownChargingEnabled = true
            knownForceDischargeEnabled = false
        case .temporaryFullCharge:
            temporaryFullChargeUntil = Date().addingTimeInterval(24 * 60 * 60)
            UserDefaults.standard.set(temporaryFullChargeUntil, forKey: Self.temporaryFullChargeDefaultsKey)
            isChargingPaused = false
            try await chargeController.temporaryFullCharge()
            knownChargingEnabled = true
            knownForceDischargeEnabled = false
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case power = "功率"
    case apps = "App"
    case automation = "计划"

    var id: Self { self }

    var displayName: String { L10n.text(rawValue) }

    var iconAssetName: String {
        switch self {
        case .overview: "HarborBatteryMark"
        case .power: "HarborPowerMark"
        case .apps: "HarborAppMark"
        case .automation: "HarborScheduleMark"
        }
    }

    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
