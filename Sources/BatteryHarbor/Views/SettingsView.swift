import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: SettingsSection = .general
    @State private var navigationDirection: SettingsNavigationDirection = .forward
    @State private var visibleSection: SettingsSection = .general
    @State private var outgoingSection: SettingsSection?
    @State private var incomingSection: SettingsSection?
    @State private var transitionProgress: CGFloat = 1
    @State private var isSectionTransitioning = false
    @State private var sectionTransitionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            settingsNavigation
            Divider()

            GeometryReader { proxy in
                ZStack {
                    if let outgoingSection, let incomingSection, isSectionTransitioning {
                        settingsContent(outgoingSection)
                            .offset(x: outgoingOffset(width: proxy.size.width))
                            .opacity(1 - transitionProgress)
                        settingsContent(incomingSection)
                            .offset(x: incomingOffset(width: proxy.size.width))
                            .opacity(transitionProgress)
                    } else {
                        settingsContent(visibleSection)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .frame(width: 760, height: 570)
        .background { HarborRootBackground() }
        .onAppear {
            guard !isSectionTransitioning else { return }
            visibleSection = selectedSection
        }
        .onDisappear {
            sectionTransitionTask?.cancel()
            visibleSection = selectedSection
            outgoingSection = nil
            incomingSection = nil
            transitionProgress = 1
            isSectionTransitioning = false
        }
    }

    private var settingsNavigation: some View {
        VStack(spacing: 10) {
            ZStack {
                Text(selectedSection.displayName)
                    .font(.headline)

                HStack {
                    HStack(spacing: 7) {
                        Image("HarborBatteryMark")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(HarborPalette.accent)
                            .frame(width: 17, height: 17)
                        Text("电池港")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Text("技术预览版")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsNavigationItem(
                        section: section,
                        isSelected: selectedSection == section
                    ) {
                        beginSettingsTransition(to: section)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(!isSectionTransitioning)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func settingsContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general: generalSettings
        case .dashboard: dashboardSettings
        case .charging: chargingSettings
        case .automation: automationSettings
        case .advanced: advancedSettings
        case .about: aboutSettings
        }
    }

    private func beginSettingsTransition(to newSection: SettingsSection) {
        guard newSection != selectedSection, !isSectionTransitioning else { return }

        sectionTransitionTask?.cancel()
        navigationDirection = newSection.order > visibleSection.order ? .forward : .backward
        outgoingSection = visibleSection
        incomingSection = newSection
        transitionProgress = 0
        isSectionTransitioning = true
        selectedSection = newSection

        let duration = reduceMotion ? 0.16 : 0.28
        sectionTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.22, 0.78, 0.20, 1, duration: duration)) {
                transitionProgress = 1
            }
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.04) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            visibleSection = newSection
            outgoingSection = nil
            incomingSection = nil
            transitionProgress = 1
            isSectionTransitioning = false
            sectionTransitionTask = nil
        }
    }

    private func outgoingOffset(width: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let direction: CGFloat = navigationDirection == .forward ? -1 : 1
        return direction * width * transitionProgress
    }

    private func incomingOffset(width: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let direction: CGFloat = navigationDirection == .forward ? 1 : -1
        return direction * width * (1 - transitionProgress)
    }

    private var generalSettings: some View {
        settingsForm {
            Section("外观") {
                HStack(spacing: 12) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.title2)
                        .foregroundStyle(HarborPalette.dataBlue)
                        .frame(width: 38, height: 38)
                        .harborGlassCard(cornerRadius: 11)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统 Liquid Glass")
                            .font(.subheadline.weight(.semibold))
                        Text("macOS 26 使用原生 Glass Effect；旧系统自动回退到 Material。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("已启用")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborPalette.success)
                }
            }

            Section("启动") {
                Toggle("登录时启动电池港", isOn: Binding(
                    get: { store.launchesAtLogin },
                    set: { enabled in store.setLaunchAtLogin(enabled) }
                ))
                if let message = store.launchAtLoginMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("语言") {
                Picker("界面语言", selection: $store.interfaceLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Text("界面正文会立即更新；系统窗口标题和快捷指令可能需要重新启动 App 后更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dashboardSettings: some View {
        settingsForm {
            Section("菜单栏实时读数") {
                Picker("显示内容", selection: $store.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .id(store.interfaceLanguage.rawValue)
                menuBarPreview
                Text("更改会立即应用到屏幕顶部的电池港图标和读数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("本机历史数据") {
                LabeledContent("保留范围", value: L10n.text("最近 24 小时"))
                HStack {
                    Button("导出 CSV") { store.exportEnergyHistory() }
                    Button("清除历史", role: .destructive) { store.clearEnergyHistory() }
                }
                if let message = store.historyActionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chargingSettings: some View {
        settingsForm {
            Section("电池") {
                LabeledContent("设计容量", value: capacity(store.snapshot.designCapacityMAh))
                LabeledContent("当前满充容量", value: capacity(store.snapshot.fullChargeCapacityMAh))
                LabeledContent("电压", value: voltsText)
                LabeledContent("电流", value: ampsText)
            }

            Section("充电控制模块") {
                LabeledContent("Helper 状态", value: store.helperRegistrationStatus.localizedDisplayName)
                if let reason = store.controlUnavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                helperActions
                if let probe = store.helperProbe {
                    LabeledContent("连接", value: L10n.text(probe.isPrivileged ? "安全握手成功（root）" : "权限不足"))
                    LabeledContent("协议 / PID", value: "v\(probe.protocolVersion) / \(probe.processIdentifier)")
                    LabeledContent("硬件写入", value: L10n.text(probe.writeOperationsEnabled ? "已启用" : "安全锁定"))
                    LabeledContent("恢复自检", value: L10n.text(probe.hardwareVerificationPassed ? "已通过" : "尚未执行"))
                    if probe.writeOperationsEnabled, !store.hasConfirmedHardwareControl {
                        Label("应用侧仍锁定：需要执行自动写入恢复测试", systemImage: "lock.shield")
                            .foregroundStyle(.orange)
                        Text("自检只会短暂切换 CHTE，随后回读并恢复原值；任何一步失败都不会解锁。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("开始安全自检") {
                            store.runHardwareVerification()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isHardwareVerificationInProgress)
                        if store.isHardwareVerificationInProgress {
                            ProgressView("正在验证并恢复原值…")
                                .controlSize(.small)
                        }
                    } else if store.hasConfirmedHardwareControl {
                        Label("写入、回读和恢复验证已通过", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        if let result = store.hardwareVerificationResult {
                            LabeledContent(
                                "恢复证据",
                                value: "\(result.key) \(result.originalValue) → \(result.temporaryValue) → \(result.restoredValue)"
                            )
                        }
                        Button("重新锁定硬件控制", role: .destructive) {
                            store.lockHardwareControl()
                        }
                    }
                }
                if let message = store.helperActionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("自动保护") {
                Toggle("高温时暂停充电", isOn: $store.highTemperatureProtectionEnabled)
                HStack {
                    Text("高温阈值")
                    Slider(value: $store.highTemperatureThreshold, in: 35...45, step: 1)
                        .disabled(!store.highTemperatureProtectionEnabled)
                    Text("\(Int(store.highTemperatureThreshold))°C")
                        .monospacedDigit()
                        .frame(width: 48)
                }
                Toggle("Mac 睡眠前暂停充电", isOn: $store.sleepChargingProtectionEnabled)
                if store.isHighTemperatureProtectionActive {
                    Label("高温保护正在生效", systemImage: "thermometer.high")
                        .foregroundStyle(.orange)
                }
                Text("温度降至阈值以下 3°C 后解除；唤醒后按当前上限恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var automationSettings: some View {
        settingsForm {
            Section("计划与快捷指令") {
                Label("按时间、接通电源和电量触发养护动作", systemImage: "calendar.badge.clock")
                LabeledContent("计划任务", value: L10n.format("已启用 · %lld 项", store.schedules.count))
                LabeledContent("Apple 快捷指令", value: L10n.text("4 个动作"))
                Text("可在“快捷指令”App 中搜索电池港，查询状态、设置上限、暂停/恢复或临时充满。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSettings: some View {
        settingsForm {
            Section("兼容性") {
                LabeledContent("机型", value: store.capabilities.modelIdentifier)
                LabeledContent("系统固件", value: store.capabilities.firmwareVersion)
                LabeledContent("基础控制", value: store.capabilities.baselineBackend.displayName)
                LabeledContent("系统原生上限", value: store.capabilities.nativeLimitDescription)
                LabeledContent("AppleSMC", value: L10n.text(store.capabilities.hasAppleSMCService ? "已检测到" : "不可用"))
                LabeledContent("充电控制键", value: store.capabilities.smcChargeKeys.chargingPath.displayName)
                LabeledContent("放电控制键", value: store.capabilities.smcChargeKeys.dischargeKey ?? L10n.text("未检测到"))
            }

            Section("诊断") {
                Button("导出诊断报告") { store.exportDiagnosticReport() }
                Text("报告包含机型、电池快照、Helper 状态和最近计划结果，不包含电池序列号或 Apple ID。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = store.diagnosticActionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aboutSettings: some View {
        VStack(spacing: 14) {
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 54))
                .foregroundStyle(.blue, .green)
            Text("电池港").font(.title.bold())
            Text("从零实现的原生 macOS 电池养护工具").foregroundStyle(.secondary)
            Text("硬件控制需通过签名 Helper 和人工确认测试。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var menuBarPreview: some View {
        HStack(spacing: 8) {
            Text("菜单栏预览")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HarborMenuBarBatteryIcon(
                batterySymbol: store.menuBarBatterySymbol,
                accessorySymbol: store.menuBarAccessorySymbol
            )
            .foregroundStyle(menuPreviewColor)
            Text(store.menuBarTitle)
                .font(.caption.monospacedDigit())
                .foregroundStyle(menuPreviewColor)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 9))
    }

    private var menuPreviewColor: Color {
        .white
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }

    private func capacity(_ value: Int?) -> String {
        value.map { "\($0) mAh" } ?? "—"
    }

    private var voltsText: String {
        store.snapshot.voltageVolts.map { $0.formatted(.number.precision(.fractionLength(2))) + " V" } ?? "—"
    }

    private var ampsText: String {
        store.snapshot.currentAmps.map { $0.formatted(.number.precision(.fractionLength(2))) + " A" } ?? "—"
    }

    @ViewBuilder
    private var helperActions: some View {
        HStack {
            switch store.helperRegistrationStatus {
            case .notRegistered:
                Button("安装控制模块") { store.registerHelper() }
            case .requiresApproval:
                Button("打开登录项设置") { store.openHelperApprovalSettings() }
                Button("刷新") { store.refreshHelperStatus(probeWhenEnabled: true) }
            case .enabled:
                Button("测试连接") { store.probeHelper() }
                Button("更新模块") { store.registerHelper() }
                Button("移除模块", role: .destructive) { store.unregisterHelper() }
            case .notFound:
                Button("尝试注册控制模块") { store.registerHelper() }
                Button("重新检测") { store.refreshHelperStatus(probeWhenEnabled: true) }
            case .unknown:
                Button("重新检测") { store.refreshHelperStatus(probeWhenEnabled: true) }
            }
            if store.isHelperActionInProgress { ProgressView().controlSize(.small) }
        }
    }
}

private struct SettingsNavigationItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                navigationIcon
                    .frame(width: 25, height: 25)
                Text(section.shortTitle)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? HarborPalette.accent : Color.secondary)
            .frame(width: 82, height: 54)
            .background {
                if isSelected {
                    Color.clear
                        .harborGlassCard(
                            cornerRadius: 13,
                            tint: HarborPalette.accent.opacity(0.18),
                            interactive: true
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .settingsNavigationFocusStyle()
        .help(section.displayName)
    }

    @ViewBuilder
    private var navigationIcon: some View {
        if let assetName = section.iconAssetName {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        } else if let symbolName = section.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .regular))
        }
    }
}

private enum SettingsNavigationDirection {
    case forward
    case backward
}

private extension View {
    @ViewBuilder
    func settingsNavigationFocusStyle() -> some View {
        if #available(macOS 14.0, *) {
            // Keep the button keyboard-focusable while suppressing the large
            // system halo that can look like a second selected tab.
            focusEffectDisabled()
        } else {
            self
        }
    }
}

private extension SettingsSection {
    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var shortTitle: String {
        switch self {
        case .general: L10n.text("通用")
        case .dashboard: L10n.text("仪表盘")
        case .charging: L10n.text("充电")
        case .automation: L10n.text("计划")
        case .advanced: L10n.text("高级")
        case .about: L10n.text("关于")
        }
    }

    var iconAssetName: String? {
        switch self {
        case .general: "HarborBatteryMark"
        case .dashboard: "HarborPowerMark"
        case .charging: "HarborPlugMark"
        case .automation: "HarborScheduleMark"
        case .advanced, .about: nil
        }
    }

    var symbolName: String? {
        switch self {
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        default: nil
        }
    }
}

private extension HelperRegistrationStatus {
    var localizedDisplayName: String {
        switch self {
        case .enabled: L10n.text("已启用")
        case .requiresApproval: L10n.text("等待管理员批准")
        case .notRegistered: L10n.text("尚未安装")
        case .notFound: L10n.text("系统尚未识别模块")
        case .unknown: L10n.text("状态未知")
        }
    }
}
