import Foundation
import IOKit

/// Root-only SMC transport. The app target does not compile this file.
final class SMCPrivilegedAccess: SMCByteAccess {
    private static let kernelSelector: UInt32 = 2
    private let connection: io_connect_t

    init() throws {
        guard geteuid() == 0 else { throw PrivilegedSMCError.rootRequired }
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
        let (keyCode, info) = try keyInfo(key)
        let dataSize = info.keyInfo.dataSize
        guard dataSize > 0, dataSize <= 32 else { throw SMCReadError.invalidDataSize(dataSize) }

        var request = SMCParamStruct()
        request.key = keyCode
        request.keyInfo.dataSize = dataSize
        request.data8 = SMCCommand.readBytes.rawValue
        let output = try call(request)
        try validateFirmwareResult(output.result)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(dataSize))) }
    }

    func write(_ key: String, value: [UInt8]) throws {
        let (keyCode, info) = try keyInfo(key)
        guard info.keyInfo.dataSize == value.count else {
            throw SMCWriteTransactionError.unexpectedDataSize(
                key: key,
                expected: Int(info.keyInfo.dataSize),
                actual: value.count
            )
        }

        var request = SMCParamStruct()
        request.key = keyCode
        request.keyInfo.dataSize = info.keyInfo.dataSize
        request.data8 = SMCCommand.writeBytes.rawValue
        request.bytes = Self.byteTuple(value)
        let output = try call(request)
        try validateFirmwareResult(output.result)
    }

    static func isTahoeChargeBackendAvailable() -> Bool {
        guard geteuid() == 0, let access = try? SMCPrivilegedAccess() else { return false }
        return (try? access.read("CHTE").count) == 4
            && (try? access.read("CHIE").count) == 1
    }

    private func keyInfo(_ key: String) throws -> (UInt32, SMCParamStruct) {
        let keyCode = try SMCReadOnlyClient.fourCharacterCode(key)
        var request = SMCParamStruct()
        request.key = keyCode
        request.data8 = SMCCommand.readKeyInfo.rawValue
        let output = try call(request)
        try validateFirmwareResult(output.result)
        return (keyCode, output)
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

    private static func byteTuple(_ value: [UInt8]) -> SMCParamStruct.Bytes32 {
        var bytes = value
        if bytes.count < 32 { bytes.append(contentsOf: repeatElement(0, count: 32 - bytes.count)) }
        if bytes.count > 32 { bytes = Array(bytes.prefix(32)) }
        return (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
            bytes[16], bytes[17], bytes[18], bytes[19], bytes[20], bytes[21], bytes[22], bytes[23],
            bytes[24], bytes[25], bytes[26], bytes[27], bytes[28], bytes[29], bytes[30], bytes[31]
        )
    }
}

enum PrivilegedSMCError: LocalizedError {
    case rootRequired

    var errorDescription: String? { "SMC 写入必须由 root Helper 执行" }
}
