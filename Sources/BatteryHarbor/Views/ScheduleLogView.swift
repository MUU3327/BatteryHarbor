import SwiftUI

struct ScheduleLogView: View {
    @EnvironmentObject private var store: BatteryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("计划执行日志").font(.title2.bold())
                    Text("最近 100 条执行、失败和跳过记录").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("清除", role: .destructive, action: store.clearScheduleLogs)
                    .disabled(store.scheduleLogs.isEmpty)
            }
            .padding(20)
            Divider()

            if store.scheduleLogs.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("暂无执行记录").font(.headline)
                    Text("计划任务触发后会在这里记录结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.scheduleLogs) { log in
                    HStack(spacing: 11) {
                        Image(systemName: log.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(log.succeeded ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(log.scheduleName).font(.headline)
                                Text(log.action.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(log.message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(log.timestamp, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 560, height: 440)
        .background { HarborRootBackground() }
    }
}
