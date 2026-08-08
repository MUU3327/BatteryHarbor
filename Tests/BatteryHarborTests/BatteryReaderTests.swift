import Foundation
import XCTest
@testable import BatteryHarbor

final class BatteryReaderTests: XCTestCase {
    func testHelperSigningPolicyAcceptsMatchingAppleTeam() {
        XCTAssertTrue(HelperClientSigningPolicy.identitiesMatch(
            guestTeamIdentifier: "ABCDEFGHIJ",
            helperTeamIdentifier: "ABCDEFGHIJ",
            guestLeafCertificate: Data([1]),
            helperLeafCertificate: Data([2])
        ))
    }

    func testHelperSigningPolicyAcceptsMatchingCommunityCertificateWithoutTeam() {
        let certificate = Data([0x30, 0x82, 0x01, 0x00])
        XCTAssertTrue(HelperClientSigningPolicy.identitiesMatch(
            guestTeamIdentifier: nil,
            helperTeamIdentifier: nil,
            guestLeafCertificate: certificate,
            helperLeafCertificate: certificate
        ))
    }

    func testHelperSigningPolicyRejectsAdHocAndMismatchedIdentities() {
        XCTAssertFalse(HelperClientSigningPolicy.identitiesMatch(
            guestTeamIdentifier: nil,
            helperTeamIdentifier: nil,
            guestLeafCertificate: nil,
            helperLeafCertificate: nil
        ))
        XCTAssertFalse(HelperClientSigningPolicy.identitiesMatch(
            guestTeamIdentifier: "ABCDEFGHIJ",
            helperTeamIdentifier: "KLMNOPQRST",
            guestLeafCertificate: Data([1]),
            helperLeafCertificate: Data([1])
        ))
        XCTAssertFalse(HelperClientSigningPolicy.identitiesMatch(
            guestTeamIdentifier: nil,
            helperTeamIdentifier: nil,
            guestLeafCertificate: Data([1]),
            helperLeafCertificate: Data([2])
        ))
    }

    func testFinalBundleServiceIdentifiersUseGitHubNamespace() {
        XCTAssertEqual(
            ChargeHelperConstants.machServiceName,
            "io.github.muu3327.batteryharbor.helper"
        )
        XCTAssertEqual(
            ChargeHelperConstants.launchDaemonPlistName,
            "io.github.muu3327.batteryharbor.helper.plist"
        )
        XCTAssertEqual(
            ChargeHelperConstants.legacyLaunchDaemonPlistName,
            "com.batteryharbor.helper.plist"
        )
    }

    func testEnglishLocalizationCoversDynamicInterfaceValues() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.object(forKey: "interfaceLanguage")
        defaults.set(AppLanguage.english.rawValue, forKey: "interfaceLanguage")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "interfaceLanguage")
            } else {
                defaults.removeObject(forKey: "interfaceLanguage")
            }
        }

        let snapshot = BatterySnapshot(
            percentage: 80,
            isCharging: false,
            isFullyCharged: false,
            isPresent: true,
            powerSource: .adapter
        )
        XCTAssertEqual(L10n.text("概览"), "Overview")
        XCTAssertEqual(SettingsSection.charging.displayName, "Charging")
        XCTAssertEqual(MenuBarDisplayMode.power.displayName, "Power")
        XCTAssertEqual(snapshot.stateText, "Connected to Power, Not Charging")
        XCTAssertEqual(L10n.text("临时目标 100%"), "Temporary Target 100%")
        XCTAssertEqual(L10n.format("常规上限 %lld%%", 90), "Regular Limit 90%")
        XCTAssertEqual(
            L10n.format("临时充满已启用，结束后恢复 %lld%% 上限", 90),
            "Top Up to 100% is active; the 90% limit will be restored when it ends"
        )
    }

    func testUnsignedRegistryValueIsConvertedToSignedInteger() {
        let wrapped = NSNumber(value: UInt64.max - 301)
        XCTAssertEqual(signedInt(wrapped), -302)
    }

    func testRegularRegistryValueRemainsPositive() {
        XCTAssertEqual(signedInt(NSNumber(value: 2_500)), 2_500)
    }

    func testSnapshotStateTextDistinguishesAdapterWithoutCharging() {
        let snapshot = BatterySnapshot(
            percentage: 80,
            isCharging: false,
            isFullyCharged: false,
            isPresent: true,
            powerSource: .adapter
        )
        XCTAssertEqual(snapshot.stateText, "已接电源，未充电")
    }

    func testPowerBalanceUsesAdapterSystemAndBatteryTelemetry() {
        let snapshot = BatterySnapshot(
            powerWatts: 26.463,
            adapterInputWatts: 31.880,
            systemLoadWatts: 5.417
        )
        XCTAssertEqual(snapshot.powerBalanceText, "平衡误差 0.00 W")
    }

    func testNativeChargeLimitRequiresMacOS264() {
        XCTAssertFalse(HardwareCapabilityProbe.supportsNativeChargeLimit(
            on: OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9)
        ))
        XCTAssertTrue(HardwareCapabilityProbe.supportsNativeChargeLimit(
            on: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        ))
        XCTAssertTrue(HardwareCapabilityProbe.supportsNativeChargeLimit(
            on: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        ))
    }

    func testEnergyCounterDeltaDoesNotUnderflow() {
        let previous = AppEnergyMonitor.Counters(
            processStartTime: 10,
            energyNanojoules: 500,
            cpuNanoseconds: 1_000,
            wakeups: 10,
            ioBytes: 2_000
        )
        let current = AppEnergyMonitor.Counters(
            processStartTime: 10,
            energyNanojoules: 400,
            cpuNanoseconds: 1_500,
            wakeups: 13,
            ioBytes: 2_500
        )
        let delta = AppEnergyMonitor.delta(current: current, previous: previous)
        XCTAssertEqual(delta.energyNanojoules, 0)
        XCTAssertEqual(delta.cpuNanoseconds, 500)
        XCTAssertEqual(delta.wakeups, 3)
        XCTAssertEqual(delta.ioBytes, 500)
    }

    func testEnergyHistoryAggregatesAppsAndHonorsCutoff() {
        let now = Date(timeIntervalSince1970: 10_000)
        let recentUsage = AppEnergyUsage(
            name: "示例 App",
            bundlePath: "/Applications/Example.app",
            energyJoules: 2,
            cpuPercent: 8,
            wakeups: 4,
            ioMegabytes: 1,
            impactScore: 2
        )
        let samples = [
            AppEnergyHistorySample(timestamp: now.addingTimeInterval(-30), usages: [recentUsage]),
            AppEnergyHistorySample(timestamp: now.addingTimeInterval(-60), usages: [recentUsage]),
            AppEnergyHistorySample(timestamp: now.addingTimeInterval(-7_200), usages: [recentUsage])
        ]

        let ranking = EnergyHistoryArchive.aggregate(samples, since: now.addingTimeInterval(-3_600))
        XCTAssertEqual(ranking.count, 1)
        XCTAssertEqual(ranking[0].energyJoules, 4)
        XCTAssertEqual(ranking[0].cpuPercent, 8)
        XCTAssertEqual(ranking[0].wakeups, 8)
        XCTAssertEqual(ranking[0].impactScore, 4)
    }

    func testEnergyHistoryCSVQuotesApplicationNames() {
        let date = Date(timeIntervalSince1970: 0)
        let usage = AppEnergyUsage(
            name: "示例, \"App\"",
            bundlePath: "/Applications/Example.app",
            energyJoules: 1,
            cpuPercent: 2,
            wakeups: 3,
            ioMegabytes: 4,
            impactScore: 5
        )
        let csv = EnergyHistoryArchive.csv(snapshot: EnergyHistorySnapshot(
            powerSamples: [PowerSample(timestamp: date, watts: -8.5)],
            appSamples: [AppEnergyHistorySample(timestamp: date, usages: [usage])]
        ))
        XCTAssertTrue(csv.contains("power,,,-8.5"))
        XCTAssertTrue(csv.contains("\"示例, \"\"App\"\"\""))
    }

    func testSMCStructMatchesKernelABI() {
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data8), 42)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.bytes), 48)
    }

    func testSMCFourCharacterCodeUsesBigEndianASCII() throws {
        XCTAssertEqual(try SMCReadOnlyClient.fourCharacterCode("CHTE"), 0x43485445)
        XCTAssertThrowsError(try SMCReadOnlyClient.fourCharacterCode("太长了"))
    }

    func testChargePolicyStopsAtUpperLimit() {
        let input = policyInput(percentage: 80, charging: true)
        XCTAssertEqual(ChargePolicy().actions(for: input), [.disableCharging])
    }

    func testChargePolicyUsesHysteresisBeforeResuming() {
        XCTAssertEqual(
            ChargePolicy().actions(for: policyInput(percentage: 79, charging: false)),
            []
        )
        XCTAssertEqual(
            ChargePolicy().actions(for: policyInput(percentage: 77, charging: false)),
            [.enableCharging]
        )
    }

    func testChargePolicyDischargesAboveLimitInSafeOrder() {
        let input = policyInput(
            percentage: 85,
            charging: true,
            discharging: false,
            automaticallyDischarges: true
        )
        XCTAssertEqual(
            ChargePolicy().actions(for: input),
            [.disableCharging, .enableForceDischarge]
        )
    }

    func testTemperatureProtectionUsesThreeDegreeHysteresis() {
        let protection = BatteryTemperatureProtection()
        XCTAssertEqual(
            protection.decision(
                temperatureCelsius: 38,
                threshold: 38,
                wasActive: false,
                isEnabled: true
            ),
            TemperatureProtectionDecision(
                isActive: true,
                actions: [.disableForceDischarge, .disableCharging]
            )
        )
        XCTAssertTrue(protection.decision(
            temperatureCelsius: 36,
            threshold: 38,
            wasActive: true,
            isEnabled: true
        ).isActive)
        XCTAssertFalse(protection.decision(
            temperatureCelsius: 35,
            threshold: 38,
            wasActive: true,
            isEnabled: true
        ).isActive)
    }

    func testTemporaryFullChargeOverridesPauseAndDischarge() {
        let now = Date()
        let input = ChargePolicyInput(
            percentage: 82,
            isAdapterConnected: true,
            isChargingEnabled: false,
            isForceDischargeEnabled: true,
            upperLimit: 80,
            lowerLimitDelta: 3,
            isPaused: true,
            automaticallyDischarges: true,
            temporaryFullChargeUntil: now.addingTimeInterval(3_600),
            now: now
        )
        XCTAssertEqual(
            ChargePolicy().actions(for: input),
            [.disableForceDischarge, .enableCharging]
        )
    }

    func testCalibrationAdvancesThroughAllFourStages() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var session = BatteryCalibrationSession(startedAt: startedAt, originalChargeLimit: 80)

        XCTAssertEqual(
            session.advance(percentage: 100, isAdapterConnected: true, now: startedAt),
            [.disableForceDischarge, .disableCharging]
        )
        XCTAssertEqual(session.phase, .restingAtFull)

        XCTAssertEqual(
            session.advance(
                percentage: 100,
                isAdapterConnected: true,
                now: startedAt.addingTimeInterval(60),
                fullRestDuration: 60
            ),
            [.disableCharging, .enableForceDischarge]
        )
        XCTAssertEqual(session.phase, .dischargingToLow)

        XCTAssertEqual(
            session.advance(
                percentage: 10,
                isAdapterConnected: true,
                now: startedAt.addingTimeInterval(120)
            ),
            [.disableForceDischarge, .enableCharging]
        )
        XCTAssertEqual(session.phase, .chargingToFullAgain)

        XCTAssertEqual(
            session.advance(
                percentage: 100,
                isAdapterConnected: true,
                now: startedAt.addingTimeInterval(180)
            ),
            [.disableForceDischarge, .disableCharging]
        )
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.progress, 1)
    }

    func testCalibrationWaitsSafelyWhenPowerIsDisconnected() {
        var session = BatteryCalibrationSession(originalChargeLimit: 75)
        XCTAssertEqual(
            session.advance(percentage: 50, isAdapterConnected: false, now: Date()),
            [.disableForceDischarge]
        )
        XCTAssertEqual(session.phase, .chargingToFull)
        XCTAssertEqual(session.originalChargeLimit, 75)
    }

    func testDisconnectingAdapterClearsForcedDischarge() {
        var input = policyInput(percentage: 85, charging: false, discharging: true)
        input = ChargePolicyInput(
            percentage: input.percentage,
            isAdapterConnected: false,
            isChargingEnabled: input.isChargingEnabled,
            isForceDischargeEnabled: input.isForceDischargeEnabled,
            upperLimit: input.upperLimit,
            lowerLimitDelta: input.lowerLimitDelta,
            isPaused: input.isPaused,
            automaticallyDischarges: input.automaticallyDischarges,
            temporaryFullChargeUntil: input.temporaryFullChargeUntil,
            now: input.now
        )
        XCTAssertEqual(ChargePolicy().actions(for: input), [.disableForceDischarge])
    }

    func testTahoeWritePlannerUsesSafeDischargeOrder() throws {
        XCTAssertEqual(
            try TahoeSMCWritePlanner().steps(for: .enableForceDischarge),
            [
                SMCWriteStep(key: "CHTE", value: [0x01, 0x00, 0x00, 0x00]),
                SMCWriteStep(key: "CHIE", value: [0x08])
            ]
        )
    }

    func testVerifiedSMCTransactionRollsBackOnVerificationFailure() throws {
        let backend = FakeSMCAccess(values: [
            "CHTE": [0x00, 0x00, 0x00, 0x00],
            "CHIE": [0x00]
        ])
        backend.keysThatIgnoreWrites = ["CHIE"]
        let steps = try TahoeSMCWritePlanner().steps(for: .enableForceDischarge)

        XCTAssertThrowsError(try VerifiedSMCTransactionExecutor(access: backend).execute(steps))
        XCTAssertEqual(backend.values["CHTE"], [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(backend.values["CHIE"], [0x00])
    }

    func testVerifiedSMCTransactionRejectsUnexpectedSizeBeforeWriting() {
        let backend = FakeSMCAccess(values: ["CHTE": [0x00, 0x00, 0x00, 0x00]])
        let invalid = [SMCWriteStep(key: "CHTE", value: [0x01])]

        XCTAssertThrowsError(try VerifiedSMCTransactionExecutor(access: backend).execute(invalid))
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testHardwareRestoreVerificationWritesTemporaryValueThenRestoresOriginal() throws {
        let original: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let temporary: [UInt8] = [0x01, 0x00, 0x00, 0x00]
        let backend = FakeSMCAccess(values: ["CHTE": original])

        let outcome = try VerifiedSMCRestoreTester(access: backend).verifyChargingToggle()

        XCTAssertEqual(outcome.originalValue, original)
        XCTAssertEqual(outcome.temporaryValue, temporary)
        XCTAssertEqual(outcome.restoredValue, original)
        XCTAssertEqual(backend.writes, [
            SMCWriteStep(key: "CHTE", value: temporary),
            SMCWriteStep(key: "CHTE", value: original)
        ])
        XCTAssertEqual(backend.values["CHTE"], original)
    }

    func testHardwareRestoreVerificationRejectsUnknownOriginalWithoutWriting() {
        let backend = FakeSMCAccess(values: ["CHTE": [0x07, 0x00, 0x00, 0x00]])
        XCTAssertThrowsError(try VerifiedSMCRestoreTester(access: backend).verifyChargingToggle())
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testHelperCommandRequestRoundTripsThroughJSON() throws {
        let request = HelperCommandRequest(
            requestIdentifier: UUID(uuidString: "13CC8F31-E12E-4AE6-9388-8763B20A0C18")!,
            actions: [.disableForceDischarge, .enableCharging]
        )
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(HelperCommandRequest.self, from: data), request)
        XCTAssertEqual(ChargeHelperConstants.protocolVersion, 3)
    }

    func testDiagnosticReportExcludesSerialNumberAndIncludesControlState() {
        let capabilities = ChargeCapabilities(
            modelIdentifier: "MacTest1,1",
            firmwareVersion: "1.0",
            isAppleSilicon: true,
            hasAppleSMCService: true,
            supportsNativeChargeLimit: false,
            baselineBackend: .privilegedSMC,
            smcChargeKeys: SMCChargeKeyCapabilities(
                chargingPath: .tahoe,
                dischargeKey: "CHIE",
                chargingRawValue: [0, 0, 0, 0],
                dischargeRawValue: [0]
            )
        )
        let report = DiagnosticReportBuilder.build(
            generatedAt: Date(timeIntervalSince1970: 0),
            snapshot: BatterySnapshot(percentage: 80, isPresent: true),
            capabilities: capabilities,
            controlState: .unavailable(reason: "测试锁定"),
            helperStatus: .notRegistered,
            helperProbe: nil,
            chargeLimit: 80,
            automaticallyDischarges: false,
            highTemperatureProtectionEnabled: true,
            highTemperatureThreshold: 38,
            sleepProtectionEnabled: true,
            scheduleCount: 2,
            recentLogs: []
        )
        XCTAssertTrue(report.contains("MacTest1,1"))
        XCTAssertTrue(report.contains("不可用：测试锁定"))
        XCTAssertTrue(report.contains("计划数量: 2"))
        XCTAssertFalse(report.lowercased().contains("serial"))
    }

    func testChargeScheduleTriggersOnlyOncePerMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 10, hour: 9, minute: 30, second: 5
        )))
        let weekday = calendar.component(.weekday, from: date)
        var schedule = ChargeSchedule(
            name: "工作日上限",
            hour: 9,
            minute: 30,
            weekdays: [weekday],
            action: .applyLimit,
            chargeLimit: 80
        )

        XCTAssertTrue(schedule.isDue(at: date, calendar: calendar))
        schedule.lastTriggeredAt = date
        XCTAssertFalse(schedule.isDue(at: date.addingTimeInterval(40), calendar: calendar))
        XCTAssertFalse(schedule.isDue(at: date.addingTimeInterval(60), calendar: calendar))
    }

    func testChargeScheduleClampsLimitAndTime() {
        let schedule = ChargeSchedule(
            name: "边界",
            hour: 28,
            minute: -4,
            weekdays: [0, 1, 8],
            action: .applyLimit,
            chargeLimit: 20
        )
        XCTAssertEqual(schedule.hour, 23)
        XCTAssertEqual(schedule.minute, 0)
        XCTAssertEqual(schedule.weekdays, [1])
        XCTAssertEqual(schedule.chargeLimit, 50)
    }

    private func policyInput(
        percentage: Int,
        charging: Bool?,
        discharging: Bool? = false,
        automaticallyDischarges: Bool = false
    ) -> ChargePolicyInput {
        ChargePolicyInput(
            percentage: percentage,
            isAdapterConnected: true,
            isChargingEnabled: charging,
            isForceDischargeEnabled: discharging,
            upperLimit: 80,
            lowerLimitDelta: 3,
            isPaused: false,
            automaticallyDischarges: automaticallyDischarges,
            temporaryFullChargeUntil: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private final class FakeSMCAccess: SMCByteAccess {
    var values: [String: [UInt8]]
    var keysThatIgnoreWrites: Set<String> = []
    private(set) var writes: [SMCWriteStep] = []

    init(values: [String: [UInt8]]) {
        self.values = values
    }

    func read(_ key: String) throws -> [UInt8] {
        values[key] ?? []
    }

    func write(_ key: String, value: [UInt8]) throws {
        writes.append(SMCWriteStep(key: key, value: value))
        guard !keysThatIgnoreWrites.contains(key) else { return }
        values[key] = value
    }
}
