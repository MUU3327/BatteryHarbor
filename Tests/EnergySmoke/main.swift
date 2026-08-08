import Foundation

let monitor = AppEnergyMonitor()

Task {
    _ = await monitor.sample()
    try? await Task.sleep(nanoseconds: 5_000_000_000)
    let ranking = await monitor.sample()

    guard !ranking.isEmpty else {
        FileHandle.standardError.write(Data("失败 / Failed: 5 秒采样后未获得 App 能耗排行 / no app energy ranking after 5 seconds\n".utf8))
        exit(1)
    }

    print("通过 / Passed: 获得 \(ranking.count) 个 App 的能耗增量 / captured energy deltas for \(ranking.count) apps")
    for usage in ranking.prefix(5) {
        print(
            "- \(usage.name): 指数 \(String(format: "%.3f", usage.impactScore))，"
                + "能量 \(String(format: "%.4f", usage.energyJoules)) J，"
                + "CPU \(String(format: "%.2f", usage.cpuPercent))%"
        )
    }
    exit(0)
}

dispatchMain()
