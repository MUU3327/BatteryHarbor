import AppKit
import SwiftUI

struct AppEnergyRankingView: View {
    @EnvironmentObject private var store: BatteryStore
    @State private var range: EnergyRankingRange = .current

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 9) {
                        Image("HarborAppMark")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(HarborPalette.accent)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(range == .current ? "当前耗电 App" : "耗电历史排行"))
                                .font(.headline)
                            Text(range.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.isEnergyRankingSampling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Picker("统计范围", selection: $range) {
                    ForEach(EnergyRankingRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if displayedRanking.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text(L10n.text(range == .current ? "正在建立基线" : "还没有足够的历史数据"))
                            .font(.headline)
                        Text(L10n.text(range == .current ? "保持面板打开约 5–10 秒即可看到排行。" : "电池港运行时会每 30 秒保存一次，最多保留 24 小时。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(displayedRanking.enumerated()), id: \.element.id) { index, usage in
                            energyRow(index: index, usage: usage)
                        }
                    }
                }

                Text("排行聚合同一 App 的辅助进程；历史数据保存在本机，数值用于相对比较。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var displayedRanking: [AppEnergyUsage] {
        guard let interval = range.interval else { return store.appEnergyRanking }
        return store.energyRanking(since: Date().addingTimeInterval(-interval))
    }

    private func energyRow(index: Int, usage: AppEnergyUsage) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Image(nsImage: NSWorkspace.shared.icon(forFile: usage.bundlePath))
                .resizable()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(usage.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detailText(for: usage))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text(usage.impactScore.formatted(.number.precision(.fractionLength(2))))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(index == 0 ? HarborPalette.accent : .primary)
        }
        .padding(.horizontal, 10)
        .frame(height: 47)
        .harborGlassCard(cornerRadius: 13)
    }

    private func detailText(for usage: AppEnergyUsage) -> String {
        if usage.energyJoules > 0 {
            return "\(usage.energyJoules.formatted(.number.precision(.fractionLength(3)))) J · CPU \(usage.cpuPercent.formatted(.number.precision(.fractionLength(1))))%"
        }
        return L10n.format(
            "CPU %@%% · 唤醒 %lld",
            usage.cpuPercent.formatted(.number.precision(.fractionLength(1))),
            usage.wakeups
        )
    }
}

private enum EnergyRankingRange: String, CaseIterable, Identifiable {
    case current
    case oneHour
    case twentyFourHours

    var id: Self { self }

    var title: String {
        switch self {
        case .current: L10n.text("实时")
        case .oneHour: L10n.text("1 小时")
        case .twentyFourHours: L10n.text("24 小时")
        }
    }

    var subtitle: String {
        switch self {
        case .current: L10n.text("按最近 5 秒的公开进程能耗数据估算")
        case .oneHour: L10n.text("过去 1 小时的本机累计采样")
        case .twentyFourHours: L10n.text("过去 24 小时的本机累计采样")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .current: nil
        case .oneHour: 60 * 60
        case .twentyFourHours: 24 * 60 * 60
        }
    }
}
