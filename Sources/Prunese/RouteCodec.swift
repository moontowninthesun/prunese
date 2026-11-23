import Foundation

enum RouteCodec {
    static func drafts(from data: Data, table fallbackTable: RouteTable, stage fallbackStage: Int) throws -> [RouteDraft] {
        guard data.count <= 8 * 1024 * 1024, let source = String(data: data, encoding: .utf8) else {
            throw RouteImportError("Choose a UTF-8 route file under 8 MB.")
        }
        var parser = RouteLiteralParser(source)
        let parsed = try parser.parse()
        let table = parsed.table ?? fallbackTable
        guard let object = parsed.value.object else {
            throw RouteImportError("The file must contain a route object or a table of numbered routes.")
        }
        if object["length"] != nil {
            return [try draft(from: object, stage: parsed.stage ?? fallbackStage, table: table)]
        }
        let stages = object.keys.compactMap(Int.init).sorted()
        guard !stages.isEmpty, stages.count == object.count else {
            throw RouteImportError("No numbered routes were found.")
        }
        return try stages.map { stage in
            guard let route = object[String(stage)]?.object else {
                throw RouteImportError("Stage \(stage) must be an object.")
            }
            return try draft(from: route, stage: stage, table: table)
        }
    }

    private static func draft(from object: [String: RouteValue], stage: Int, table: RouteTable) throws -> RouteDraft {
        var fields = object
        var items: [RouteItem] = []
        guard fields["length"]?.number != nil, fields["boss"]?.number != nil,
              fields["material"]?.string != nil else {
            throw RouteImportError("Stage \(stage) needs a number for length and boss, and a material name.")
        }
        let hasArcadeCast = fields["arcadeCast"] != nil
        for layer in RouteLayer.allCases {
            guard let value = fields.removeValue(forKey: layer.rawValue) else {
                if layer == .arcadeCast { continue }
                throw RouteImportError("Stage \(stage) is missing \(layer.rawValue).")
            }
            guard let array = value.array else {
                throw RouteImportError("Stage \(stage) has an invalid \(layer.rawValue) list.")
            }
            for (index, value) in array.enumerated() {
                guard let tuple = value.array else {
                    throw RouteImportError("Stage \(stage), \(layer.rawValue) item \(index + 1) must be an array.")
                }
                let item = RouteItem(layer: layer, tuple: tuple)
                guard item.isValidTuple else {
                    throw RouteImportError("Stage \(stage), \(layer.rawValue) item \(index + 1) has invalid fields.")
                }
                items.append(item)
            }
        }
        return RouteDraft(title: "Stage \(stage)", table: table, stage: stage, fields: fields,
                          items: items, hasArcadeCast: hasArcadeCast)
    }

    static func javascript(for draft: RouteDraft) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let object = String(decoding: try encoder.encode(draft.route), as: UTF8.self)
        let script = "// Prunese route override. Load after \(draft.table.sourceFile).\n" +
                     "window.\(draft.table.rawValue)[\(draft.stage)] = \(object);\n"
        return Data(script.utf8)
    }
}

struct RouteImportError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Reads only JavaScript literals. A route file is data, even when its extension is .js.
private struct RouteLiteralParser {
    typealias Result = (table: RouteTable?, stage: Int?, value: RouteValue)
    private let bytes: [UInt8]
    private var position = 0

    init(_ source: String) {
        let bytes = Array(source.utf8)
        self.bytes = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
    }

    mutating func parse() throws -> Result {
        try skipSpace()
        var table: RouteTable?
        var stage: Int?
        if peek == 119 { // window
            guard readWord() == "window" else { throw error("Expected a route object or a window assignment.") }
            try require(46, "Expected a period after window.")
            try skipSpace()
            guard let name = RouteTable(rawValue: readWord()) else { throw error("Unknown route table.") }
            table = name
            if try take(91) {
                try skipSpace()
                guard let index = Int(readNumberToken()) else { throw error("Expected a numeric stage.") }
                stage = index
                try require(93, "Expected a closing bracket after the stage.")
            }
            try require(61, "Expected an assignment to the route table.")
        }
        let value = try readValue(depth: 0)
        _ = try take(59)
        try skipSpace()
        guard peek == nil else { throw error("Unexpected content after the route.") }
        return (table, stage, value)
    }

    private mutating func readValue(depth: Int) throws -> RouteValue {
        guard depth < 64 else { throw error("Route data is nested too deeply.") }
        try skipSpace()
        guard let first = peek else { throw error("Expected a literal value.") }
        switch first {
        case 123:
            position += 1
            var fields: [String: RouteValue] = [:]
            while try !take(125) {
                try skipSpace()
                let name: String
                if peek == 34 || peek == 39 { name = try readString() }
                else { name = readWord() }
                guard !name.isEmpty else { throw error("Expected a property name.") }
                guard fields[name] == nil else { throw error("Duplicate property \(name).") }
                try require(58, "Expected a colon after \(name).")
                fields[name] = try readValue(depth: depth + 1)
                if try take(125) { break }
                try require(44, "Expected a comma between properties.")
            }
            return .object(fields)
        case 91:
            position += 1
            var values: [RouteValue] = []
            while try !take(93) {
                values.append(try readValue(depth: depth + 1))
                if try take(93) { break }
                try require(44, "Expected a comma between values.")
            }
            return .array(values)
        case 34, 39:
            return .string(try readString())
        case 45, 43, 46, 48...57:
            guard let number = Double(readNumberToken()), number.isFinite else { throw error("Invalid number.") }
            return .number(number)
        default:
            switch readWord() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default: throw error("Expected a literal value.")
            }
        }
    }

    private var peek: UInt8? { position < bytes.count ? bytes[position] : nil }

    private mutating func skipSpace() throws {
        while let byte = peek {
            if [9, 10, 13, 32].contains(byte) {
                position += 1
                continue
            }
            guard byte == 47, position + 1 < bytes.count else { break }
            let next = bytes[position + 1]
            if next == 47 {
                while let byte = peek, byte != 10 { position += 1 }
            } else if next == 42 {
                position += 2
                while position + 1 < bytes.count && !(bytes[position] == 42 && bytes[position + 1] == 47) {
                    position += 1
                }
                guard position + 1 < bytes.count else { throw error("Unclosed comment.") }
                position += 2
            } else { break }
        }
    }

    private mutating func take(_ byte: UInt8) throws -> Bool {
        try skipSpace()
        guard peek == byte else { return false }
        position += 1
        return true
    }

    private mutating func require(_ byte: UInt8, _ message: String) throws {
        guard try take(byte) else { throw error(message) }
    }

    private mutating func readWord() -> String {
        let start = position
        while let byte = peek, (48...57).contains(byte) || (65...90).contains(byte) ||
                (97...122).contains(byte) || byte == 95 || byte == 36 {
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    private mutating func readNumberToken() -> String {
        let start = position
        while let byte = peek, (48...57).contains(byte) || [43, 45, 46, 69, 101].contains(byte) {
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    private mutating func readString() throws -> String {
        guard let quote = peek else { throw error("Expected a string.") }
        position += 1
        var result: [UInt8] = []
        while let byte = peek {
            position += 1
            if byte == quote { return String(decoding: result, as: UTF8.self) }
            guard byte != 10 && byte != 13 else { throw error("Unclosed string.") }
            if byte != 92 { result.append(byte); continue }
            guard let escaped = peek else { throw error("Incomplete escape.") }
            position += 1
            switch escaped {
            case 34, 39, 47, 92: result.append(escaped)
            case 98: result.append(8)
            case 102: result.append(12)
            case 110: result.append(10)
            case 114: result.append(13)
            case 116: result.append(9)
            case 117:
                var value = try readHex(count: 4)
                if (0xD800...0xDBFF).contains(value) {
                    guard position + 1 < bytes.count, bytes[position] == 92, bytes[position + 1] == 117 else {
                        throw error("Incomplete Unicode pair.")
                    }
                    position += 2
                    let low = try readHex(count: 4)
                    guard (0xDC00...0xDFFF).contains(low) else { throw error("Invalid Unicode pair.") }
                    value = 0x10000 + (value - 0xD800) * 1024 + (low - 0xDC00)
                }
                guard let scalar = UnicodeScalar(value) else { throw error("Invalid Unicode escape.") }
                result.append(contentsOf: String(scalar).utf8)
            default: throw error("Unknown string escape.")
            }
        }
        throw error("Unclosed string.")
    }

    private mutating func readHex(count: Int) throws -> UInt32 {
        guard position + count <= bytes.count,
              let value = UInt32(String(decoding: bytes[position..<position + count], as: UTF8.self), radix: 16) else {
            throw error("Invalid Unicode escape.")
        }
        position += count
        return value
    }

    private func error(_ message: String) -> RouteImportError {
        let line = bytes.prefix(position).reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        return RouteImportError("Line \(line). \(message)")
    }
}
