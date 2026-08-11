import AppKit
import SwiftUI

struct AutomationView: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Image("HarborScheduleMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(HarborPalette.accent)
                        .frame(width: 18, height: 18)
                    Text("计划任务")
                }
                .font(.headline)
                Spacer()
                Button {
                    openWindow(id: "schedule-logs")
                } label: {
                    Label("日志", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    store.beginCreatingSchedule()
                    openWindow(id: "schedule-editor")
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            calibrationCard

            if store.schedules.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(store.schedules) { schedule in
                        ScheduleRow(schedule: schedule)
                            .environmentObject(store)
                    }
                }
            }

            Text("计划仅在电池港运行时检查；所有动作仍受 Helper 和人工确认闸门保护。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var calibrationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: store.calibrationSession?.phase.symbol ?? "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(HarborPalette.accent)
                .frame(width: 38, height: 38)
                .background(HarborPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.calibrationSession?.phase.title ?? L10n.text("电池校准"))
                    .font(.subheadline.weight(.semibold))
                if let session = store.calibrationSession {
                    ProgressView(value: session.progress)
                        .tint(HarborPalette.accent)
                    Text(session.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("完整充满、静置、放至 10%，再完整充满。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            calibrationButton
        }
        .padding(11)
        .harborGlassCard(cornerRadius: 15)
    }

    @ViewBuilder
    private var calibrationButton: some View {
        if store.calibrationSession?.isActive == true {
            Button("停止", role: .destructive, action: store.cancelCalibration)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if store.calibrationSession != nil {
            Button("清除", action: store.clearCalibrationResult)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Button("开始", action: store.startCalibration)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.controlState.isAvailable)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image("HarborScheduleMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 38, height: 38)
                .foregroundStyle(HarborPalette.accent)
            Text("还没有计划")
                .font(.headline)
            Text("可按星期和时间应用上限、暂停、恢复或临时充满。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct ScheduleRow: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.openWindow) private var openWindow
    let schedule: ChargeSchedule

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: schedule.action.symbol)
                .foregroundStyle(HarborPalette.dataBlue)
                .frame(width: 32, height: 32)
                .background(HarborPalette.dataBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(schedule.name).font(.subheadline.weight(.semibold))
                    Text(schedule.timeText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(detailText).font(.caption).foregroundStyle(.secondary)
                if let result = schedule.lastResult {
                    Text(result).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { store.setScheduleEnabled(schedule.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button {
                store.beginEditingSchedule(schedule)
                openWindow(id: "schedule-editor")
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("编辑计划")
            Button(role: .destructive) {
                store.deleteSchedule(schedule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .harborGlassCard(cornerRadius: 15)
    }

    private var detailText: String {
        let action = schedule.action == .applyLimit
            ? L10n.format("上限 %lld%%", schedule.chargeLimit ?? 80)
            : schedule.action.displayName
        return "\(schedule.weekdaysText) · \(action)"
    }
}

struct ScheduleEditorWindow: View {
    @EnvironmentObject private var store: BatteryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScheduleEditorView(
            schedule: store.scheduleBeingEdited,
            onSave: { schedule in
                store.saveScheduleFromEditor(schedule)
                dismiss()
            },
            onCancel: {
                store.cancelScheduleEditing()
                dismiss()
            }
        )
        .id(store.scheduleEditorSessionID)
        .background(ScheduleEditorWindowBridge(sessionID: store.scheduleEditorSessionID))
    }
}

private struct ScheduleEditorView: View {
    @State private var name: String
    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var action: ScheduledChargeAction
    @State private var limit: Double

    let originalSchedule: ChargeSchedule?
    let onSave: (ChargeSchedule) -> Void
    let onCancel: () -> Void

    init(
        schedule: ChargeSchedule? = nil,
        onSave: @escaping (ChargeSchedule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        originalSchedule = schedule
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: schedule?.name ?? L10n.text("电池养护"))
        var components = DateComponents()
        components.hour = schedule?.hour ?? Calendar.current.component(.hour, from: Date())
        components.minute = schedule?.minute ?? Calendar.current.component(.minute, from: Date())
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
        _weekdays = State(initialValue: schedule?.weekdays ?? Set(1...7))
        _action = State(initialValue: schedule?.action ?? .applyLimit)
        _limit = State(initialValue: Double(schedule?.chargeLimit ?? 80))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(originalSchedule == nil ? "新增计划" : "编辑计划").font(.title3.bold())
            TextField("计划名称", text: $name)
            DatePicker("执行时间", selection: $time, displayedComponents: .hourAndMinute)
            VStack(alignment: .leading, spacing: 8) {
                Text("重复").font(.subheadline)
                HStack(spacing: 5) {
                    ForEach(weekdayOptions, id: \.value) { item in
                        Button(item.label) { toggleWeekday(item.value) }
                            .buttonStyle(.bordered)
                            .tint(weekdays.contains(item.value) ? .blue : .gray)
                            .controlSize(.small)
                    }
                }
            }
            Picker("动作", selection: $action) {
                ForEach(ScheduledChargeAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
            if action == .applyLimit {
                HStack {
                    Text("充电上限")
                    Slider(value: $limit, in: 50...100, step: 5)
                    Text("\(Int(limit))%").monospacedDigit().frame(width: 42)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440, height: 390)
    }

    private var weekdayOptions: [(label: String, value: Int)] {
        [
            (label: L10n.text("一"), value: 2), (label: L10n.text("二"), value: 3),
            (label: L10n.text("三"), value: 4), (label: L10n.text("四"), value: 5),
            (label: L10n.text("五"), value: 6), (label: L10n.text("六"), value: 7),
            (label: L10n.text("日"), value: 1)
        ]
    }

    private func toggleWeekday(_ value: Int) {
        if weekdays.contains(value) { weekdays.remove(value) } else { weekdays.insert(value) }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        onSave(ChargeSchedule(
            id: originalSchedule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            weekdays: weekdays,
            action: action,
            chargeLimit: action == .applyLimit ? Int(limit) : nil,
            isEnabled: originalSchedule?.isEnabled ?? true,
            lastTriggeredAt: originalSchedule?.lastTriggeredAt,
            lastResult: originalSchedule?.lastResult
        ))
    }
}

private struct ScheduleEditorWindowBridge: NSViewRepresentable {
    let sessionID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window,
                  context.coordinator.activatedSessionID != sessionID
            else { return }

            context.coordinator.activatedSessionID = sessionID
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    final class Coordinator {
        var activatedSessionID: UUID?
    }
}
