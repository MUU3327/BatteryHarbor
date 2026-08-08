import Darwin
import Foundation
import Security

final class ChargeHelperService: NSObject, ChargeHelperXPCProtocol {
    private let commandLock = NSLock()
    private var hasPassedHardwareVerification = false

    func probe(withReply reply: @escaping (Data) -> Void) {
        commandLock.lock()
        let payload = Self.currentProbe(hardwareVerificationPassed: hasPassedHardwareVerification)
        commandLock.unlock()
        reply((try? JSONEncoder().encode(payload)) ?? Data())
    }

    func execute(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        commandLock.lock()
        defer { commandLock.unlock() }

        let response: HelperCommandResponse
        do {
            let request = try JSONDecoder().decode(HelperCommandRequest.self, from: requestData)
            try Self.validate(request.actions)
            guard Self.currentProbe().writeOperationsEnabled else {
                throw HelperExecutionError.writeOperationsUnavailable
            }
            guard hasPassedHardwareVerification else {
                throw HelperExecutionError.hardwareVerificationRequired
            }

            let access = try SMCPrivilegedAccess()
            let planner = TahoeSMCWritePlanner()
            let steps = try request.actions.flatMap { try planner.steps(for: $0) }
            try VerifiedSMCTransactionExecutor(access: access).execute(steps)
            response = HelperCommandResponse(
                requestIdentifier: request.requestIdentifier,
                succeeded: true,
                message: "SMC 写入及回读验证成功",
                observedValues: try Self.observedValues(access)
            )
        } catch {
            let requestID = (try? JSONDecoder().decode(HelperCommandRequest.self, from: requestData))?
                .requestIdentifier ?? UUID()
            response = HelperCommandResponse(
                requestIdentifier: requestID,
                succeeded: false,
                message: error.localizedDescription,
                observedValues: [:]
            )
        }
        reply((try? JSONEncoder().encode(response)) ?? Data())
    }

    func verifyHardwareControl(withReply reply: @escaping (Data) -> Void) {
        commandLock.lock()
        defer { commandLock.unlock() }

        let payload: HardwareVerificationPayload
        do {
            guard Self.currentProbe().writeOperationsEnabled else {
                throw HelperExecutionError.writeOperationsUnavailable
            }
            let access = try SMCPrivilegedAccess()
            let outcome = try VerifiedSMCRestoreTester(access: access).verifyChargingToggle()
            hasPassedHardwareVerification = true
            payload = HardwareVerificationPayload(
                protocolVersion: ChargeHelperConstants.protocolVersion,
                succeeded: true,
                message: "CHTE 临时写入、回读、原值恢复及二次回读全部成功",
                key: outcome.key,
                originalValue: outcome.originalValue,
                temporaryValue: outcome.temporaryValue,
                restoredValue: outcome.restoredValue
            )
        } catch {
            payload = HardwareVerificationPayload(
                protocolVersion: ChargeHelperConstants.protocolVersion,
                succeeded: false,
                message: error.localizedDescription,
                key: "CHTE",
                originalValue: [],
                temporaryValue: [],
                restoredValue: []
            )
        }
        reply((try? JSONEncoder().encode(payload)) ?? Data())
    }

    static func currentProbe(hardwareVerificationPassed: Bool = false) -> HelperProbePayload {
        let effectiveUserID = geteuid()
        return HelperProbePayload(
            protocolVersion: ChargeHelperConstants.protocolVersion,
            processIdentifier: getpid(),
            effectiveUserID: effectiveUserID,
            isPrivileged: effectiveUserID == 0,
            writeOperationsEnabled: effectiveUserID == 0 && SMCPrivilegedAccess.isTahoeChargeBackendAvailable(),
            hardwareVerificationPassed: hardwareVerificationPassed
        )
    }

    private static func validate(_ actions: [ChargeHardwareAction]) throws {
        guard !actions.isEmpty, actions.count <= 2, Set(actions).count == actions.count else {
            throw HelperExecutionError.invalidActionSequence
        }
        let actionSet = Set(actions)
        guard !(actionSet.contains(.enableCharging) && actionSet.contains(.disableCharging)),
              !(actionSet.contains(.enableForceDischarge) && actionSet.contains(.disableForceDischarge))
        else { throw HelperExecutionError.invalidActionSequence }
    }

    private static func observedValues(_ access: SMCPrivilegedAccess) throws -> [String: [UInt8]] {
        ["CHTE": try access.read("CHTE"), "CHIE": try access.read("CHIE")]
    }
}

private enum HelperExecutionError: LocalizedError {
    case invalidActionSequence
    case writeOperationsUnavailable
    case hardwareVerificationRequired

    var errorDescription: String? {
        switch self {
        case .invalidActionSequence: "无效或相互冲突的充电动作"
        case .writeOperationsUnavailable: "当前 Helper、权限或 SMC 键不允许硬件写入"
        case .hardwareVerificationRequired: "root Helper 尚未通过本次启动的写入恢复安全自检"
        }
    }
}

final class ChargeHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    // Keep one service instance for the lifetime of the root helper. Hardware
    // verification is intentionally valid only until this helper restarts, but
    // it must survive the short-lived XPC connection used for the verification
    // request so later command connections can observe the unlocked state.
    private let service = ChargeHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ClientCodeValidator.accepts(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: ChargeHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private enum ClientCodeValidator {
    private static let expectedBundleIdentifier = "io.github.muu3327.batteryharbor"

    static func accepts(_ connection: NSXPCConnection) -> Bool {
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
        ] as CFDictionary

        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode,
              let guestInfo = signingInformation(for: guestCode),
              guestInfo[kSecCodeInfoIdentifier as String] as? String == expectedBundleIdentifier,
              let ownInfo = ownSigningInformation(),
              HelperClientSigningPolicy.identitiesMatch(
                guestTeamIdentifier: teamIdentifier(from: guestInfo),
                helperTeamIdentifier: teamIdentifier(from: ownInfo),
                guestLeafCertificate: leafCertificate(from: guestInfo),
                helperLeafCertificate: leafCertificate(from: ownInfo)
              )
        else { return false }

        var requirement: SecRequirement?
        let requirementText = "identifier \"\(expectedBundleIdentifier)\"" as CFString
        guard SecRequirementCreateWithString(requirementText, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }

        // `SecCodeCopyGuestWithAttributes` returns a dynamic SecCode for the
        // connected process. kSecCSCheckAllArchitectures is a static-code-only
        // validation flag and makes SecCodeCheckValidity fail with -67070.
        // Default validation still verifies the live process against the
        // identifier requirement; the Team ID or exact-certificate comparison
        // above pins the client to the same signing authority as this helper.
        let flags: SecCSFlags = []
        return SecCodeCheckValidity(guestCode, flags, requirement) == errSecSuccess
    }

    private static func ownSigningInformation() -> [String: Any]? {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess,
              let ownCode
        else { return nil }
        return signingInformation(for: ownCode)
    }

    private static func teamIdentifier(from information: [String: Any]) -> String? {
        information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func leafCertificate(from information: [String: Any]) -> Data? {
        guard let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }

    private static func signingInformation(for code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess
        else { return nil }
        return information as? [String: Any]
    }
}

@main
enum BatteryHarborHelperMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let payload = ChargeHelperService.currentProbe()
            guard let data = try? JSONEncoder().encode(payload),
                  let output = String(data: data, encoding: .utf8)
            else { exit(1) }
            print(output)
            return
        }

        let delegate = ChargeHelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: ChargeHelperConstants.machServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
        _ = delegate
    }
}
