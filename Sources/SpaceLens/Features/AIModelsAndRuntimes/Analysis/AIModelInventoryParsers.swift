import Foundation

struct GGUFMetadata: Equatable, Sendable {
    let name: String?
    let architecture: String?
    let quantization: String?
}

enum AIModelInventoryParsers {
    private static let maximumSmallDocumentSize: UInt64 = 2 * 1_024 * 1_024
    private static let maximumHeaderBytes = 16 * 1_024 * 1_024

    struct OllamaDescriptor: Decodable, Equatable, Sendable {
        let mediaType: String
        let digest: String
        let size: Int64
    }

    struct OllamaManifest: Decodable, Equatable, Sendable {
        let config: OllamaDescriptor?
        let layers: [OllamaDescriptor]
    }

    static func ollamaManifest(at url: URL) -> OllamaManifest? {
        guard let data = boundedData(at: url, maximumBytes: maximumSmallDocumentSize) else {
            return nil
        }
        return try? JSONDecoder().decode(OllamaManifest.self, from: data)
    }

    static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = boundedData(at: url, maximumBytes: maximumSmallDocumentSize),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    static func isSafeTensors(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8),
              prefix.count == 8 else { return false }
        let headerLength = littleEndianUInt64(prefix, at: 0)
        guard headerLength > 1, headerLength <= UInt64(maximumHeaderBytes) else { return false }
        guard let header = try? handle.read(upToCount: Int(headerLength)),
              header.count == Int(headerLength),
              (try? JSONSerialization.jsonObject(with: header)) is [String: Any] else { return false }
        return true
    }

    static func ggufMetadata(at url: URL) -> GGUFMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumHeaderBytes),
              data.count >= 24 else { return nil }
        var cursor = DataCursor(data: data)
        guard cursor.readBytes(count: 4) == Data([0x47, 0x47, 0x55, 0x46]),
              let version = cursor.readUInt32(),
              (2...3).contains(version),
              cursor.readUInt64() != nil,
              let keyValueCount = cursor.readUInt64(),
              keyValueCount <= 100_000 else { return nil }

        var name: String?
        var architecture: String?
        var fileType: UInt64?
        let entriesToRead = min(Int(keyValueCount), 2_048)

        for _ in 0..<entriesToRead {
            guard let key = cursor.readString(maximumLength: 1_048_576),
                  let type = cursor.readUInt32() else { break }
            switch type {
            case 8:
                guard let value = cursor.readString(maximumLength: 1_048_576) else { break }
                if key == "general.name" { name = value }
                if key == "general.architecture" { architecture = value }
            case 4:
                guard let value = cursor.readUInt32() else { break }
                if key == "general.file_type" { fileType = UInt64(value) }
            case 10:
                guard let value = cursor.readUInt64() else { break }
                if key == "general.file_type" { fileType = value }
            case 9:
                guard cursor.skipArray() else { break }
            default:
                guard cursor.skipScalar(type: type) else { break }
            }
            if name != nil, architecture != nil, fileType != nil { break }
        }

        return GGUFMetadata(
            name: name,
            architecture: architecture,
            quantization: fileType.flatMap(quantizationName(for:))
        )
    }

    static func quantizationFromFilename(_ name: String) -> String? {
        let upper = name.uppercased()
        let patterns = [
            "IQ4_XS", "IQ4_NL", "IQ3_XXS", "IQ3_M", "IQ3_S", "IQ2_XXS", "IQ2_XS",
            "IQ2_M", "IQ2_S", "IQ1_M", "IQ1_S", "Q8_0", "Q6_K", "Q5_K_M", "Q5_K_S",
            "Q5_1", "Q5_0", "Q4_K_M", "Q4_K_S", "Q4_1", "Q4_0", "Q3_K_L", "Q3_K_M",
            "Q3_K_S", "Q2_K", "BF16", "F16", "F32"
        ]
        return patterns.first { upper.contains($0) }
    }

    static func normalizedSHA256(_ digest: String) -> String? {
        let value = digest.lowercased().replacingOccurrences(of: "sha256:", with: "")
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value
    }

    static func boundedString(at url: URL, maximumBytes: UInt64 = 4_096) -> String? {
        guard let data = boundedData(at: url, maximumBytes: maximumBytes) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedData(at url: URL, maximumBytes: UInt64) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size <= maximumBytes else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func quantizationName(for fileType: UInt64) -> String? {
        switch fileType {
        case 0: "F32"
        case 1: "F16"
        case 2: "Q4_0"
        case 3: "Q4_1"
        case 6: "Q5_0"
        case 7: "Q5_1"
        case 8: "Q8_0"
        case 10: "Q2_K"
        case 11: "Q3_K_S"
        case 12: "Q3_K_M"
        case 13: "Q3_K_L"
        case 14: "Q4_K_S"
        case 15: "Q4_K_M"
        case 16: "Q5_K_S"
        case 17: "Q5_K_M"
        case 18: "Q6_K"
        case 19: "IQ2_XXS"
        case 20: "IQ2_XS"
        case 21: "IQ3_XXS"
        case 22: "IQ1_S"
        case 23: "IQ4_NL"
        case 26: "IQ3_S"
        case 27: "IQ3_M"
        case 28: "IQ2_S"
        case 29: "IQ2_M"
        case 30: "IQ4_XS"
        case 31: "IQ1_M"
        case 32: "BF16"
        default: nil
        }
    }

    private static func littleEndianUInt64(_ data: Data, at offset: Int) -> UInt64 {
        guard data.count >= offset + 8 else { return 0 }
        return (0..<8).reduce(UInt64(0)) { result, index in
            result | (UInt64(data[offset + index]) << UInt64(index * 8))
        }
    }
}

private struct DataCursor {
    let data: Data
    var offset = 0

    mutating func readBytes(count: Int) -> Data? {
        guard count >= 0, offset <= data.count - count else { return nil }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readUInt32() -> UInt32? {
        guard let bytes = readBytes(count: 4) else { return nil }
        return (0..<4).reduce(UInt32(0)) { result, index in
            result | (UInt32(bytes[index]) << UInt32(index * 8))
        }
    }

    mutating func readUInt64() -> UInt64? {
        guard let bytes = readBytes(count: 8) else { return nil }
        return (0..<8).reduce(UInt64(0)) { result, index in
            result | (UInt64(bytes[index]) << UInt64(index * 8))
        }
    }

    mutating func readString(maximumLength: Int) -> String? {
        guard let length = readUInt64(), length <= UInt64(maximumLength),
              let bytes = readBytes(count: Int(length)) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    mutating func skipScalar(type: UInt32) -> Bool {
        let byteCount: Int
        switch type {
        case 0, 1, 7: byteCount = 1
        case 2, 3: byteCount = 2
        case 4, 5, 6: byteCount = 4
        case 10, 11, 12: byteCount = 8
        default: return false
        }
        return readBytes(count: byteCount) != nil
    }

    mutating func skipArray() -> Bool {
        guard let elementType = readUInt32(), let count = readUInt64(), count <= 1_000_000 else {
            return false
        }
        if elementType == 8 {
            for _ in 0..<Int(count) {
                guard readString(maximumLength: 1_048_576) != nil else { return false }
            }
            return true
        }
        let byteCount: UInt64
        switch elementType {
        case 0, 1, 7: byteCount = count
        case 2, 3: byteCount = count.multipliedReportingOverflow(by: 2).partialValue
        case 4, 5, 6: byteCount = count.multipliedReportingOverflow(by: 4).partialValue
        case 10, 11, 12: byteCount = count.multipliedReportingOverflow(by: 8).partialValue
        default: return false
        }
        guard byteCount <= UInt64(Int.max) else { return false }
        return readBytes(count: Int(byteCount)) != nil
    }
}
