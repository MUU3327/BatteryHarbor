import Foundation

struct EnergyHistorySnapshot: Codable, Equatable, Sendable {
    var powerSamples: [PowerSample] = []
    var appSamples: [AppEnergyHistorySample] = []
}

actor EnergyHistoryArchive {
    private let fileURL: URL
    private var snapshot = EnergyHistorySnapshot()
    private var hasLoaded = false
    private var lastPowerRecordAt: Date?
    private var lastAppRecordAt: Date?
    private let retention: TimeInterval = 24 * 60 * 60

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base
                .appendingPathComponent("BatteryHarbor", isDirectory: true)
                .appendingPathComponent("EnergyHistory.json")
        }
    }

    func load() -> EnergyHistorySnapshot {
        loadIfNeeded()
        prune(relativeTo: Date())
        return snapshot
    }

    func record(power sample: PowerSample) {
        loadIfNeeded()
        guard lastPowerRecordAt.map({ sample.timestamp.timeIntervalSince($0) >= 30 }) ?? true else { return }
        lastPowerRecordAt = sample.timestamp
        snapshot.powerSamples.append(sample)
        prune(relativeTo: sample.timestamp)
        save()
    }

    func record(appUsages usages: [AppEnergyUsage], at date: Date = Date()) -> Bool {
        loadIfNeeded()
        guard !usages.isEmpty,
              lastAppRecordAt.map({ date.timeIntervalSince($0) >= 30 }) ?? true
        else { return false }
        lastAppRecordAt = date
        snapshot.appSamples.append(AppEnergyHistorySample(timestamp: date, usages: usages))
        prune(relativeTo: date)
        save()
        return true
    }

    func csvData() -> Data {
        loadIfNeeded()
        prune(relativeTo: Date())
        return Data(Self.csv(snapshot: snapshot).utf8)
    }

    func clear() {
        snapshot = EnergyHistorySnapshot()
        lastPowerRecordAt = nil
        lastAppRecordAt = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func csv(snapshot: EnergyHistorySnapshot) -> String {
        var rows = [
            "timestamp,type,name,bundle_path,battery_watts,energy_joules,cpu_percent,wakeups,io_megabytes,impact_score"
        ]
        let formatter = ISO8601DateFormatter()
        for sample in snapshot.powerSamples {
            rows.append([
                formatter.string(from: sample.timestamp), "power", "", "",
                String(sample.watts), "", "", "", "", ""
            ].map(csvEscape).joined(separator: ","))
        }
        for sample in snapshot.appSamples {
            for usage in sample.usages {
                rows.append([
                    formatter.string(from: sample.timestamp), "app", usage.name, usage.bundlePath, "",
                    String(usage.energyJoules), String(usage.cpuPercent), String(usage.wakeups),
                    String(usage.ioMegabytes), String(usage.impactScore)
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func aggregate(
        _ samples: [AppEnergyHistorySample],
        since cutoff: Date
    ) -> [AppEnergyUsage] {
        struct Aggregate {
            var name: String
            var energy = 0.0
            var cpu = 0.0
            var cpuCount = 0
            var wakeups: UInt64 = 0
            var io = 0.0
            var impact = 0.0
        }

        var aggregates: [String: Aggregate] = [:]
        for sample in samples where sample.timestamp >= cutoff {
            for usage in sample.usages {
                var aggregate = aggregates[usage.bundlePath] ?? Aggregate(name: usage.name)
                aggregate.name = usage.name
                aggregate.energy += usage.energyJoules
                aggregate.cpu += usage.cpuPercent
                aggregate.cpuCount += 1
                aggregate.wakeups += usage.wakeups
                aggregate.io += usage.ioMegabytes
                aggregate.impact += usage.impactScore
                aggregates[usage.bundlePath] = aggregate
            }
        }

        return aggregates.map { path, aggregate in
            AppEnergyUsage(
                name: aggregate.name,
                bundlePath: path,
                energyJoules: aggregate.energy,
                cpuPercent: aggregate.cpu / Double(max(aggregate.cpuCount, 1)),
                wakeups: aggregate.wakeups,
                ioMegabytes: aggregate.io,
                impactScore: aggregate.impact
            )
        }
        .sorted { $0.impactScore > $1.impactScore }
        .prefix(8)
        .map { $0 }
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(EnergyHistorySnapshot.self, from: data)
        else { return }
        snapshot = decoded
        lastPowerRecordAt = snapshot.powerSamples.last?.timestamp
        lastAppRecordAt = snapshot.appSamples.last?.timestamp
    }

    private func prune(relativeTo date: Date) {
        let cutoff = date.addingTimeInterval(-retention)
        snapshot.powerSamples.removeAll { $0.timestamp < cutoff }
        snapshot.appSamples.removeAll { $0.timestamp < cutoff }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is optional telemetry; live monitoring must continue if disk persistence fails.
        }
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
