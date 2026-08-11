import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var selectedSection: DashboardSection = .overview
    @State private var visibleSection: DashboardSection = .overview
    @State private var outgoingSection: DashboardSection?
    @State private var incomingSection: DashboardSection?
    @State private var transitionProgress: CGFloat = 1
    @State private var isSectionTransitioning = false
    @State private var sectionTransitionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            DashboardSectionPicker(
                selection: selectedSection,
                isDisabled: isSectionTransitioning,
                onSelect: beginSectionTransition
            )

            ZStack(alignment: .top) {
                if let outgoingSection, let incomingSection, isSectionTransitioning {
                    sectionContent(outgoingSection)
                        .offset(x: outgoingOffset(width: Self.dashboardWidth))
                        .opacity(1 - transitionProgress)
                    sectionContent(incomingSection)
                        .offset(x: incomingOffset(width: Self.dashboardWidth))
                        .opacity(transitionProgress)
                } else {
                    sectionContent(visibleSection)
                }
            }
            .frame(
                width: Self.dashboardWidth,
                height: Self.contentHeight,
                alignment: .top
            )
            .clipped()

            Divider()
            footer
        }
        .frame(
            width: Self.dashboardWidth,
            height: Self.dashboardHeight,
            alignment: .top
        )
        .background { HarborRootBackground() }
        .onDisappear {
            sectionTransitionTask?.cancel()
            outgoingSection = nil
            incomingSection = nil
            transitionProgress = 1
            isSectionTransitioning = false
        }
    }

    private static let dashboardWidth: CGFloat = 390
    // Keep the menu close to the compact Alpha 1 footprint. Every section
    // scrolls inside this stable viewport instead of growing the menu window.
    private static let dashboardHeight: CGFloat = 550
    // The standalone brand row was removed, so its 48 points now belong to
    // the content viewport without increasing the overall menu height.
    private static let contentHeight: CGFloat = 467

    @ViewBuilder
    private func sectionContent(_ section: DashboardSection) -> some View {
        switch section {
        case .overview: TextFirstOverviewView()
        case .power:
            ScrollView {
                PowerChartView()
                    .padding(.top, 12)
            }
        case .apps:
            ScrollView {
                AppEnergyRankingView()
                    .padding(.top, 12)
            }
        case .automation:
            ScrollView {
                AutomationView()
                    .padding(.top, 12)
            }
        }
    }

    private func beginSectionTransition(to newSection: DashboardSection) {
        guard newSection != visibleSection, !isSectionTransitioning else { return }

        sectionTransitionTask?.cancel()
        navigationDirection = circularDirection(from: visibleSection, to: newSection)
        outgoingSection = visibleSection
        incomingSection = newSection
        transitionProgress = 0
        isSectionTransitioning = true
        selectedSection = newSection

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
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .medium))
                Text("Battery Harbor")
                    .font(.caption2)
            }
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
            Color(nsColor: .controlBackgroundColor).opacity(0.22)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
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

private struct DashboardSectionPicker: View {
    @EnvironmentObject private var store: BatteryStore

    let selection: DashboardSection
    let isDisabled: Bool
    let onSelect: (DashboardSection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    store.selectedSection = section
                    onSelect(section)
                } label: {
                    Text(section.displayName)
                        .font(.subheadline.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(selection == section ? .primary : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == section ? HarborPalette.dataBlue : .clear)
                                .frame(height: 2)
                                .padding(.horizontal, 10)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .id(store.interfaceLanguage.rawValue)
        .accessibilityLabel("页面")
        .padding(.horizontal, 16)
        .frame(height: 43)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.horizontal, 16)
        }
    }
}

private enum NavigationDirection {
    case forward
    case backward
}

private struct TextFirstOverviewView: View {
    @EnvironmentObject private var store: BatteryStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                chargeControl
                actionGroup
                commandMessages
                sectionDivider
                powerFlow
                sectionDivider
                currentState
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 10)
    }

    private var chargeControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("充电控制")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .bottom) {
                compactValue(title: "当前电量", value: "\(store.snapshot.percentage)%")
                Spacer()
                Divider()
                    .frame(height: 34)
                    .padding(.trailing, 12)
                compactValue(
                    title: store.isTemporaryFullChargeActive ? "临时目标" : "充电上限",
                    value: store.isTemporaryFullChargeActive ? "100%" : "\(regularChargeLimit)%"
                )
            }

            TextFirstChargeLimitSlider(
                value: $store.chargeLimit,
                range: 50...100,
                step: 5,
                onCommit: store.updateChargeLimit
            )

            HStack {
                Text("50%")
                Spacer()
                Text("\(regularChargeLimit)%")
                    .foregroundStyle(.primary)
                Spacer()
                Text("100%")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            Label(chargeStatusText, systemImage: chargeStatusSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(store.controlState.isAvailable ? HarborPalette.success : HarborPalette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compactValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L10n.text(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium).monospacedDigit())
        }
    }

    private var powerFlow: some View {
        let input = max(store.snapshot.adapterInputWatts ?? 0, 0)
        let system = max(store.snapshot.systemLoadWatts ?? 0, 0)
        let battery = store.snapshot.powerWatts ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("功率流向")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 0) {
                powerMetric(title: "输入", value: input, symbol: "powerplug")
                Divider().frame(height: 54)
                powerMetric(title: "系统", value: system, symbol: "laptopcomputer")
                Divider().frame(height: 54)
                powerMetric(
                    title: "电池",
                    value: battery,
                    symbol: nativeBatterySymbol,
                    usesSignedValue: true
                )
            }
        }
    }

    private func powerMetric(
        title: String,
        value: Double,
        symbol: String,
        usesSignedValue: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(L10n.text(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .frame(height: 19)
            Text(
                usesSignedValue
                    ? signedPowerText(value, fractionLength: 1)
                    : value.formatted(.number.precision(.fractionLength(1))) + " W"
            )
                .font(.subheadline.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var nativeBatterySymbol: String {
        store.snapshot.menuBarSymbol
    }

    private var currentState: some View {
        let status = store.chargingPathStatus

        return VStack(alignment: .leading, spacing: 8) {
            Text("当前状态")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 5) {
                stateText(status.connection.displayName)
                stateArrow
                stateText(status.negotiation.displayName)
                stateArrow
                stateText(status.systemSupply.displayName)
                stateArrow
                stateText(status.batteryFlow.displayName, highlighted: true)
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: status.diagnostic.symbol)
                    .foregroundStyle(diagnosticTint)
                    .frame(width: 16)
                Text(status.diagnostic.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stateText(_ value: String, highlighted: Bool = false) -> some View {
        Text(value)
            .font(.caption.weight(highlighted ? .semibold : .regular))
            .foregroundStyle(highlighted ? diagnosticTint : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(maxWidth: .infinity)
    }

    private var stateArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var actionGroup: some View {
        HStack(spacing: 10) {
            actionButton(
                title: L10n.text(store.isChargingPaused ? "恢复充电" : "暂停充电"),
                subtitle: L10n.text(store.isChargingPaused ? "重新允许电池充电" : "停止向电池充电"),
                symbol: store.isChargingPaused ? "play.fill" : "pause.fill",
                tint: HarborPalette.dataBlue,
                action: store.toggleChargingPaused
            )

            actionButton(
                title: L10n.text(store.isTemporaryFullChargeActive ? "结束临时充满" : "临时充满"),
                subtitle: L10n.text(store.isTemporaryFullChargeActive ? "恢复常规充电上限" : "临时调整到 100%"),
                symbol: store.isTemporaryFullChargeActive ? "xmark" : "bolt.fill",
                tint: store.isTemporaryFullChargeActive ? HarborPalette.danger : HarborPalette.dataBlue,
                action: store.isTemporaryFullChargeActive
                    ? store.cancelTemporaryFullCharge
                    : store.temporaryFullCharge
            )
        }
        .padding(.top, 12)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle().stroke(tint.opacity(0.72), lineWidth: 1)
                        }
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.28),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!store.controlState.isAvailable || store.isChargingCommandInProgress)
    }

    @ViewBuilder
    private var commandMessages: some View {
        if let text = store.temporaryFullChargeStatusText {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
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
            .padding(.top, 6)
        }
        if let reason = store.controlUnavailableReason {
            Label(reason, systemImage: "wrench.and.screwdriver")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
    }

    private var regularChargeLimit: Int {
        Int(store.chargeLimit.rounded())
    }

    private var chargeStatusText: String {
        guard store.isTemporaryFullChargeActive else { return store.chargeLimitStatusText }
        return L10n.format("临时充满已启用，结束后恢复 %lld%% 上限", regularChargeLimit)
    }

    private var chargeStatusSymbol: String {
        store.isTemporaryFullChargeActive ? "bolt.badge.checkmark.fill" : store.chargeLimitStatusSymbol
    }

    private var diagnosticTint: Color {
        switch store.chargingPathStatus.diagnostic.level {
        case .normal: HarborPalette.success
        case .informational: HarborPalette.dataBlue
        case .warning: HarborPalette.warning
        }
    }
}

private struct TextFirstChargeLimitSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: () -> Void

    private let thumbDiameter: CGFloat = 30
    private let particlePositions: [(CGFloat, CGFloat)] = [
        (0.07, 0.34), (0.12, 0.62), (0.19, 0.42), (0.28, 0.68),
        (0.36, 0.29), (0.43, 0.57), (0.52, 0.37), (0.59, 0.69),
        (0.67, 0.28), (0.74, 0.55), (0.81, 0.36)
    ]

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - thumbDiameter, 1)
            let progress = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let thumbX = thumbDiameter / 2 + trackWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 24)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.93, green: 0.96, blue: 0.99),
                                Color(red: 0.62, green: 0.76, blue: 0.94),
                                HarborPalette.dataBlue,
                                Color(red: 0.05, green: 0.24, blue: 0.52)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(trackWidth * progress, 1), height: 24)
                    .padding(.leading, thumbDiameter / 2)

                ForEach(Array(particlePositions.enumerated()), id: \.offset) { index, position in
                    let particleColor = colorScheme == .dark || position.0 > 0.38
                        ? Color.white
                        : Color(red: 0.30, green: 0.46, blue: 0.67)
                    Circle()
                        .fill(particleColor.opacity(index.isMultiple(of: 3) ? 0.90 : 0.58))
                        .frame(width: index.isMultiple(of: 4) ? 2.5 : 1.6)
                        .position(
                            x: thumbDiameter / 2 + trackWidth * position.0,
                            y: 8 + 14 * position.1
                        )
                        .opacity(position.0 <= progress ? 1 : 0)
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.52) : Color.white.opacity(0.94))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.92 : 0.72), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 5, y: 2)
                    .position(x: thumbX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)
            }
            .animation(
                reduceMotion
                    ? nil
                    : .timingCurve(0.22, 0.74, 0.20, 1, duration: 0.20),
                value: progress
            )
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
        .frame(height: 34)
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

private struct OverviewView: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            primaryControlCard

            ScrollView {
                LazyVStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                        Text("更多充电详情")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    chargeLimitDetailCard
                    powerAllocationCard
                    currentStateCard

                    if let reason = store.controlUnavailableReason {
                        Label(reason, systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .harborGlassCard(cornerRadius: 12, tint: .orange.opacity(0.08))
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.visible)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var primaryControlCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("充电控制")
                        .font(.headline)
                    Text(store.chargingPathStatus.batteryFlow.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                compactValue(
                    title: "当前电量",
                    value: "\(store.snapshot.percentage)%"
                )
                compactValue(
                    title: store.isTemporaryFullChargeActive ? "临时目标" : "充电上限",
                    value: store.isTemporaryFullChargeActive ? "100%" : "\(regularChargeLimit)%"
                )
            }

            controls
        }
        .padding(12)
        .harborGlassCard(cornerRadius: 18, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private func compactValue(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(L10n.text(title))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(HarborPalette.dataBlue)
        }
        .frame(minWidth: 56, alignment: .trailing)
    }

    private var chargeLimitDetailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("充电上限")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(store.isTemporaryFullChargeActive ? "100%" : "\(regularChargeLimit)%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(HarborPalette.dataBlue)
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
                Text("100%")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            Label(chargeTargetStatusText, systemImage: chargeTargetStatusSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(store.controlState.isAvailable ? HarborPalette.success : HarborPalette.warning)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 0) {
                dashboardMetric(title: "电压", value: voltageText, symbol: "bolt.fill")
                Divider().frame(height: 40)
                dashboardMetric(
                    title: "功率",
                    value: signedPowerText(store.snapshot.powerWatts, fractionLength: 1),
                    symbol: "waveform.path.ecg"
                )
                Divider().frame(height: 40)
                dashboardMetric(title: "电池温度", value: temperatureText, symbol: "thermometer.medium")
            }
        }
        .padding(13)
        .harborGlassCard(cornerRadius: 18, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private var chargeLimitSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("充电上限")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    openWindow(id: "battery-details")
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("查看电池详情")
            }

            ZStack {
                Circle()
                    .stroke(HarborPalette.dataBlue.opacity(0.10), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.02, store.chargeLimit / 100))
                    .stroke(
                        HarborPalette.dataBlue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(regularChargeLimit)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(HarborPalette.dataBlue)
                        .monospacedDigit()
                    Text(L10n.text(store.isTemporaryFullChargeActive ? "临时目标" : "目标"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            .frame(maxWidth: .infinity)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .harborGlassCard(cornerRadius: 18, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private var powerAllocationCard: some View {
        let input = max(store.snapshot.adapterInputWatts ?? 0, 0)
        let system = max(store.snapshot.systemLoadWatts ?? 0, 0)
        let batterySigned = store.snapshot.powerWatts ?? 0
        let battery = abs(batterySigned)
        let maximum = max(input, system, battery, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("功率分配")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 8) {
                DashboardPowerColumn(
                    title: "输入",
                    value: input,
                    maximum: maximum,
                    tint: HarborPalette.dataBlue
                )
                DashboardPowerColumn(
                    title: "系统",
                    value: system,
                    maximum: maximum,
                    tint: Color.cyan.opacity(0.72)
                )
                DashboardPowerColumn(
                    title: "电池",
                    value: battery,
                    displayValue: signedPowerText(batterySigned, fractionLength: 1),
                    maximum: maximum,
                    tint: (store.snapshot.powerWatts ?? 0) < 0
                        ? HarborPalette.warning
                        : HarborPalette.success
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .harborGlassCard(cornerRadius: 18, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private var chargeControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("充电控制")
                .font(.headline)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前电量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(store.snapshot.percentage)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(HarborPalette.dataBlue)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("充电上限目标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.isTemporaryFullChargeActive ? "100%" : "\(regularChargeLimit)%")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(HarborPalette.dataBlue)
                        .monospacedDigit()
                }
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
                Text("\(regularChargeLimit)%")
                    .foregroundStyle(HarborPalette.dataBlue)
                Spacer()
                Text("100%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Label(chargeTargetStatusText, systemImage: chargeTargetStatusSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(store.controlState.isAvailable ? HarborPalette.success : HarborPalette.warning)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 0) {
                dashboardMetric(
                    title: "电压",
                    value: voltageText,
                    symbol: "bolt.fill"
                )
                Divider().frame(height: 40)
                dashboardMetric(
                    title: "功率",
                    value: signedPowerText(store.snapshot.powerWatts, fractionLength: 1),
                    symbol: "waveform.path.ecg"
                )
                Divider().frame(height: 40)
                dashboardMetric(
                    title: "电池温度",
                    value: temperatureText,
                    symbol: "thermometer.medium"
                )
            }

        }
        .padding(15)
        .harborGlassCard(cornerRadius: 20, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private var regularChargeLimit: Int {
        Int(store.chargeLimit.rounded())
    }

    private var chargeTargetStatusText: String {
        guard store.isTemporaryFullChargeActive else { return store.chargeLimitStatusText }
        return L10n.format("临时充满已启用，结束后恢复 %lld%% 上限", regularChargeLimit)
    }

    private var chargeTargetStatusSymbol: String {
        store.isTemporaryFullChargeActive ? "bolt.badge.checkmark.fill" : store.chargeLimitStatusSymbol
    }

    private var currentStateCard: some View {
        let status = store.chargingPathStatus
        return VStack(alignment: .leading, spacing: 12) {
            Text("当前状态")
                .font(.headline)

            HStack(spacing: 3) {
                stateStage(status.connection.displayName, status.connection.symbol, tint: HarborPalette.dataBlue)
                stateArrow
                stateStage(status.negotiation.displayName, status.negotiation.symbol, tint: HarborPalette.dataBlue)
                stateArrow
                stateStage(status.systemSupply.displayName, status.systemSupply.symbol, tint: HarborPalette.dataBlue)
                stateArrow
                stateStage(status.batteryFlow.displayName, status.batteryFlow.symbol, tint: diagnosticTint)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status.diagnostic.symbol)
                    .foregroundStyle(diagnosticTint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.diagnostic.title)
                        .font(.caption.weight(.semibold))
                    Text(status.diagnostic.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .harborGlassCard(cornerRadius: 18, tint: HarborPalette.dataBlue.opacity(0.04))
    }

    private var diagnosticTint: Color {
        switch store.chargingPathStatus.diagnostic.level {
        case .normal: HarborPalette.success
        case .informational: HarborPalette.dataBlue
        case .warning: HarborPalette.warning
        }
    }

    private func stateStage(_ value: String, _ symbol: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.08), in: Circle())
                .overlay { Circle().stroke(tint.opacity(0.24), lineWidth: 1) }
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
    }

    private var stateArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HarborPalette.dataBlue.opacity(0.62))
    }

    private func dashboardMetric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HarborPalette.dataBlue)
                .frame(width: 28, height: 28)
                .background(HarborPalette.dataBlue.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(L10n.text(title))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var voltageText: String {
        let voltage = store.snapshot.powerSource == .adapter
            ? (store.snapshot.adapterVoltageVolts ?? store.snapshot.voltageVolts)
            : store.snapshot.voltageVolts
        return voltage.map {
            $0.formatted(.number.precision(.fractionLength(1))) + " V"
        } ?? "— V"
    }

    private var temperatureText: String {
        store.snapshot.temperatureCelsius.map {
            $0.formatted(.number.precision(.fractionLength(1))) + "°C"
        } ?? "—"
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 10) {
                ControlButton(
                    title: L10n.text(store.isChargingPaused ? "恢复充电" : "暂停充电"),
                    subtitle: L10n.text(store.isChargingPaused ? "重新允许电池充电" : "停止向电池充电"),
                    symbol: store.isChargingPaused ? "play.fill" : "pause.fill",
                    tint: HarborPalette.dataBlue,
                    enabled: store.controlState.isAvailable && !store.isChargingCommandInProgress,
                    action: store.toggleChargingPaused
                )
                ControlButton(
                    title: L10n.text(store.isTemporaryFullChargeActive ? "结束临时充满" : "临时充满"),
                    subtitle: L10n.text(store.isTemporaryFullChargeActive ? "恢复常规充电上限" : "临时调整到 100%"),
                    symbol: store.isTemporaryFullChargeActive ? "xmark.circle.fill" : "bolt.fill",
                    tint: store.isTemporaryFullChargeActive ? HarborPalette.danger : HarborPalette.dataBlue,
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
}

private struct DashboardPowerColumn: View {
    let title: String
    let value: Double
    var displayValue: String? = nil
    let maximum: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(L10n.text(title))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(displayValue ?? value.formatted(.number.precision(.fractionLength(1))) + " W")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            GeometryReader { proxy in
                let fraction = min(max(value / maximum, 0), 1)
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(HarborPalette.dataBlue.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.58), tint],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(3, proxy.size.height * fraction))
                }
            }
            .frame(width: 30, height: 72)
        }
        .frame(maxWidth: .infinity)
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
    let subtitle: String
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(enabled ? tint : .secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        (enabled ? tint : Color.secondary).opacity(0.10),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
                    .frame(height: 58)
            .harborGlassCard(
                cornerRadius: 16,
                tint: HarborPalette.dataBlue.opacity(0.05)
            )
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
                    .opacity(colorScheme == .dark ? 0.42 : 0.36)
            }
        }
        .ignoresSafeArea()
    }
}

private struct HarborBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = HarborBackdropVisualEffectView(frame: .zero)
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        view.alphaValue = 1
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
        nsView.alphaValue = 1
    }
}

private final class HarborBackdropVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // NSViewRepresentable can be attached while SwiftUI is already in an
        // AppKit layout pass. Mutating the window synchronously here causes a
        // recursive layout on first menu expansion, which shows up as a very
        // visible hitch. Defer the one-time window configuration to the next
        // main-loop turn instead.
        guard let attachedWindow = window else { return }
        DispatchQueue.main.async { [weak attachedWindow] in
            attachedWindow?.isOpaque = false
            attachedWindow?.backgroundColor = .clear
        }
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

        if #available(macOS 26.0, *), !reduceTransparency, interactive {
            content
                .background {
                    shape.fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.48 : 0.54)
                    )
                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.12 : 0.09))
                    }
                }
                .glassEffect(
                    .regular.tint(tint?.opacity(0.40)).interactive(interactive),
                    in: shape
                )
                .overlay { subtleBoundary(for: shape) }
        } else {
            content
                .background {
                    shape.fill(
                        reduceTransparency
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.58 : 0.64)
                    )
                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.11 : 0.07))
                    }
                }
                .overlay { subtleBoundary(for: shape) }
        }
    }

    private func subtleBoundary(
        for shape: RoundedRectangle
    ) -> some View {
        ZStack {
            shape
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.075), lineWidth: 0.6)
            if interactive {
                shape
                    .inset(by: 0.5)
                    .stroke(HarborPalette.accent.opacity(0.07), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}
