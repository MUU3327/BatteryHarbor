import Darwin
import Foundation

actor AppEnergyMonitor {
    struct Counters: Equatable, Sendable {
        let processStartTime: UInt64
        let energyNanojoules: UInt64
        let cpuNanoseconds: UInt64
        let wakeups: UInt64
        let ioBytes: UInt64
    }

    private struct AppAggregate {
        let name: String
        let bundlePath: String
        var energyNanojoules: UInt64 = 0
        var cpuNanoseconds: UInt64 = 0
        var wakeups: UInt64 = 0
        var ioBytes: UInt64 = 0
    }

    private var previousCounters: [pid_t: Counters] = [:]
    private var previousSampleDate: Date?

    func sample() -> [AppEnergyUsage] {
        let now = Date()
        let interval = max(now.timeIntervalSince(previousSampleDate ?? now), 0.001)
        var currentCounters: [pid_t: Counters] = [:]
        var aggregates: [String: AppAggregate] = [:]

        for pid in allProcessIdentifiers() where pid > 0 {
            guard let counters = counters(for: pid),
                  let executablePath = executablePath(for: pid),
                  let app = appIdentity(forExecutablePath: executablePath)
            else { continue }

            currentCounters[pid] = counters
            guard let previous = previousCounters[pid],
                  previous.processStartTime == counters.processStartTime
            else { continue }

            let delta = Self.delta(current: counters, previous: previous)
            var aggregate = aggregates[app.path] ?? AppAggregate(name: app.name, bundlePath: app.path)
            aggregate.energyNanojoules += delta.energyNanojoules
            aggregate.cpuNanoseconds += delta.cpuNanoseconds
            aggregate.wakeups += delta.wakeups
            aggregate.ioBytes += delta.ioBytes
            aggregates[app.path] = aggregate
        }

        previousCounters = currentCounters
        previousSampleDate = now

        return aggregates.values
            .map { aggregate in
                let energyJoules = Double(aggregate.energyNanojoules) / 1_000_000_000
                let cpuPercent = Double(aggregate.cpuNanoseconds) / 1_000_000_000
                    / interval / Double(max(ProcessInfo.processInfo.processorCount, 1)) * 100
                let ioMegabytes = Double(aggregate.ioBytes) / 1_048_576
                return AppEnergyUsage(
                    name: aggregate.name,
                    bundlePath: aggregate.bundlePath,
                    energyJoules: energyJoules,
                    cpuPercent: cpuPercent,
                    wakeups: aggregate.wakeups,
                    ioMegabytes: ioMegabytes,
                    impactScore: Self.impactScore(
                        energyJoules: energyJoules,
                        cpuSeconds: Double(aggregate.cpuNanoseconds) / 1_000_000_000,
                        wakeups: aggregate.wakeups,
                        ioMegabytes: ioMegabytes
                    )
                )
            }
            .filter { $0.impactScore > 0.0001 }
            .sorted { $0.impactScore > $1.impactScore }
            .prefix(8)
            .map { $0 }
    }

    static func delta(current: Counters, previous: Counters) -> Counters {
        Counters(
            processStartTime: current.processStartTime,
            energyNanojoules: subtractWithoutUnderflow(current.energyNanojoules, previous.energyNanojoules),
            cpuNanoseconds: subtractWithoutUnderflow(current.cpuNanoseconds, previous.cpuNanoseconds),
            wakeups: subtractWithoutUnderflow(current.wakeups, previous.wakeups),
            ioBytes: subtractWithoutUnderflow(current.ioBytes, previous.ioBytes)
        )
    }

    static func impactScore(
        energyJoules: Double,
        cpuSeconds: Double,
        wakeups: UInt64,
        ioMegabytes: Double
    ) -> Double {
        if energyJoules > 0 { return energyJoules }
        return cpuSeconds * 10 + Double(wakeups) * 0.002 + ioMegabytes * 0.05
    }

    private static func subtractWithoutUnderflow(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func allProcessIdentifiers() -> [pid_t] {
        let estimatedCount = max(proc_listallpids(nil, 0), 256)
        var identifiers = [pid_t](repeating: 0, count: Int(estimatedCount) + 64)
        let byteCount = Int32(identifiers.count * MemoryLayout<pid_t>.stride)
        let count = proc_listallpids(&identifiers, byteCount)
        guard count > 0 else { return [] }
        return Array(identifiers.prefix(Int(count)))
    }

    private func counters(for pid: pid_t) -> Counters? {
        var currentUsage = rusage_info_v6()
        let currentResult = withUnsafeMutablePointer(to: &currentUsage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V6, reboundPointer)
            }
        }
        if currentResult == 0 {
            return Counters(
                processStartTime: currentUsage.ri_proc_start_abstime,
                energyNanojoules: currentUsage.ri_energy_nj,
                cpuNanoseconds: currentUsage.ri_user_time + currentUsage.ri_system_time,
                wakeups: currentUsage.ri_pkg_idle_wkups + currentUsage.ri_interrupt_wkups,
                ioBytes: currentUsage.ri_diskio_bytesread + currentUsage.ri_diskio_byteswritten
            )
        }

        // macOS releases predating rusage v6 still provide the CPU/wakeup/I/O fields in v4.
        var legacyUsage = rusage_info_v4()
        let legacyResult = withUnsafeMutablePointer(to: &legacyUsage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPointer)
            }
        }
        guard legacyResult == 0 else { return nil }
        return Counters(
            processStartTime: legacyUsage.ri_proc_start_abstime,
            energyNanojoules: 0,
            cpuNanoseconds: legacyUsage.ri_user_time + legacyUsage.ri_system_time,
            wakeups: legacyUsage.ri_pkg_idle_wkups + legacyUsage.ri_interrupt_wkups,
            ioBytes: legacyUsage.ri_diskio_bytesread + legacyUsage.ri_diskio_byteswritten
        )
    }

    private func executablePath(for pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a C macro Swift cannot import; Darwin defines it as 4 * MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func appIdentity(forExecutablePath path: String) -> (name: String, path: String)? {
        let components = URL(fileURLWithPath: path).pathComponents
        // Use the outermost bundle so Electron/Chromium helper apps roll up to their host application.
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = NSString.path(withComponents: Array(components[...appIndex]))
        let appURL = URL(fileURLWithPath: appPath)
        let bundle = Bundle(url: appURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        return (displayName ?? bundleName ?? fallbackName, appPath)
    }
}
