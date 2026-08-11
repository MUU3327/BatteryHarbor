import Foundation
import IOKit
import IOKit.ps

protocol BatteryReading: Sendable {
    func read() -> BatterySnapshot
}

struct BatteryReader: BatteryReading {
    func read() -> BatterySnapshot {
        var snapshot = readPowerSourceDescription()
        guard let registry = readRegistryProperties() else { return snapshot }

        snapshot.isPresent = bool(registry["BatteryInstalled"]) ?? snapshot.isPresent
        snapshot.percentage = int(registry["CurrentCapacity"]) ?? snapshot.percentage
        snapshot.isCharging = bool(registry["IsCharging"]) ?? snapshot.isCharging
        snapshot.isFullyCharged = bool(registry["FullyCharged"]) ?? snapshot.isFullyCharged
        snapshot.temperatureCelsius = int(registry["Temperature"]).map { Double($0) / 100 }
        snapshot.voltageVolts = int(registry["Voltage"]).map { Double($0) / 1_000 }
        snapshot.currentAmps = signedInt(registry["Amperage"]).map { Double($0) / 1_000 }
        snapshot.cycleCount = int(registry["CycleCount"])
        snapshot.designCapacityMAh = int(registry["DesignCapacity"])
        snapshot.fullChargeCapacityMAh = int(registry["AppleRawMaxCapacity"])
            ?? int(registry["NominalChargeCapacity"])
        snapshot.remainingCapacityMAh = int(registry["AppleRawCurrentCapacity"])

        if let design = snapshot.designCapacityMAh,
           let full = snapshot.fullChargeCapacityMAh,
           design > 0 {
            snapshot.healthPercentage = min(100, Double(full) / Double(design) * 100)
        }

        if let telemetry = registry["PowerTelemetryData"] as? [String: Any] {
            snapshot.powerWatts = signedInt(telemetry["BatteryPower"]).map { Double($0) / 1_000 }
            snapshot.adapterInputWatts = signedInt(telemetry["SystemPowerIn"]).map { Double($0) / 1_000 }
            snapshot.adapterVoltageVolts = int(telemetry["SystemVoltageIn"]).map { Double($0) / 1_000 }
            snapshot.adapterCurrentAmps = signedInt(telemetry["SystemCurrentIn"]).map { Double($0) / 1_000 }
            snapshot.systemLoadWatts = signedInt(telemetry["SystemLoad"]).map { Double($0) / 1_000 }
            snapshot.adapterEfficiencyLossWatts = signedInt(telemetry["AdapterEfficiencyLoss"])
                .map { Double($0) / 1_000 }
        } else if let voltage = snapshot.voltageVolts,
                  let current = snapshot.currentAmps {
            snapshot.powerWatts = voltage * current
        }

        if let adapter = (registry["AdapterDetails"] as? [String: Any])
            ?? (registry["AppleRawAdapterDetails"] as? [[String: Any]])?.first {
            applyAdapterDetails(adapter, to: &snapshot)
        }

        // IOPowerSources often publishes the negotiated adapter identity before
        // AppleSmartBattery has refreshed its telemetry dictionary. Using this
        // public API makes the newly connected/negotiating state visible sooner.
        if snapshot.powerSource == .adapter,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            applyAdapterDetails(adapter, to: &snapshot)
        }

        snapshot.timestamp = Date()
        return snapshot
    }

    private func applyAdapterDetails(_ adapter: [String: Any], to snapshot: inout BatterySnapshot) {
        snapshot.adapterRatedWatts = snapshot.adapterRatedWatts ?? int(adapter["Watts"])
        snapshot.adapterVoltageVolts = snapshot.adapterVoltageVolts
            ?? int(adapter["AdapterVoltage"]).map { Double($0) / 1_000 }
        if snapshot.adapterCurrentAmps == nil,
           let input = snapshot.adapterInputWatts,
           let voltage = snapshot.adapterVoltageVolts,
           voltage > 0 {
            snapshot.adapterCurrentAmps = input / voltage
        }
    }

    private func readPowerSourceDescription() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unavailable }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let current = int(description[kIOPSCurrentCapacityKey]) ?? 0
            let maximum = int(description[kIOPSMaxCapacityKey]) ?? 100
            let percentage = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
            let state = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = bool(description[kIOPSIsChargingKey]) ?? false
            let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let timeRemaining = int(description[timeKey]).flatMap { $0 > 0 ? $0 : nil }

            return BatterySnapshot(
                percentage: percentage,
                isCharging: isCharging,
                isFullyCharged: bool(description[kIOPSIsChargedKey]) ?? false,
                isPresent: bool(description[kIOPSIsPresentKey]) ?? true,
                powerSource: state == kIOPSACPowerValue ? .adapter : .battery,
                timeRemainingMinutes: timeRemaining
            )
        }

        return .unavailable
    }

    private func readRegistryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return properties
    }
}

func int(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber: return number.intValue
    case let value as Int: return value
    default: return nil
    }
}

func signedInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return int(value) }
    return Int(Int64(bitPattern: number.uint64Value))
}

func bool(_ value: Any?) -> Bool? {
    switch value {
    case let number as NSNumber: return number.boolValue
    case let value as Bool: return value
    default: return nil
    }
}
