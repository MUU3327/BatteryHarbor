import Foundation

struct ChargePolicyInput: Equatable, Sendable {
    let percentage: Int
    let isAdapterConnected: Bool
    let isChargingEnabled: Bool?
    let isForceDischargeEnabled: Bool?
    let upperLimit: Int
    let lowerLimitDelta: Int
    let isPaused: Bool
    let temporaryFullChargeUntil: Date?
    let now: Date
}

struct ChargePolicy {
    func actions(for input: ChargePolicyInput) -> [ChargeHardwareAction] {
        guard input.isAdapterConnected else {
            return input.isForceDischargeEnabled == true ? [.disableForceDischarge] : []
        }

        if let deadline = input.temporaryFullChargeUntil, deadline > input.now {
            var actions: [ChargeHardwareAction] = []
            if input.isForceDischargeEnabled == true { actions.append(.disableForceDischarge) }
            if input.percentage < 100, input.isChargingEnabled != true { actions.append(.enableCharging) }
            return actions
        }

        if input.isPaused {
            var actions: [ChargeHardwareAction] = []
            if input.isForceDischargeEnabled == true { actions.append(.disableForceDischarge) }
            if input.isChargingEnabled != false { actions.append(.disableCharging) }
            return actions
        }

        let upperLimit = min(max(input.upperLimit, 50), 100)
        let lowerLimit = max(5, upperLimit - min(max(input.lowerLimitDelta, 1), 20))

        // Force discharge remains available to the explicit calibration
        // workflow, but normal charge-limit maintenance never enables it.
        if input.isForceDischargeEnabled == true {
            return [.disableForceDischarge]
        }

        if input.percentage >= upperLimit, input.isChargingEnabled != false {
            return [.disableCharging]
        }

        if input.percentage <= lowerLimit, input.isChargingEnabled != true {
            return [.enableCharging]
        }

        return []
    }
}

struct TemperatureProtectionDecision: Equatable, Sendable {
    let isActive: Bool
    let actions: [ChargeHardwareAction]
}

struct BatteryTemperatureProtection {
    func decision(
        temperatureCelsius: Double?,
        threshold: Double,
        resumeDelta: Double = 3,
        wasActive: Bool,
        isEnabled: Bool
    ) -> TemperatureProtectionDecision {
        guard isEnabled else { return TemperatureProtectionDecision(isActive: false, actions: []) }
        let threshold = min(max(threshold, 30), 50)
        let resumeTemperature = threshold - min(max(resumeDelta, 1), 10)

        guard let temperatureCelsius else {
            return TemperatureProtectionDecision(
                isActive: wasActive,
                actions: wasActive ? [.disableForceDischarge, .disableCharging] : []
            )
        }
        if wasActive, temperatureCelsius > resumeTemperature {
            return TemperatureProtectionDecision(
                isActive: true,
                actions: [.disableForceDischarge, .disableCharging]
            )
        }
        if temperatureCelsius >= threshold {
            return TemperatureProtectionDecision(
                isActive: true,
                actions: [.disableForceDischarge, .disableCharging]
            )
        }
        return TemperatureProtectionDecision(isActive: false, actions: [])
    }
}
