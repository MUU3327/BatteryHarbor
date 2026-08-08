import Foundation
import IOKit

enum SMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

enum SMCReadError: LocalizedError {
    case serviceUnavailable
    case connectionFailed(kern_return_t)
    case invalidKey
    case invalidDataSize(UInt32)
    case ioKit(kern_return_t)
    case firmware(UInt8)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable: "未找到 AppleSMC 服务"
        case let .connectionFailed(code): "无法连接 AppleSMC（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case .invalidKey: "SMC 键必须是 4 个 ASCII 字符"
        case let .invalidDataSize(size): "SMC 返回了无效长度：\(size)"
        case let .ioKit(code): "SMC I/O 错误（0x\(String(UInt32(bitPattern: code), radix: 16))）"
        case let .firmware(code): "SMC 固件拒绝读取（0x\(String(code, radix: 16))）"
        }
    }
}

struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PowerLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var memory: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var attributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var powerLimit = PowerLimit()
    var keyInfo = KeyInfo()
    var alignmentPadding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// Read-only interface to AppleSMC. This type deliberately exposes no write command.
final class SMCReadOnlyClient {
    private static let kernelSelector: UInt32 = 2
    private let connection: io_connect_t

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCReadError.serviceUnavailable }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCReadError.connectionFailed(result) }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func read(_ key: String) throws -> [UInt8] {
        let keyCode = try Self.fourCharacterCode(key)

        var infoRequest = SMCParamStruct()
        infoRequest.key = keyCode
        infoRequest.data8 = SMCCommand.readKeyInfo.rawValue
        let info = try call(infoRequest)
        try validateFirmwareResult(info.result)

        let dataSize = info.keyInfo.dataSize
        guard dataSize > 0, dataSize <= 32 else { throw SMCReadError.invalidDataSize(dataSize) }

        var readRequest = SMCParamStruct()
        readRequest.key = keyCode
        readRequest.keyInfo.dataSize = dataSize
        readRequest.data8 = SMCCommand.readBytes.rawValue
        let output = try call(readRequest)
        try validateFirmwareResult(output.result)

        return withUnsafeBytes(of: output.bytes) { buffer in
            Array(buffer.prefix(Int(dataSize)))
        }
    }

    static func fourCharacterCode(_ key: String) throws -> UInt32 {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else {
            throw SMCReadError.invalidKey
        }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            Self.kernelSelector,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else { throw SMCReadError.ioKit(result) }
        return output
    }

    private func validateFirmwareResult(_ result: UInt8) throws {
        guard result == 0 else { throw SMCReadError.firmware(result) }
    }
}

struct SMCChargeKeyCapabilities: Equatable, Sendable {
    enum ChargingPath: String, Sendable {
        case tahoe
        case legacy
        case unavailable

        var displayName: String {
            switch self {
            case .tahoe: "CHTE（Tahoe）"
            case .legacy: "CH0B + CH0C（旧版）"
            case .unavailable: "未检测到"
            }
        }
    }

    let chargingPath: ChargingPath
    let dischargeKey: String?
    let chargingRawValue: [UInt8]?
    let dischargeRawValue: [UInt8]?

    static let unavailable = Self(
        chargingPath: .unavailable,
        dischargeKey: nil,
        chargingRawValue: nil,
        dischargeRawValue: nil
    )
}

struct SMCChargeCapabilityProbe {
    func probe() -> SMCChargeKeyCapabilities {
        guard let client = try? SMCReadOnlyClient() else { return .unavailable }

        let tahoeValue = try? client.read("CHTE")
        let legacyB = try? client.read("CH0B")
        let legacyC = try? client.read("CH0C")

        let chargingPath: SMCChargeKeyCapabilities.ChargingPath
        let chargingValue: [UInt8]?
        if let tahoeValue {
            chargingPath = .tahoe
            chargingValue = tahoeValue
        } else if let legacyB, legacyC != nil {
            chargingPath = .legacy
            chargingValue = legacyB
        } else {
            chargingPath = .unavailable
            chargingValue = nil
        }

        for key in ["CHIE", "CH0J", "CH0I"] {
            if let value = try? client.read(key) {
                return SMCChargeKeyCapabilities(
                    chargingPath: chargingPath,
                    dischargeKey: key,
                    chargingRawValue: chargingValue,
                    dischargeRawValue: value
                )
            }
        }

        return SMCChargeKeyCapabilities(
            chargingPath: chargingPath,
            dischargeKey: nil,
            chargingRawValue: chargingValue,
            dischargeRawValue: nil
        )
    }
}
