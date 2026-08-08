import Foundation
import IOKit

struct ChargeCapabilities: Equatable, Sendable {
    enum BaselineBackend: String, Sendable {
        case nativeChargeLimit
        case privilegedSMC
        case unsupported

        var displayName: String {
            switch self {
            case .nativeChargeLimit: L10n.text("系统原生充电上限")
            case .privilegedSMC: L10n.text("特权 SMC 控制")
            case .unsupported: L10n.text("暂不支持")
            }
        }
    }

    let modelIdentifier: String
    let firmwareVersion: String
    let isAppleSilicon: Bool
    let hasAppleSMCService: Bool
    let supportsNativeChargeLimit: Bool
    let baselineBackend: BaselineBackend
    let smcChargeKeys: SMCChargeKeyCapabilities

    var nativeLimitDescription: String {
        supportsNativeChargeLimit ? "80%–100%" : L10n.text("不可用")
    }
}

protocol HardwareCapabilityProbing: Sendable {
    func probe() -> ChargeCapabilities
}

struct HardwareCapabilityProbe: HardwareCapabilityProbing {
    func probe() -> ChargeCapabilities {
        let model = registryString(path: "IODeviceTree:/", key: "model") ?? L10n.text("未知机型")
        let firmware = registryString(path: "IODeviceTree:/chosen", key: "firmware-version")?
            .replacingOccurrences(of: "mBoot-", with: "") ?? L10n.text("未知固件")
        let smcService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        let hasSMC = smcService != 0
        if smcService != 0 { IOObjectRelease(smcService) }

        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif

        let nativeLimit = Self.supportsNativeChargeLimit(on: ProcessInfo.processInfo.operatingSystemVersion)
        let smcChargeKeys = SMCChargeCapabilityProbe().probe()
        let backend: ChargeCapabilities.BaselineBackend
        if isAppleSilicon && nativeLimit {
            backend = .nativeChargeLimit
        } else if hasSMC {
            backend = .privilegedSMC
        } else {
            backend = .unsupported
        }

        return ChargeCapabilities(
            modelIdentifier: model,
            firmwareVersion: firmware,
            isAppleSilicon: isAppleSilicon,
            hasAppleSMCService: hasSMC,
            supportsNativeChargeLimit: isAppleSilicon && nativeLimit,
            baselineBackend: backend,
            smcChargeKeys: smcChargeKeys
        )
    }

    static func supportsNativeChargeLimit(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 26
            || (version.majorVersion == 26 && version.minorVersion >= 4)
    }

    private func registryString(path: String, key: String) -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let rawValue = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        else { return nil }

        if let value = rawValue as? String { return value }
        guard let data = rawValue as? Data else { return nil }
        let bytes = data.prefix { $0 != 0 }
        return String(data: Data(bytes), encoding: .utf8)
    }
}
