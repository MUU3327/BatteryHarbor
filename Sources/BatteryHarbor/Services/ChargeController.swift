import Foundation
import ServiceManagement

enum ChargeControlState: Equatable, Sendable {
    case unavailable(reason: String)
    case ready
    case applying
    case failed(message: String)

    var isAvailable: Bool {
        if case .ready = self { return true }
        return false
    }
}

protocol ChargeControlling: Sendable {
    func availability() async -> ChargeControlState
    func helperRegistrationStatus() async -> HelperRegistrationStatus
    func registerHelper() async throws
    func unregisterHelper() async throws
    func probeHelper() async throws -> HelperProbePayload
    func verifyHardwareControl() async throws -> HardwareVerificationPayload
    func openApprovalSettings() async
    func setChargeLimit(_ percentage: Int) async throws
    func setChargingPaused(_ paused: Bool) async throws
    func temporaryFullCharge() async throws
    func applyHardwareActions(_ actions: [ChargeHardwareAction]) async throws
}

/// Phase-one implementation. The public app never writes battery controller values directly.
/// A signed, authenticated XPC helper will replace this implementation in phase two.
struct UnavailableChargeController: ChargeControlling {
    func availability() async -> ChargeControlState {
        .unavailable(reason: "需要安装特权充电控制模块")
    }

    func helperRegistrationStatus() async -> HelperRegistrationStatus { .notFound }

    func registerHelper() async throws { throw ChargeControlError.helperUnavailable }

    func unregisterHelper() async throws { throw ChargeControlError.helperUnavailable }

    func probeHelper() async throws -> HelperProbePayload { throw ChargeControlError.helperUnavailable }

    func verifyHardwareControl() async throws -> HardwareVerificationPayload {
        throw ChargeControlError.helperUnavailable
    }

    func openApprovalSettings() async {}

    func setChargeLimit(_ percentage: Int) async throws {
        throw ChargeControlError.helperUnavailable
    }

    func setChargingPaused(_ paused: Bool) async throws {
        throw ChargeControlError.helperUnavailable
    }

    func temporaryFullCharge() async throws {
        throw ChargeControlError.helperUnavailable
    }

    func applyHardwareActions(_ actions: [ChargeHardwareAction]) async throws {
        throw ChargeControlError.helperUnavailable
    }
}

struct SystemChargeController: ChargeControlling {
    private let capabilityProbe: any HardwareCapabilityProbing

    init(capabilityProbe: any HardwareCapabilityProbing = HardwareCapabilityProbe()) {
        self.capabilityProbe = capabilityProbe
    }

    func availability() async -> ChargeControlState {
        let capabilities = capabilityProbe.probe()
        guard capabilities.isAppleSilicon else {
            return .unavailable(reason: "当前预览版仅验证 Apple Silicon")
        }

        switch await helperRegistrationStatus() {
        case .enabled:
            do {
                let probe = try await probeHelper()
                guard probe.isPrivileged else {
                    return .unavailable(reason: "控制模块未以 root 权限运行")
                }
                guard probe.writeOperationsEnabled else {
                    return .unavailable(reason: "控制模块未检测到受支持的 CHTE/CHIE 写入后端")
                }
                guard probe.hardwareVerificationPassed else {
                    return .unavailable(reason: "控制模块等待执行写入、回读和原值恢复安全自检")
                }
                return .ready
            } catch {
                return .unavailable(reason: error.localizedDescription)
            }
        case .requiresApproval:
            return .unavailable(reason: "控制模块等待管理员在登录项设置中批准")
        case .notRegistered:
            return .unavailable(reason: "控制模块已随 App 打包，尚未注册")
        case .notFound:
            return .unavailable(reason: "ServiceManagement 尚未识别控制模块，可尝试注册以获取详细结果")
        case .unknown:
            return .unavailable(reason: "无法识别控制模块状态")
        }
    }

    func helperRegistrationStatus() async -> HelperRegistrationStatus {
        let service = SMAppService.daemon(plistName: ChargeHelperConstants.launchDaemonPlistName)
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    func registerHelper() async throws {
        let legacyService = SMAppService.daemon(
            plistName: ChargeHelperConstants.legacyLaunchDaemonPlistName
        )
        if legacyService.status == .enabled || legacyService.status == .requiresApproval {
            try await legacyService.unregister()
        }

        try SMAppService.daemon(plistName: ChargeHelperConstants.launchDaemonPlistName).register()
    }

    func unregisterHelper() async throws {
        let currentService = SMAppService.daemon(
            plistName: ChargeHelperConstants.launchDaemonPlistName
        )
        if currentService.status == .enabled || currentService.status == .requiresApproval {
            try await currentService.unregister()
        }

        let legacyService = SMAppService.daemon(
            plistName: ChargeHelperConstants.legacyLaunchDaemonPlistName
        )
        if legacyService.status == .enabled || legacyService.status == .requiresApproval {
            try await legacyService.unregister()
        }
    }

    func probeHelper() async throws -> HelperProbePayload {
        guard await helperRegistrationStatus() == .enabled else {
            throw ChargeControlError.helperUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion = HelperProbeCompletion(continuation)
            let connection = NSXPCConnection(machServiceName: ChargeHelperConstants.machServiceName)
            connection.remoteObjectInterface = NSXPCInterface(with: ChargeHelperXPCProtocol.self)
            connection.interruptionHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInterrupted)
            }
            connection.invalidationHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInvalidated)
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                completion.resume(throwing: error)
            }) as? ChargeHelperXPCProtocol else {
                connection.invalidate()
                completion.resume(throwing: ChargeControlError.helperUnavailable)
                return
            }

            proxy.probe { data in
                defer { connection.invalidate() }
                do {
                    let payload = try JSONDecoder().decode(HelperProbePayload.self, from: data)
                    guard payload.protocolVersion == ChargeHelperConstants.protocolVersion else {
                        throw ChargeControlError.helperProtocolMismatch
                    }
                    completion.resume(returning: payload)
                } catch {
                    completion.resume(throwing: error)
                }
            }
        }
    }

    func openApprovalSettings() async {
        SMAppService.openSystemSettingsLoginItems()
    }

    func verifyHardwareControl() async throws -> HardwareVerificationPayload {
        guard await helperRegistrationStatus() == .enabled else {
            throw ChargeControlError.helperUnavailable
        }
        let snapshot = BatteryReader().read()
        guard snapshot.isPresent, snapshot.powerSource == .adapter else {
            throw ChargeControlError.adapterRequiredForVerification
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion = HardwareVerificationCompletion(continuation)
            let connection = NSXPCConnection(machServiceName: ChargeHelperConstants.machServiceName)
            connection.remoteObjectInterface = NSXPCInterface(with: ChargeHelperXPCProtocol.self)
            connection.interruptionHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInterrupted)
            }
            connection.invalidationHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInvalidated)
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                completion.resume(throwing: error)
            }) as? ChargeHelperXPCProtocol else {
                connection.invalidate()
                completion.resume(throwing: ChargeControlError.helperUnavailable)
                return
            }

            proxy.verifyHardwareControl { data in
                defer { connection.invalidate() }
                do {
                    let payload = try JSONDecoder().decode(HardwareVerificationPayload.self, from: data)
                    guard payload.protocolVersion == ChargeHelperConstants.protocolVersion else {
                        throw ChargeControlError.helperProtocolMismatch
                    }
                    guard payload.succeeded else {
                        throw ChargeControlError.helperRejected(message: payload.message)
                    }
                    guard payload.originalValue == payload.restoredValue,
                          !payload.originalValue.isEmpty,
                          payload.originalValue != payload.temporaryValue
                    else { throw ChargeControlError.hardwareVerificationInvalid }
                    completion.resume(returning: payload)
                } catch {
                    completion.resume(throwing: error)
                }
            }
        }
    }

    func setChargeLimit(_ percentage: Int) async throws {
        guard (50...100).contains(percentage) else {
            throw ChargeControlError.invalidChargeLimit
        }
        let snapshot = BatteryReader().read()
        guard snapshot.isPresent, snapshot.powerSource == .adapter else { return }
        if snapshot.percentage >= percentage {
            _ = try await executeHelperActions([.disableForceDischarge, .disableCharging])
        } else if snapshot.percentage <= percentage - 3 {
            _ = try await executeHelperActions([.disableForceDischarge, .enableCharging])
        }
    }

    func setChargingPaused(_ paused: Bool) async throws {
        let actions: [ChargeHardwareAction] = paused
            ? [.disableForceDischarge, .disableCharging]
            : [.disableForceDischarge, .enableCharging]
        _ = try await executeHelperActions(actions)
    }

    func temporaryFullCharge() async throws {
        _ = try await executeHelperActions([.disableForceDischarge, .enableCharging])
    }

    func applyHardwareActions(_ actions: [ChargeHardwareAction]) async throws {
        guard !actions.isEmpty else { return }
        _ = try await executeHelperActions(actions)
    }

    private func executeHelperActions(_ actions: [ChargeHardwareAction]) async throws -> HelperCommandResponse {
        guard await helperRegistrationStatus() == .enabled else {
            throw ChargeControlError.helperUnavailable
        }
        let request = HelperCommandRequest(requestIdentifier: UUID(), actions: actions)
        let requestData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            let completion = HelperCommandCompletion(continuation)
            let connection = NSXPCConnection(machServiceName: ChargeHelperConstants.machServiceName)
            connection.remoteObjectInterface = NSXPCInterface(with: ChargeHelperXPCProtocol.self)
            connection.interruptionHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInterrupted)
            }
            connection.invalidationHandler = {
                completion.resume(throwing: ChargeControlError.helperConnectionInvalidated)
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                completion.resume(throwing: error)
            }) as? ChargeHelperXPCProtocol else {
                connection.invalidate()
                completion.resume(throwing: ChargeControlError.helperUnavailable)
                return
            }

            proxy.execute(requestData) { data in
                defer { connection.invalidate() }
                do {
                    let response = try JSONDecoder().decode(HelperCommandResponse.self, from: data)
                    guard response.requestIdentifier == request.requestIdentifier else {
                        throw ChargeControlError.helperResponseMismatch
                    }
                    guard response.succeeded else {
                        throw ChargeControlError.helperRejected(message: response.message)
                    }
                    completion.resume(returning: response)
                } catch {
                    completion.resume(throwing: error)
                }
            }
        }
    }
}

enum ChargeControlError: LocalizedError {
    case helperUnavailable
    case helperConnectionInterrupted
    case helperConnectionInvalidated
    case helperProtocolMismatch
    case helperResponseMismatch
    case helperRejected(message: String)
    case invalidChargeLimit
    case writeOperationsLocked
    case adapterRequiredForVerification
    case hardwareVerificationInvalid

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "特权充电控制模块尚未安装"
        case .helperConnectionInterrupted: "与控制模块的连接被中断"
        case .helperConnectionInvalidated: "控制模块连接已失效"
        case .helperProtocolMismatch: "控制模块协议版本不匹配"
        case .helperResponseMismatch: "控制模块返回了不匹配的请求标识"
        case let .helperRejected(message): message
        case .invalidChargeLimit: "充电上限必须在 50%–100% 之间"
        case .writeOperationsLocked: "硬件写入仍处于安全锁定状态"
        case .adapterRequiredForVerification: "安全自检前必须连接电源适配器"
        case .hardwareVerificationInvalid: "安全自检没有返回有效的原值恢复证据"
        }
    }
}

private final class HardwareVerificationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HardwareVerificationPayload, Error>?

    init(_ continuation: CheckedContinuation<HardwareVerificationPayload, Error>) {
        self.continuation = continuation
    }

    func resume(returning payload: HardwareVerificationPayload) {
        takeContinuation()?.resume(returning: payload)
    }

    func resume(throwing error: any Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<HardwareVerificationPayload, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

private final class HelperCommandCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HelperCommandResponse, Error>?

    init(_ continuation: CheckedContinuation<HelperCommandResponse, Error>) {
        self.continuation = continuation
    }

    func resume(returning response: HelperCommandResponse) {
        takeContinuation()?.resume(returning: response)
    }

    func resume(throwing error: any Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<HelperCommandResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

private final class HelperProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HelperProbePayload, Error>?

    init(_ continuation: CheckedContinuation<HelperProbePayload, Error>) {
        self.continuation = continuation
    }

    func resume(returning payload: HelperProbePayload) {
        takeContinuation()?.resume(returning: payload)
    }

    func resume(throwing error: any Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<HelperProbePayload, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}
