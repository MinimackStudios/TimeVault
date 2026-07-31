import Foundation

struct ExportService: Sendable {
    func writeJSON(_ comparison: SnapshotComparison, to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(comparison)
        try data.write(to: url, options: .atomic)
    }

    func writeCSV(_ comparison: SnapshotComparison, to url: URL) throws {
        var rows = ["Change type,File name,Relative path,Old size,New size,Size difference,Old modification date,New modification date"]
        let formatter = ISO8601DateFormatter()
        for change in comparison.changes {
            let oldDate = change.oldMetadata?.modificationDate.map(formatter.string) ?? ""
            let newDate = change.newMetadata?.modificationDate.map(formatter.string) ?? ""
            rows.append([
                change.kind.rawValue, change.newMetadata?.fileName ?? change.oldMetadata?.fileName ?? "", change.relativePath,
                change.oldSize.map(String.init) ?? "", change.newSize.map(String.init) ?? "", String(change.sizeDifference), oldDate, newDate
            ].map(Self.escape).joined(separator: ","))
        }
        try rows.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func escape(_ value: String) -> String {
        let safeValue = neutralizeFormula(value)
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func neutralizeFormula(_ value: String) -> String {
        guard let first = value.first else { return value }
        switch first {
        case "=", "+", "-", "@", "\t", "\r", "\n":
            return "'" + value
        default:
            return value
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
