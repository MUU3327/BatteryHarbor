import Foundation

enum ScheduledChargeAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case applyLimit = "应用充电上限"
    case pauseCharging = "暂停充电"
    case resumeCharging = "恢复充电"
    case temporaryFullCharge = "临时充满"

    var id: Self { self }

    var displayName: String { L10n.text(rawValue) }

    var symbol: String {
        switch self {
        case .applyLimit: "slider.horizontal.3"
        case .pauseCharging: "pause.fill"
        case .resumeCharging: "play.fill"
        case .temporaryFullCharge: "bolt.fill"
        }
    }
}

struct ChargeSchedule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
    var action: ScheduledChargeAction
    var chargeLimit: Int?
    var isEnabled: Bool
    var lastTriggeredAt: Date?
    var lastResult: String?

    init(
        id: UUID = UUID(),
        name: String,
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        action: ScheduledChargeAction,
        chargeLimit: Int? = nil,
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil,
        lastResult: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.action = action
        self.chargeLimit = chargeLimit.map { min(max($0, 50), 100) }
        self.isEnabled = isEnabled
        self.lastTriggeredAt = lastTriggeredAt
        self.lastResult = lastResult
    }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var weekdaysText: String {
        if weekdays == Set(1...7) { return L10n.text("每天") }
        let labels = [
            1: L10n.text("周日"), 2: L10n.text("周一"), 3: L10n.text("周二"),
            4: L10n.text("周三"), 5: L10n.text("周四"), 6: L10n.text("周五"),
            7: L10n.text("周六")
        ]
        return [2, 3, 4, 5, 6, 7, 1]
            .filter { weekdays.contains($0) }
            .compactMap { labels[$0] }
            .joined(separator: " ")
    }

    func isDue(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, weekdays.contains(calendar.component(.weekday, from: date)),
              calendar.component(.hour, from: date) == hour,
              calendar.component(.minute, from: date) == minute
        else { return false }

        guard let lastTriggeredAt else { return true }
        return !calendar.isDate(lastTriggeredAt, equalTo: date, toGranularity: .minute)
    }
}

struct ScheduleExecutionLog: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let scheduleID: UUID
    let scheduleName: String
    let action: ScheduledChargeAction
    let timestamp: Date
    let succeeded: Bool
    let message: String

    init(
        id: UUID = UUID(),
        scheduleID: UUID,
        scheduleName: String,
        action: ScheduledChargeAction,
        timestamp: Date = Date(),
        succeeded: Bool,
        message: String
    ) {
        self.id = id
        self.scheduleID = scheduleID
        self.scheduleName = scheduleName
        self.action = action
        self.timestamp = timestamp
        self.succeeded = succeeded
        self.message = message
    }
}
