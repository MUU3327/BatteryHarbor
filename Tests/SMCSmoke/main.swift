import Foundation

@main
enum SMCSmoke {
    static func main() {
        precondition(MemoryLayout<SMCParamStruct>.stride == 80, "SMC ABI 结构必须为 80 字节")
        let capabilities = SMCChargeCapabilityProbe().probe()
        print("充电控制键 / Charging key: \(capabilities.chargingPath.displayName)")
        print("放电控制键 / Discharge key: \(capabilities.dischargeKey ?? "未检测到 / not detected")")
        print("充电原始值 / Original charging value: \(hex(capabilities.chargingRawValue))")
        print("放电原始值 / Original discharge value: \(hex(capabilities.dischargeRawValue))")

        do {
            let client = try SMCReadOnlyClient()
            for key in ["CHTE", "CH0B", "CH0C", "CHIE", "CH0J", "CH0I"] {
                do {
                    print("\(key)：\(hex(try client.read(key)))")
                } catch {
                    print("\(key)：\(error.localizedDescription)")
                }
            }
        } catch {
            print("AppleSMC：\(error.localizedDescription)")
        }
    }

    private static func hex(_ bytes: [UInt8]?) -> String {
        guard let bytes else { return "—" }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
