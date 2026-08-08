import Foundation

struct SMCWriteStep: Equatable, Sendable {
    let key: String
    let value: [UInt8]
}

enum SMCWriteTransactionError: LocalizedError, Equatable {
    case unsupportedAction(ChargeHardwareAction)
    case unexpectedDataSize(key: String, expected: Int, actual: Int)
    case verificationFailed(key: String)
    case unsafeOriginalValue(key: String)
    case restorationFailed(key: String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAction(action): "当前 SMC 配置不支持动作：\(action.rawValue)"
        case let .unexpectedDataSize(key, expected, actual):
            "SMC 键 \(key) 长度异常（预期 \(expected)，实际 \(actual)）"
        case let .verificationFailed(key): "SMC 键 \(key) 写后验证失败，已尝试回滚"
        case let .unsafeOriginalValue(key): "SMC 键 \(key) 的原始值不在安全自检白名单内"
        case let .restorationFailed(key): "SMC 键 \(key) 未能恢复原值，硬件控制保持锁定"
        }
    }
}

struct SMCRestoreVerificationOutcome: Equatable, Sendable {
    let key: String
    let originalValue: [UInt8]
    let temporaryValue: [UInt8]
    let restoredValue: [UInt8]
}

/// Performs one deliberately short, reversible CHTE toggle. The original value is always restored
/// and verified before a successful result can be returned.
struct VerifiedSMCRestoreTester {
    private let access: any SMCByteAccess

    init(access: any SMCByteAccess) {
        self.access = access
    }

    func verifyChargingToggle() throws -> SMCRestoreVerificationOutcome {
        let key = "CHTE"
        let enabled: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let disabled: [UInt8] = [0x01, 0x00, 0x00, 0x00]
        let original = try access.read(key)
        guard original == enabled || original == disabled else {
            throw SMCWriteTransactionError.unsafeOriginalValue(key: key)
        }
        let temporary = original == enabled ? disabled : enabled
        var temporaryWriteAttempted = false

        do {
            temporaryWriteAttempted = true
            try access.write(key, value: temporary)
            guard try access.read(key) == temporary else {
                throw SMCWriteTransactionError.verificationFailed(key: key)
            }
            try access.write(key, value: original)
            temporaryWriteAttempted = false
            let restored = try access.read(key)
            guard restored == original else {
                throw SMCWriteTransactionError.restorationFailed(key: key)
            }
            return SMCRestoreVerificationOutcome(
                key: key,
                originalValue: original,
                temporaryValue: temporary,
                restoredValue: restored
            )
        } catch {
            if temporaryWriteAttempted {
                do {
                    try access.write(key, value: original)
                    guard try access.read(key) == original else {
                        throw SMCWriteTransactionError.restorationFailed(key: key)
                    }
                } catch {
                    throw SMCWriteTransactionError.restorationFailed(key: key)
                }
            }
            throw error
        }
    }
}

/// Only the key/value combinations verified for Tahoe-era Apple Silicon are expressible here.
struct TahoeSMCWritePlanner {
    func steps(for action: ChargeHardwareAction) throws -> [SMCWriteStep] {
        switch action {
        case .enableCharging:
            [
                SMCWriteStep(key: "CHIE", value: [0x00]),
                SMCWriteStep(key: "CHTE", value: [0x00, 0x00, 0x00, 0x00])
            ]
        case .disableCharging:
            [SMCWriteStep(key: "CHTE", value: [0x01, 0x00, 0x00, 0x00])]
        case .enableForceDischarge:
            [
                SMCWriteStep(key: "CHTE", value: [0x01, 0x00, 0x00, 0x00]),
                SMCWriteStep(key: "CHIE", value: [0x08])
            ]
        case .disableForceDischarge:
            [SMCWriteStep(key: "CHIE", value: [0x00])]
        }
    }
}

protocol SMCByteAccess: AnyObject {
    func read(_ key: String) throws -> [UInt8]
    func write(_ key: String, value: [UInt8]) throws
}

struct VerifiedSMCTransactionExecutor {
    private static let allowedSizes = ["CHTE": 4, "CHIE": 1]
    private let access: any SMCByteAccess

    init(access: any SMCByteAccess) {
        self.access = access
    }

    func execute(_ steps: [SMCWriteStep]) throws {
        var originals: [String: [UInt8]] = [:]
        var touchedKeys: [String] = []

        do {
            for step in steps {
                let expectedSize = try validatedSize(for: step)
                if originals[step.key] == nil {
                    let original = try access.read(step.key)
                    guard original.count == expectedSize else {
                        throw SMCWriteTransactionError.unexpectedDataSize(
                            key: step.key,
                            expected: expectedSize,
                            actual: original.count
                        )
                    }
                    originals[step.key] = original
                }

                try access.write(step.key, value: step.value)
                touchedKeys.append(step.key)
                guard try access.read(step.key) == step.value else {
                    throw SMCWriteTransactionError.verificationFailed(key: step.key)
                }
            }
        } catch {
            rollback(touchedKeys: touchedKeys, originals: originals)
            throw error
        }
    }

    private func validatedSize(for step: SMCWriteStep) throws -> Int {
        guard let expectedSize = Self.allowedSizes[step.key], step.value.count == expectedSize else {
            throw SMCWriteTransactionError.unexpectedDataSize(
                key: step.key,
                expected: Self.allowedSizes[step.key] ?? 0,
                actual: step.value.count
            )
        }
        return expectedSize
    }

    private func rollback(touchedKeys: [String], originals: [String: [UInt8]]) {
        for key in touchedKeys.reversed() {
            guard let original = originals[key] else { continue }
            try? access.write(key, value: original)
        }
    }
}
