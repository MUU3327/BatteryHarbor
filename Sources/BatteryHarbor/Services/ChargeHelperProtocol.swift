import Foundation

/// Defines the only signing relationships that may cross the privileged XPC
/// boundary. Apple-issued development and distribution identities are pinned
/// by Team ID. Community release builds, whose private signing certificate is
/// maintained by the project, are pinned by the exact leaf certificate bytes.
/// Ad-hoc signatures have neither identity and are therefore rejected.
enum HelperClientSigningPolicy {
    static func identitiesMatch(
        guestTeamIdentifier: String?,
        helperTeamIdentifier: String?,
        guestLeafCertificate: Data?,
        helperLeafCertificate: Data?
    ) -> Bool {
        if let guestTeamIdentifier,
           let helperTeamIdentifier,
           !guestTeamIdentifier.isEmpty,
           guestTeamIdentifier == helperTeamIdentifier {
            return true
        }

        guard guestTeamIdentifier == nil,
              helperTeamIdentifier == nil,
              let guestLeafCertificate,
              let helperLeafCertificate,
              !guestLeafCertificate.isEmpty
        else { return false }

        return guestLeafCertificate == helperLeafCertificate
    }
}

enum ChargeHelperConstants {
    static let machServiceName = "io.github.muu3327.batteryharbor.helper"
    static let launchDaemonPlistName = "io.github.muu3327.batteryharbor.helper.plist"
    static let legacyLaunchDaemonPlistName = "com.batteryharbor.helper.plist"
    static let protocolVersion = 3
}

enum ChargeHardwareAction: String, Codable, Equatable, Hashable, Sendable {
    case enableCharging
    case disableCharging
    case enableForceDischarge
    case disableForceDischarge
}

struct HelperProbePayload: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let processIdentifier: Int32
    let effectiveUserID: UInt32
    let isPrivileged: Bool
    let writeOperationsEnabled: Bool
    let hardwareVerificationPassed: Bool
}

struct HelperCommandRequest: Codable, Equatable, Sendable {
    let requestIdentifier: UUID
    let actions: [ChargeHardwareAction]
}

struct HelperCommandResponse: Codable, Equatable, Sendable {
    let requestIdentifier: UUID
    let succeeded: Bool
    let message: String
    let observedValues: [String: [UInt8]]
}

struct HardwareVerificationPayload: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let succeeded: Bool
    let message: String
    let key: String
    let originalValue: [UInt8]
    let temporaryValue: [UInt8]
    let restoredValue: [UInt8]
}

enum HelperRegistrationStatus: String, Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown

    var displayName: String {
        switch self {
        case .enabled: "已启用"
        case .requiresApproval: "等待管理员批准"
        case .notRegistered: "尚未安装"
        case .notFound: "系统尚未识别模块"
        case .unknown: "状态未知"
        }
    }
}

@objc(ChargeHelperXPCProtocol)
protocol ChargeHelperXPCProtocol {
    func probe(withReply reply: @escaping (Data) -> Void)
    func execute(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func verifyHardwareControl(withReply reply: @escaping (Data) -> Void)
}
