import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("失败 / Failed: \(message)\n".utf8))
        exit(1)
    }
}

let wrapped = NSNumber(value: UInt64.max - 301)
require(signedInt(wrapped) == -302, "负电流注册表数值转换错误")

let adapterSnapshot = BatterySnapshot(
    percentage: 80,
    isCharging: false,
    isFullyCharged: false,
    isPresent: true,
    powerSource: .adapter
)
require(adapterSnapshot.stateText == L10n.text("已接电源，未充电"), "电源状态文案错误 / Incorrect power-state text")

let live = BatteryReader().read()
require(live.isPresent, "未读取到内置电池")
require((0...100).contains(live.percentage), "电量百分比越界")
require(live.voltageVolts != nil, "未读取到电池电压")
require(live.powerWatts != nil, "未计算出实时功率")

let capabilities = HardwareCapabilityProbe().probe()
require(capabilities.isAppleSilicon, "当前硬件不是 Apple Silicon")
require(capabilities.hasAppleSMCService, "未检测到 AppleSMC 服务")
require(capabilities.modelIdentifier != "未知机型", "未读取到机型标识")
require(capabilities.firmwareVersion != "未知固件", "未读取到固件版本")

print(
    "通过 / Passed: \(capabilities.modelIdentifier), 固件 / firmware \(capabilities.firmwareVersion), "
        + "电量 / charge \(live.percentage)%, 功率 / power \(live.powerWatts ?? 0) W, "
        + "循环 / cycles \(live.cycleCount ?? 0)"
)
