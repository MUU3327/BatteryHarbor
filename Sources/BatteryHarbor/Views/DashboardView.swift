import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var visibleSection: DashboardSection = .overview
    @State private var outgoingSection: DashboardSection?
    @State private var incomingSection: DashboardSection?
    @State private var transitionProgress: CGFloat = 1
    @State private var isSectionTransitioning = false
    @State private var sectionTransitionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("页面", selection: sectionSelection) {
                ForEach(DashboardSection.allCases) { section in
                    Label(section.displayName, image: section.iconAssetName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .id(store.interfaceLanguage.rawValue)
            .labelsHidden()
            .accessibilityLabel("页面")
            .disabled(isSectionTransitioning)
            .padding(3)
            .harborGlassCard(
                cornerRadius: 10,
                tint: HarborPalette.accent.opacity(0.12),
                interactive: true
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    if let outgoingSection, let incomingSection, isSectionTransitioning {
                        sectionContent(outgoingSection)
                            .offset(x: outgoingOffset(width: proxy.size.width))
                            .opacity(1 - transitionProgress)
                        sectionContent(incomingSection)
                            .offset(x: incomingOffset(width: proxy.size.width))
                            .opacity(transitionProgress)
                    } else {
                        sectionContent(visibleSection)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            .environmentObject(store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            footer
        }
        .frame(width: 390, height: 540)
        .background { HarborRootBackground() }
        .onAppear {
            guard !isSectionTransitioning else { return }
            visibleSection = store.selectedSection
        }
        .onDisappear {
            sectionTransitionTask?.cancel()
            visibleSection = store.selectedSection
            outgoingSection = nil
            incomingSection = nil
            transitionProgress = 1
            isSectionTransitioning = false
        }
    }

    private var sectionSelection: Binding<DashboardSection> {
        Binding(
            get: { store.selectedSection },
            set: { newSection in
                beginSectionTransition(to: newSection)
            }
        )
    }

    @ViewBuilder
    private func sectionContent(_ section: DashboardSection) -> some View {
        switch section {
        case .overview: OverviewView()
        case .power: PowerChartView()
        case .apps: AppEnergyRankingView()
        case .automation: AutomationView()
        }
    }

    private func beginSectionTransition(to newSection: DashboardSection) {
        guard newSection != store.selectedSection, !isSectionTransitioning else { return }

        sectionTransitionTask?.cancel()
        navigationDirection = circularDirection(from: visibleSection, to: newSection)
        outgoingSection = visibleSection
        incomingSection = newSection
        transitionProgress = 0
        isSectionTransitioning = true
        store.selectedSection = newSection

        let duration = reduceMotion ? 0.16 : 0.28
        sectionTransitionTask = Task { @MainActor in
            // Give SwiftUI one render pass with progress at zero so the
            // animation cannot be coalesced with the initial state change.
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

    private func circularDirection(
        from current: DashboardSection,
        to target: DashboardSection
    ) -> NavigationDirection {
        let count = DashboardSection.allCases.count
        let forwardDistance = (target.order - current.order + count) % count
        let backwardDistance = (current.order - target.order + count) % count
        return forwardDistance <= backwardDistance ? .forward : .backward
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

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(HarborPalette.accent.opacity(0.13), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.025, Double(store.snapshot.percentage) / 100))
                    .stroke(
                        HarborPalette.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image("HarborBatteryMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(HarborPalette.accent)
                    .frame(width: 25, height: 25)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.snapshot.percentage)%")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(store.snapshot.stateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let watts = store.snapshot.powerWatts {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(abs(watts).formatted(.number.precision(.fractionLength(1))) + " W")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(L10n.text(watts >= 0 ? "流入电池" : "电池输出"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button {
                showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")

            Spacer()
            Text("电池港 · 技术预览版")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background {
            ZStack {
                Rectangle().fill(.thinMaterial)
                Color(nsColor: .controlBackgroundColor).opacity(0.36)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }

    private func showSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")

        Task { @MainActor in
            // `openWindow` only guarantees scene creation. Menu-bar apps have
            // no Dock activation path, so an existing window can otherwise
            // remain behind the previously active application or on another
            // Space. Retry briefly while SwiftUI creates or restores it.
            for _ in 0..<12 {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.identifier == HarborWindowIdentifier.settings
                }) {
                    window.hidesOnDeactivate = false
                    window.collectionBehavior.insert(.moveToActiveSpace)
                    window.deminiaturize(nil)
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

private enum NavigationDirection {
    case forward
    case backward
}

private struct OverviewView: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                chargeLimitCard
                controls
                metrics
                Button {
                    openWindow(id: "battery-details")
                } label: {
                    Label("查看电池详情", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .harborGlassButtonStyle()
                if let reason = store.controlUnavailableReason {
                    Label(reason, systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .harborGlassCard(cornerRadius: 12, tint: .orange.opacity(0.08))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var chargeLimitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(chargeStatusIconAsset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(chargeStatusTint)
                    .padding(9)
                    .frame(width: 38, height: 38)
                    .background(chargeStatusTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(chargeStatusTitle)
                        .font(.headline)
                    Text(adapterElectricalText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(chargeTargetHeadline)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(chargeStatusTint)
                    Text(chargeTargetCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(store.snapshot.percentage)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(chargeStatusTint)
                    Text("实时电量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(chargeTargetLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            ChargeLimitGradientSlider(
                value: $store.chargeLimit,
                range: 50...100,
                step: 5,
                onCommit: store.updateChargeLimit
            )

            HStack {
                Text("50%")
                Spacer()
                Text("拖动标记调整充电上限")
                Spacer()
                Text("100%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                chargeMetric(title: L10n.text("输入"), value: powerText(store.snapshot.adapterInputWatts), tint: HarborPalette.warning)
                chargeMetric(title: L10n.text("系统"), value: powerText(store.snapshot.systemLoadWatts), tint: HarborPalette.dataBlue)
                chargeMetric(
                    title: L10n.text((store.snapshot.powerWatts ?? 0) < 0 ? "电池输出" : "充入电池"),
                    value: powerText(store.snapshot.powerWatts.map(abs)),
                    tint: (store.snapshot.powerWatts ?? 0) < 0 ? HarborPalette.warning : HarborPalette.success
                )
            }

            Label(chargeTargetStatusText, systemImage: chargeTargetStatusSymbol)
                .font(.caption)
                .foregroundStyle(store.controlState.isAvailable ? HarborPalette.success : HarborPalette.warning)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("超出上限时自动放电", isOn: $store.automaticallyDischarges)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(14)
        .harborGlassCard(cornerRadius: 18)
    }

    private var regularChargeLimit: Int {
        Int(store.chargeLimit.rounded())
    }

    private var chargeTargetHeadline: String {
        store.isTemporaryFullChargeActive
            ? L10n.text("临时目标 100%")
            : L10n.format("上限 %lld%%", regularChargeLimit)
    }

    private var chargeTargetCaption: String {
        if store.isTemporaryFullChargeActive {
            return L10n.format("常规上限 %lld%%", regularChargeLimit)
        }
        return L10n.text(store.snapshot.powerSource == .adapter ? "适配器已连接" : "电池供电")
    }

    private var chargeTargetLabel: String {
        store.isTemporaryFullChargeActive
            ? L10n.text("临时目标 100%")
            : L10n.format("目标 %lld%%", regularChargeLimit)
    }

    private var chargeTargetStatusText: String {
        guard store.isTemporaryFullChargeActive else { return store.chargeLimitStatusText }
        return L10n.format("临时充满已启用，结束后恢复 %lld%% 上限", regularChargeLimit)
    }

    private var chargeTargetStatusSymbol: String {
        store.isTemporaryFullChargeActive ? "bolt.badge.checkmark.fill" : store.chargeLimitStatusSymbol
    }

    private var chargeStatusTitle: String {
        if store.snapshot.powerSource != .adapter { return L10n.text("电池供电中") }
        if store.isTemporaryFullChargeActive { return L10n.text("临时充满中") }
        if store.isChargingPaused { return L10n.text("充电已暂停") }
        if store.snapshot.isCharging { return L10n.text("正在充电") }
        if store.snapshot.percentage >= Int(store.chargeLimit.rounded()) {
            return L10n.text("已达到充电上限")
        }
        return L10n.text("已接电源，未充电")
    }

    private var chargeStatusIconAsset: String {
        store.snapshot.powerSource == .adapter ? "HarborPlugMark" : "HarborBatteryMark"
    }

    private var chargeStatusTint: Color {
        if store.snapshot.powerSource != .adapter { return HarborPalette.dataBlue }
        if store.isTemporaryFullChargeActive { return HarborPalette.success }
        if store.isChargingPaused { return HarborPalette.warning }
        if store.snapshot.isCharging { return HarborPalette.success }
        return HarborPalette.accent
    }

    private var adapterElectricalText: String {
        guard store.snapshot.powerSource == .adapter else {
            return L10n.text("当前未连接电源适配器")
        }
        let voltage = store.snapshot.adapterVoltageVolts.map {
            $0.formatted(.number.precision(.fractionLength(2))) + " V"
        }
        let current = store.snapshot.adapterCurrentAmps.map {
            abs($0).formatted(.number.precision(.fractionLength(2))) + " A"
        }
        let input = store.snapshot.adapterInputWatts.map {
            abs($0).formatted(.number.precision(.fractionLength(2))) + " W"
        }
        let electrical = [voltage, current].compactMap { $0 }.joined(separator: " @ ")
        return [electrical.isEmpty ? nil : electrical, input].compactMap { $0 }.joined(separator: " · ")
    }

    private func chargeMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .harborGlassCard(cornerRadius: 10)
    }

    private func powerText(_ value: Double?) -> String {
        value.map { abs($0).formatted(.number.precision(.fractionLength(2))) + " W" } ?? "— W"
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                ControlButton(
                    title: L10n.text(store.isChargingPaused ? "恢复充电" : "暂停充电"),
                    symbol: store.isChargingPaused ? "play.fill" : "pause.fill",
                    tint: HarborPalette.warning,
                    enabled: store.controlState.isAvailable && !store.isChargingCommandInProgress,
                    action: store.toggleChargingPaused
                )
                ControlButton(
                    title: L10n.text(store.isTemporaryFullChargeActive ? "结束临时充满" : "临时充满"),
                    symbol: store.isTemporaryFullChargeActive ? "xmark.circle.fill" : "bolt.fill",
                    tint: store.isTemporaryFullChargeActive ? HarborPalette.danger : HarborPalette.success,
                    enabled: store.controlState.isAvailable && !store.isChargingCommandInProgress,
                    action: store.isTemporaryFullChargeActive
                        ? store.cancelTemporaryFullCharge
                        : store.temporaryFullCharge
                )
            }
            if let text = store.temporaryFullChargeStatusText {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            if let message = store.chargingCommandMessage {
                HStack(spacing: 6) {
                    if store.isChargingCommandInProgress {
                        ProgressView().controlSize(.small)
                    }
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
            MetricTile(title: L10n.text("电池温度"), value: temperatureText, symbol: "thermometer.medium", tint: HarborPalette.warning)
            MetricTile(title: L10n.text("电池健康"), value: healthText, symbol: "heart.fill", tint: HarborPalette.danger)
            MetricTile(title: L10n.text("循环次数"), value: store.snapshot.cycleCount.map(String.init) ?? "—", symbol: "arrow.triangle.2.circlepath", tint: HarborPalette.accent)
            MetricTile(title: L10n.text("预计时间"), value: store.snapshot.timeRemainingText ?? L10n.text("计算中"), symbol: "clock.fill", tint: HarborPalette.dataBlue)
        }
    }

    private var temperatureText: String {
        store.snapshot.temperatureCelsius.map { $0.formatted(.number.precision(.fractionLength(1))) + "°C" } ?? "—"
    }

    private var healthText: String {
        store.snapshot.healthPercentage.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—"
    }
}

private struct ChargeLimitGradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: () -> Void

    private let thumbDiameter: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - thumbDiameter, 1)
            let progress = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let thumbX = thumbDiameter / 2 + trackWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 9)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [HarborPalette.dataBlue, HarborPalette.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(trackWidth * progress, 1), height: 9)
                    .padding(.leading, thumbDiameter / 2)

                HStack(spacing: 0) {
                    ForEach(0...10, id: \.self) { index in
                        Rectangle()
                            .fill(.white.opacity(index == 0 || index == 10 ? 0 : 0.38))
                            .frame(width: 1, height: 4)
                        if index < 10 { Spacer() }
                    }
                }
                .padding(.horizontal, thumbDiameter / 2 + 2)
                .allowsHitTesting(false)

                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: 26)
                    .position(x: thumbX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay {
                        Circle().stroke(HarborPalette.accent.opacity(0.62), lineWidth: 2)
                    }
                    .shadow(color: HarborPalette.accent.opacity(0.22), radius: 5)
                    .position(x: thumbX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: proxy.size.width)
                    }
                    .onEnded { gesture in
                        updateValue(at: gesture.location.x, width: proxy.size.width)
                        onCommit()
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("充电上限")
        .accessibilityValue("\(Int(value.rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(range.upperBound, value + step)
                onCommit()
            case .decrement:
                value = max(range.lowerBound, value - step)
                onCommit()
            @unknown default:
                break
            }
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        let usableWidth = max(width - thumbDiameter, 1)
        let progress = min(max((x - thumbDiameter / 2) / usableWidth, 0), 1)
        let rawValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
        value = min(range.upperBound, max(range.lowerBound, (rawValue / step).rounded() * step))
    }
}

private struct ControlButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? tint : .secondary)
                    .frame(width: 34, height: 30)
                    .background(
                        (enabled ? tint : Color.secondary).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .harborGlassCard(cornerRadius: 14, interactive: true)
            // Keep hit testing aligned with the complete card instead of only
            // the visible icon and text inside the plain button label.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!enabled)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .harborGlassCard(cornerRadius: 12)
    }
}

enum HarborPalette {
    // Teal carries the brand, blue carries data, and warm colors are reserved
    // for state changes rather than being used as large surface fills.
    static let accent = Color(red: 0.035, green: 0.50, blue: 0.46)
    static let dataBlue = Color(red: 0.15, green: 0.42, blue: 0.76)
    static let success = Color(red: 0.10, green: 0.60, blue: 0.36)
    static let warning = Color(red: 0.86, green: 0.49, blue: 0.16)
    static let danger = Color(red: 0.78, green: 0.25, blue: 0.28)
}

struct HarborRootBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                HarborBackdropView()
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.22 : 0.14)
            }
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.16),
                    .clear,
                    HarborPalette.accent.opacity(colorScheme == .dark ? 0.045 : 0.035),
                    HarborPalette.dataBlue.opacity(colorScheme == .dark ? 0.035 : 0.024)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.025 : 0.13),
                    .clear
                ],
                center: .topLeading,
                startRadius: 4,
                endRadius: 330
            )
        }
        .ignoresSafeArea()
    }
}

private struct HarborBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = HarborBackdropVisualEffectView(frame: .zero)
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.alphaValue = 0.82
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.alphaValue = 0.82
    }
}

private final class HarborBackdropVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}

extension View {
    @ViewBuilder
    func harborGlassCard(
        cornerRadius: CGFloat = 14,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            HarborGlassCardModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
            )
        )
    }

    @ViewBuilder
    func harborGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    func cardStyle() -> some View {
        padding(14)
            .harborGlassCard(cornerRadius: 16)
    }
}

private struct HarborGlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .background {
                    shape.fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.36 : 0.30)
                    )
                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.12 : 0.09))
                    }
                }
                .glassEffect(
                    .regular.tint(tint?.opacity(0.40)).interactive(interactive),
                    in: shape
                )
                .overlay { lacqueredSurface(for: shape) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 5, y: 2)
        } else {
            content
                .background {
                    shape.fill(
                        reduceTransparency
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.82 : 0.88)
                    )
                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.11 : 0.07))
                    }
                }
                .overlay { lacqueredSurface(for: shape) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.09), radius: 3, y: 1)
        }
    }

    private func lacqueredSurface(
        for shape: RoundedRectangle
    ) -> some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.055 : 0.20),
                            .clear,
                            Color.black.opacity(colorScheme == .dark ? 0.025 : 0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.18), lineWidth: 1)
            shape
                .inset(by: 1)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.44),
                            Color.white.opacity(colorScheme == .dark ? 0.025 : 0.10),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
            if interactive {
                shape
                    .inset(by: 0.5)
                    .stroke(HarborPalette.accent.opacity(0.10), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}
