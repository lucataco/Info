import Foundation
import IOKit

/// Minimal, self-contained SMC (System Management Controller) client used only
/// for optional CPU/GPU temperature. This is the one power-hungry path Info has,
/// which is why temperature is **off by default** and sampled slowly only while
/// a panel is open.
///
/// Not Sendable — create, use, and close within a single background task.
final class SMCConnection {
    private var connection: io_connect_t = 0

    // SMC selectors
    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCReadKey: UInt8 = 5
    private let kSMCGetKeyInfo: UInt8 = 9

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
        connection = conn
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    /// Average of the valid readings among `keys` (°C), or nil if none read.
    func averageTemperature(keys: [String]) -> Double? {
        var sum = 0.0
        var count = 0
        for key in keys {
            if let value = readKey(key), value > 1, value < 120 {
                sum += value
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }

    // MARK: - Low level

    private func readKey(_ key: String) -> Double? {
        var info = SMCKeyData()
        info.key = Self.fourCharCode(key)
        info.data8 = kSMCGetKeyInfo
        guard call(&info) else { return nil }

        let dataType = info.keyInfo.dataType
        let dataSize = info.keyInfo.dataSize

        var read = SMCKeyData()
        read.key = Self.fourCharCode(key)
        read.keyInfo.dataSize = dataSize
        read.data8 = kSMCReadKey
        guard call(&read) else { return nil }

        return decode(type: dataType, bytes: read.bytes)
    }

    private func call(_ data: inout SMCKeyData) -> Bool {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let inputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent,
                                               &data, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return false }
        data = output
        return true
    }

    private func decode(type: UInt32, bytes: SMCBytes) -> Double? {
        let raw = Self.tupleToArray(bytes)
        switch Self.typeString(type) {
        case "flt ":
            let littleBits = UInt32(raw[0]) | (UInt32(raw[1]) << 8) | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
            let bigBits = (UInt32(raw[0]) << 24) | (UInt32(raw[1]) << 16) | (UInt32(raw[2]) << 8) | UInt32(raw[3])
            let little = Double(Float(bitPattern: littleBits))
            let big = Double(Float(bitPattern: bigBits))
            // Apple has used different encodings across generations/keys. For
            // temperature, accept the byte order that decodes to a plausible °C.
            if (1...120).contains(little) { return little }
            if (1...120).contains(big) { return big }
            return little
        case "sp78":
            return Double(raw[0]) + Double(raw[1]) / 256.0
        case "ui8 ":
            return Double(raw[0])
        case "ui16":
            return Double(UInt16(raw[0]) << 8 | UInt16(raw[1]))
        default:
            return nil
        }
    }

    // MARK: - Helpers

    static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) { result = (result << 8) | UInt32(byte) }
        return result
    }

    private static func typeString(_ type: UInt32) -> String {
        let bytes = [UInt8((type >> 24) & 0xff), UInt8((type >> 16) & 0xff),
                     UInt8((type >> 8) & 0xff), UInt8(type & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static func tupleToArray(_ bytes: SMCBytes) -> [UInt8] {
        withUnsafePointer(to: bytes) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 32) {
                Array(UnsafeBufferPointer(start: $0, count: 32))
            }
        }
    }

    /// Candidate thermal keys (Apple Silicon + Intel fallback). We read several
    /// and average the plausible ones because Apple changes keys per SoC.
    static let cpuKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp0n", "Tp0r", "Tp0v", "Tp0z",
        "Te05", "Tf04", "Tf09",            // efficiency clusters
        "TC0P", "TC0D", "TC0E", "TC0F",    // Intel
    ]
    static let gpuKeys = [
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0b", "Tg0j", "Tg0n", "Tg0r",
        "TCGC", "TG0P", "TG0D",            // Intel/AMD
    ]
}

// MARK: - C struct mirrors (must match AppleSMC layout)

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCKeyDataVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCKeyDataLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyDataKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Explicit padding so this matches the C struct's 12-byte size (Swift would
    // otherwise pack it as 9, throwing off SMCKeyData's total size → 76 vs 80
    // and kIOReturnBadArgument from the kernel).
    private var pad0: UInt8 = 0
    private var pad1: UInt8 = 0
    private var pad2: UInt8 = 0
}

struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCKeyDataVersion()
    var pLimitData = SMCKeyDataLimitData()
    var keyInfo = SMCKeyDataKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0)
}
