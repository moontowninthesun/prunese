import Foundation

enum RouteTable: String, CaseIterable, Codable, Identifiable, Sendable {
    case washington = "PRUNE_WASHINGTON"
    case america = "PRUNE_AMERICA"
    case planets = "PRUNE_PLANETS"

    var id: Self { self }
    var title: String {
        switch self {
        case .washington: "Washington"
        case .america: "American tour"
        case .planets: "Planetary tour"
        }
    }

    var stages: ClosedRange<Int> {
        switch self {
        case .washington: 2...9
        case .america: 11...20
        case .planets: 22...30
        }
    }

    var sourceFile: String {
        switch self {
        case .washington: "washington-routes.js"
        case .america: "american-routes.js"
        case .planets: "planetary-routes.js"
        }
    }

    var materials: [String] {
        switch self {
        case .washington: ["marble", "pool", "road", "scaffold", "steps", "turf"]
        case .america: ["brick", "desert", "fair", "road", "scaffold", "stage", "street"]
        case .planets: ["jupiter", "mars", "mercury", "moon", "neptune", "pluto", "saturn", "uranus", "venus"]
        }
    }

    var propKinds: [String] {
        switch self {
        case .washington: ["barrier", "column", "door", "flag", "lamp", "poolMarker", "tree", "window"]
        case .america: ["beacon", "bollard", "clapboard", "flag", "heatLamp", "marquee", "rimSign", "speaker", "valuation", "wirePost"]
        case .planets: ["altimeter", "crater", "dig", "iceFin", "lander", "marker", "mast", "ringMarker", "shade", "vane", "vent"]
        }
    }
}

enum RouteValue: Codable, Equatable, Sendable {
    case number(Double)
    case string(String)
    case array([RouteValue])
    case object([String: RouteValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else { self = .object(try value.decode([String: Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        case .bool(let flag): try value.encode(flag)
        case .null: try value.encodeNil()
        }
    }

    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var array: [Self]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: Self]? { if case .object(let value) = self { value } else { nil } }
}

enum RouteLayer: String, CaseIterable, Codable, Identifiable, Sendable {
    case ground, ledges, cast, arcadeCast, props, pickups

    var id: Self { self }
    var title: String {
        switch self {
        case .ground: "Ground"
        case .ledges: "Ledges"
        case .cast: "Enemies"
        case .arcadeCast: "Arcade enemies"
        case .props: "Props"
        case .pickups: "Pickups"
        }
    }

    var itemName: String {
        switch self {
        case .ground: "Ground span"
        case .ledges: "Ledge"
        case .cast: "Enemy"
        case .arcadeCast: "Arcade enemy"
        case .props: "Prop"
        case .pickups: "Pickup"
        }
    }

    var symbol: String {
        switch self {
        case .ground: "square.bottomhalf.filled"
        case .ledges: "rectangle"
        case .cast: "person.fill"
        case .arcadeCast: "person.2.fill"
        case .props: "flag.fill"
        case .pickups: "diamond.fill"
        }
    }

    var isPlatform: Bool { self == .ground || self == .ledges }
    var isEnemy: Bool { self == .cast || self == .arcadeCast }
    var xIndex: Int { self == .props || self == .pickups ? 1 : 0 }
    var yIndex: Int? {
        switch self {
        case .ground, .ledges, .pickups: 2
        case .cast, .arcadeCast: 3
        case .props: nil
        }
    }
}

struct RouteItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var layer: RouteLayer
    var tuple: [RouteValue]

    func number(at index: Int) -> Double? {
        tuple.indices.contains(index) ? tuple[index].number : nil
    }

    func string(at index: Int) -> String? {
        tuple.indices.contains(index) ? tuple[index].string : nil
    }

    mutating func set(_ value: RouteValue, at index: Int) {
        while tuple.count <= index { tuple.append(.null) }
        tuple[index] = value
        while tuple.last == .null { tuple.removeLast() }
    }

    var x: Double {
        get { number(at: layer.xIndex) ?? 0 }
        set { set(.number(newValue), at: layer.xIndex) }
    }

    var y: Double? {
        get { layer.yIndex.flatMap(number(at:)) }
        set { if let index = layer.yIndex { set(newValue.map(RouteValue.number) ?? .null, at: index) } }
    }

    var width: Double { layer.isPlatform ? (number(at: 1) ?? 0) : 0 }
    var travel: Double { layer == .ledges ? (number(at: 3) ?? 0) : 0 }
    var gate: String? { layer == .ledges ? string(at: 4) : nil }
    var kind: String { string(at: 0) ?? "" }
    var label: String {
        if layer.isEnemy {
            let names: [Int: String] = [6: "Clerk", 7: "Photographer", 8: "Student", 9: "Professor",
                                       10: "Capitol guard", 11: "Secret Service"]
            let sprite = number(at: 1) ?? 0
            return Int(exactly: sprite).flatMap { names[$0] } ?? "Sprite \(displayNumber(sprite))"
        }
        if layer == .props || layer == .pickups { return kind }
        return layer.itemName
    }
}

struct RouteDraft: Codable, Equatable, Sendable {
    static let spawnX: Double = 150
    static let floorY: Double = 612
    static let height: Double = 720
    static let screenWidth: Double = 1280
    static let maxLength: Double = 48_000

    var version = 1
    var title: String
    var notes = ""
    var table: RouteTable
    var stage: Int
    var fields: [String: RouteValue]
    var items: [RouteItem]
    var hasArcadeCast = false

    var length: Double {
        get { fields["length"]?.number ?? 3200 }
        set { fields["length"] = .number(newValue) }
    }

    var mapWidth: Double { min(max(length, Self.screenWidth), Self.maxLength) }
    var boss: Double {
        get { fields["boss"]?.number ?? 0 }
        set { fields["boss"] = .number(newValue) }
    }

    var material: String {
        get { fields["material"]?.string ?? table.materials[0] }
        set { fields["material"] = .string(newValue) }
    }

    var hint: String {
        get { fields["hint"]?.string ?? "" }
        set { fields["hint"] = .string(newValue) }
    }

    func items(on layer: RouteLayer) -> [RouteItem] { items.filter { $0.layer == layer } }

    func floorTop(at x: Double) -> Double? {
        items.first(where: { $0.layer == .ground && x >= $0.x && x <= $0.x + $0.width })?.y
    }

    func top(for item: RouteItem) -> Double {
        item.y ?? floorTop(at: item.x) ?? Self.floorY
    }

    var route: RouteValue {
        var object = fields
        for layer in RouteLayer.allCases {
            let group = items(on: layer)
            if layer == .arcadeCast && group.isEmpty && !hasArcadeCast { continue }
            object[layer.rawValue] = .array(group.map { .array($0.tuple) })
        }
        return .object(object)
    }

    func newItem(on layer: RouteLayer, at x: Double) -> RouteItem {
        let x = min(max(0, x), max(0, mapWidth - (layer.isPlatform ? 192 : 0)))
        let top = floorTop(at: x) ?? Self.floorY
        let tuple: [RouteValue]
        switch layer {
        case .ground: tuple = [.number(x), .number(192), .number(Self.floorY)]
        case .ledges: tuple = [.number(x), .number(192), .number(max(72, top - 112))]
        case .cast, .arcadeCast: tuple = [.number(x), .number(10), .string("order")]
        case .props: tuple = [.string(table.propKinds[0]), .number(x)]
        case .pickups: tuple = [.string("plum"), .number(x), .number(max(64, top - 88))]
        }
        return RouteItem(layer: layer, tuple: tuple)
    }

    static let example = RouteDraft(
        title: "Sample route",
        notes: "Use the lower ledge to cross the first gap. The upper path holds a pickup.",
        table: .washington,
        stage: 5,
        fields: ["length": .number(3200), "boss": .number(2740), "material": .string("marble"),
                 "hint": .string("Climb the ledges and cross the gap.")],
        items: [
            RouteItem(layer: .ground, tuple: [.number(0), .number(820), .number(612)]),
            RouteItem(layer: .ground, tuple: [.number(1000), .number(960), .number(612)]),
            RouteItem(layer: .ground, tuple: [.number(2140), .number(1060), .number(612)]),
            RouteItem(layer: .ledges, tuple: [.number(568), .number(328), .number(500)]),
            RouteItem(layer: .ledges, tuple: [.number(866), .number(232), .number(414)]),
            RouteItem(layer: .ledges, tuple: [.number(1788), .number(448), .number(482), .number(24)]),
            RouteItem(layer: .cast, tuple: [.number(436), .number(10), .string("order")]),
            RouteItem(layer: .cast, tuple: [.number(1380), .number(8), .string("knife")]),
            RouteItem(layer: .pickups, tuple: [.string("plum"), .number(968), .number(330)]),
            RouteItem(layer: .props, tuple: [.string("lamp"), .number(1552)])
        ])
}

struct RouteWarning: Identifiable {
    let id = UUID()
    let message: String
    var item: UUID?
    var blocksExport = false
}

extension RouteDraft {
    func warnings() -> [RouteWarning] {
        var warnings: [RouteWarning] = []
        if !table.stages.contains(stage) {
            warnings.append(.init(message: "Stage \(stage) is outside the \(table.title) route table.", blocksExport: true))
        }
        if !(Self.screenWidth...Self.maxLength).contains(length) {
            warnings.append(.init(message: "Level length must be between 1,280 and 48,000.", blocksExport: true))
        }
        if !(0...mapWidth).contains(boss) {
            warnings.append(.init(message: "Boss anchor is outside the level.", blocksExport: true))
        } else if floorTop(at: boss) == nil {
            warnings.append(.init(message: "Boss anchor has no ground below it."))
        }
        if floorTop(at: Self.spawnX) != Self.floorY {
            warnings.append(.init(message: "The game spawns Prune at (150, 612). Put ground at that point."))
        }
        if floorTop(at: length - 100) == nil {
            warnings.append(.init(message: "Check the exit: there is no ground at the end of the route."))
        }
        if table == .washington && stage <= 3 {
            warnings.append(.init(message: "Deluxe mode overrides this stage’s table terrain. Its special rooms are authored in the game."))
        }
        let supports = items.filter { $0.layer.isPlatform }
        for item in items {
            if !item.isValidTuple || !item.x.isFinite || item.x < 0 || item.x + item.width > length ||
                (item.layer.isPlatform && item.width <= 0) ||
                (item.y.map { !(0...Self.height).contains($0) } ?? false) {
                warnings.append(.init(message: "\(item.label) has invalid coordinates or fields.", item: item.id, blocksExport: true))
            } else if item.layer.isEnemy && !supports.contains(where: { span in
                item.x >= span.x && item.x <= span.x + span.width &&
                (item.y == nil ? span.layer == .ground : item.y == span.y)
            }) {
                warnings.append(.init(message: "\(item.label) at \(displayNumber(item.x)) has no matching patrol surface.", item: item.id))
            }
            if item.gate == "moon-air", stage != 22 {
                warnings.append(.init(message: "Helmet ledges open only in Stage 22.", item: item.id))
            }
        }
        return warnings
    }
}

extension RouteItem {
    var isValidTuple: Bool {
        guard number(at: layer.xIndex)?.isFinite == true else { return false }
        switch layer {
        case .ground, .ledges:
            return number(at: 1)?.isFinite == true && y?.isFinite == true
        case .cast, .arcadeCast:
            guard let sprite = number(at: 1), let index = Int(exactly: sprite), (0...11).contains(index),
                  let attack = string(at: 2), ["order", "knife"].contains(attack) else { return false }
            return tuple.count <= 3 || tuple[3] == .null || y?.isFinite == true
        case .props:
            return !kind.isEmpty
        case .pickups:
            return !kind.isEmpty && y?.isFinite == true
        }
    }
}

func displayNumber(_ number: Double) -> String {
    number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
}
