import Charts
import SwiftUI

struct PowerChartView: View {
    @EnvironmentObject private var store: BatteryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时电池功率")
                        .font(.headline)
                    Text("每 2 秒读取 · 最近 6 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let current = store.snapshot.powerWatts {
                    Text(signedPowerText(current, fractionLength: 2))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }

            powerFlow

            Chart(chartSamples) { sample in
                    AreaMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("功率", sample.watts)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [HarborPalette.dataBlue.opacity(0.38), HarborPalette.accent.opacity(0.025)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("时间", sample.timestamp),
                        y: .value("功率", sample.watts)
                    )
                    .foregroundStyle(HarborPalette.dataBlue)
                    .interpolationMethod(.linear)

                    RuleMark(y: .value("零功率", 0))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                }
                .chartYAxisLabel("瓦特")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.minute().second())
                    }
                }
            .frame(height: 175)

            HStack(spacing: 18) {
                Label("正值：充入电池", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(HarborPalette.success)
                Label("负值：电池输出", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(HarborPalette.warning)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var chartSamples: [PowerSample] {
        let samples = store.samples
        // Forty-eight points preserve the six-minute trend while reducing the
        // number of marks, gradients and hit-test nodes rebuilt on each sample.
        let maximumPoints = 48
        guard samples.count > maximumPoints else { return samples }
        let stride = max(1, Int(ceil(Double(samples.count) / Double(maximumPoints))))
        var result = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) ? sample : nil
        }
        if let last = samples.last, result.last?.id != last.id {
            result.append(last)
        }
        return result
    }

    private var powerFlow: some View {
        Group {
            if store.snapshot.powerSource == .adapter {
                adapterPowerFlow
            } else {
                HStack(spacing: 7) {
                    flowNode(
                        title: L10n.text("电池"),
                        value: signedPowerText(store.snapshot.powerWatts, fractionLength: 2),
                        symbol: "battery.75percent",
                        color: HarborPalette.warning
                    )
                    flowArrow
                    flowNode(
                        title: L10n.text("系统使用"),
                        value: watts(store.snapshot.systemLoadWatts ?? store.snapshot.powerWatts.map { abs($0) }),
                        symbol: "laptopcomputer",
                        color: HarborPalette.dataBlue
                    )
                }
            }
        }
        .padding(10)
        .harborGlassCard(cornerRadius: 16)
    }

    private var adapterPowerFlow: some View {
        let input = max(store.snapshot.adapterInputWatts ?? 0, 0)
        let system = max(store.snapshot.systemLoadWatts ?? 0, 0)
        let batterySigned = store.snapshot.powerWatts ?? 0
        let battery = abs(batterySigned)
        let allocationTotal = max(batterySigned >= 0 ? input : system, 0.01)
        let systemFraction = min(max((batterySigned >= 0 ? system : input) / allocationTotal, 0), 1)
        let batteryFraction = min(max(battery / allocationTotal, 0), 1)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 6) {
                    Image("HarborPowerMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(HarborPalette.accent)
                        .frame(width: 15, height: 15)
                    Text("实时功率流向")
                }
                .font(.caption.weight(.semibold))
                Spacer()
                Text("适配器供电")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                flowMetricNode(
                    title: L10n.text("总输入"),
                    value: watts(store.snapshot.adapterInputWatts),
                    symbol: "powerplug.fill",
                    color: HarborPalette.warning
                )
                .frame(width: 98)

                PowerFlowBranch(
                    systemFraction: systemFraction,
                    batteryFraction: batteryFraction,
                    batteryIsSupplying: batterySigned < 0
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    flowMetricNode(
                        title: L10n.text("流向系统"),
                        value: watts(store.snapshot.systemLoadWatts),
                        symbol: "laptopcomputer",
                        color: HarborPalette.dataBlue
                    )
                    flowMetricNode(
                        title: L10n.text("电池"),
                        value: signedPowerText(store.snapshot.powerWatts, fractionLength: 2),
                        symbol: "battery.75percent",
                        color: batterySigned < 0 ? HarborPalette.warning : HarborPalette.success,
                        isActive: battery > 0.01
                    )
                }
                .frame(width: 125)
            }
            .frame(height: 88)

            HStack(spacing: 14) {
                allocationLabel(
                    title: L10n.text(batterySigned < 0 ? "适配器" : "系统"),
                    fraction: systemFraction,
                    color: HarborPalette.dataBlue
                )
                allocationLabel(
                    title: L10n.text("电池"),
                    fraction: batteryFraction,
                    color: batterySigned < 0 ? HarborPalette.warning : HarborPalette.success
                )
                Spacer()
                Text("应用分项见 App 页")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func flowNode(title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flowMetricNode(
        title: String,
        value: String,
        symbol: String,
        color: Color,
        isActive: Bool = true
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
        .padding(.horizontal, 7)
        .background(color.opacity(isActive ? 0.11 : 0.04), in: RoundedRectangle(cornerRadius: 9))
        .opacity(isActive ? 1 : 0.55)
    }

    private func allocationLabel(title: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(Int((fraction * 100).rounded()))%")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func watts(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) + " W" } ?? "— W"
    }
}

private struct PowerFlowBranch: View {
    let systemFraction: Double
    let batteryFraction: Double
    let batteryIsSupplying: Bool

    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: 1, y: size.height / 2)
            let junction = CGPoint(x: size.width * 0.38, y: size.height / 2)
            let systemEnd = CGPoint(x: size.width - 5, y: size.height * 0.25)
            let batteryEnd = CGPoint(x: size.width - 5, y: size.height * 0.75)

            var trunk = Path()
            trunk.move(to: start)
            trunk.addLine(to: junction)
            context.stroke(
                trunk,
                with: .color(HarborPalette.warning.opacity(0.78)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )

            drawBranch(
                in: &context,
                from: junction,
                to: systemEnd,
                color: HarborPalette.dataBlue,
                fraction: systemFraction,
                pointsRight: true
            )
            drawBranch(
                in: &context,
                from: junction,
                to: batteryEnd,
                color: batteryIsSupplying ? HarborPalette.warning : HarborPalette.success,
                fraction: batteryFraction,
                pointsRight: !batteryIsSupplying
            )
        }
    }

    private func drawBranch(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        fraction: Double,
        pointsRight: Bool
    ) {
        let active = fraction > 0.001
        let opacity = active ? 0.9 : 0.18
        let width = active ? 2.2 + 4.3 * min(max(fraction, 0), 1) : 1.4
        var branch = Path()
        branch.move(to: start)
        branch.addCurve(
            to: end,
            control1: CGPoint(x: start.x + (end.x - start.x) * 0.45, y: start.y),
            control2: CGPoint(x: start.x + (end.x - start.x) * 0.55, y: end.y)
        )
        context.stroke(
            branch,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )

        guard active else { return }
        let direction: CGFloat = pointsRight ? 1 : -1
        let tipX = pointsRight ? end.x + 3 : start.x - 3
        let centerY = pointsRight ? end.y : start.y
        var arrow = Path()
        arrow.move(to: CGPoint(x: tipX + 3 * direction, y: centerY))
        arrow.addLine(to: CGPoint(x: tipX - 3 * direction, y: centerY - 3.5))
        arrow.addLine(to: CGPoint(x: tipX - 3 * direction, y: centerY + 3.5))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color.opacity(opacity)))
    }
}
