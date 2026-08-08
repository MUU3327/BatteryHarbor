import Foundation

struct AppEnergyUsage: Identifiable, Codable, Equatable, Sendable {
    var id: String { bundlePath }

    let name: String
    let bundlePath: String
    let energyJoules: Double
    let cpuPercent: Double
    let wakeups: UInt64
    let ioMegabytes: Double
    let impactScore: Double
}

struct AppEnergyHistorySample: Codable, Equatable, Sendable {
    let timestamp: Date
    let usages: [AppEnergyUsage]
}
