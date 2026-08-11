import SwiftUI

struct BatteryDetailView: View {
    @EnvironmentObject private var store: BatteryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: store.snapshot.menuBarSymbol)
                    .font(.system(size: 30))
                    .foregroundStyle(.blue, .green)
                    .frame(width: 52, height: 52)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("电池详情").font(.title2.bold())
                    Text("实时数据每 2 秒更新").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.snapshot.percentage)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
            }
            .padding(22)

            Form {
                Section("当前状态") {
                    detail("状态", store.snapshot.stateText)
                    detail("电源来源", store.snapshot.powerSource.displayName)
                    detail("预计时间", store.snapshot.timeRemainingText ?? "计算中")
                    detail("温度", format(store.snapshot.temperatureCelsius, suffix: "°C", digits: 1))
                    detail("电压", format(store.snapshot.voltageVolts, suffix: " V", digits: 2))
                    detail("电流", format(store.snapshot.currentAmps, suffix: " A", digits: 2))
                }

                Section("容量与健康") {
                    detail("设计容量", capacity(store.snapshot.designCapacityMAh))
                    detail("当前满充容量", capacity(store.snapshot.fullChargeCapacityMAh))
                    detail("剩余容量", capacity(store.snapshot.remainingCapacityMAh))
                    detail("健康度", format(store.snapshot.healthPercentage, suffix: "%", digits: 0))
                    detail("循环次数", store.snapshot.cycleCount.map(String.init) ?? "—")
                }

                Section("实时功率分流") {
                    detail("适配器输入", format(store.snapshot.adapterInputWatts, suffix: " W", digits: 2))
                    detail("适配器输入电压", format(store.snapshot.adapterVoltageVolts, suffix: " V", digits: 2))
                    detail("适配器输入电流", format(store.snapshot.adapterCurrentAmps, suffix: " A", digits: 2))
                    detail("系统使用", format(store.snapshot.systemLoadWatts, suffix: " W", digits: 2))
                    detail(
                        "电池功率",
                        signedPowerText(store.snapshot.powerWatts, fractionLength: 2)
                    )
                    detail("适配器损耗", format(store.snapshot.adapterEfficiencyLossWatts, suffix: " W", digits: 2))
                    detail("适配器额定功率", store.snapshot.adapterRatedWatts.map { "\($0) W" } ?? "—")
                }

                Section("控制状态") {
                    detail("充电上限", "\(Int(store.chargeLimit.rounded()))%")
                    detail("控制模块", store.helperRegistrationStatus.displayName)
                    detail("高温保护", store.isHighTemperatureProtectionActive ? "正在保护" : "正常")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 560)
        .background { HarborRootBackground() }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func capacity(_ value: Int?) -> String {
        value.map { "\($0) mAh" } ?? "—"
    }

    private func format(_ value: Double?, suffix: String, digits: Int) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(digits))) + suffix } ?? "—"
    }
}
