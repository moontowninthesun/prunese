import AppKit
import SwiftUI

enum MapSelection: Hashable {
    case route, boss, item(UUID)
}

struct MapZoom: Equatable {
    enum Action { case fit, inwards, outwards }
    let action: Action
    private let id = UUID()
}

struct StageCanvas: NSViewRepresentable {
    let draft: RouteDraft
    let selection: MapSelection?
    let snap: Bool
    let zoom: MapZoom?
    let select: (MapSelection) -> Void
    let updateItem: (RouteItem) -> Void
    let moveBoss: (Double) -> Void
    let delete: () -> Void

    func makeNSView(context: Context) -> MapWorkspace {
        MapWorkspace()
    }

    func updateNSView(_ view: MapWorkspace, context: Context) {
        let scroll = view.scroll
        let map = scroll.map
        let oldSelection = map.selection
        map.draft = draft
        map.selection = selection
        map.snap = snap
        map.select = select
        map.updateItem = updateItem
        map.moveBoss = moveBoss
        map.delete = delete
        map.setFrameSize(NSSize(width: draft.mapWidth, height: StagePainter.canvasHeight))
        map.needsDisplay = true

        if let zoom, zoom != scroll.lastZoom {
            scroll.lastZoom = zoom
            switch zoom.action {
            case .fit: scroll.fit()
            case .inwards: scroll.adjustZoom(factor: 1.35)
            case .outwards: scroll.adjustZoom(factor: 1 / 1.35)
            }
        } else if selection != oldSelection, let selection {
            let x: Double?
            switch selection {
            case .route: x = nil
            case .boss: x = draft.boss
            case .item(let id): x = draft.items.first(where: { $0.id == id })?.x
            }
            if let x { scroll.reveal(x: x) }
        }
        view.overview.needsDisplay = true
    }
}

final class MapWorkspace: NSView {
    let scroll = MapScrollView()
    let overview = MapOverview(frame: .zero)

    init() {
        super.init(frame: .zero)
        overview.scroll = scroll
        scroll.onViewportChange = { [weak overview] in overview?.needsDisplay = true }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        overview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        addSubview(overview)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: overview.topAnchor),
            overview.leadingAnchor.constraint(equalTo: leadingAnchor),
            overview.trailingAnchor.constraint(equalTo: trailingAnchor),
            overview.bottomAnchor.constraint(equalTo: bottomAnchor),
            overview.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class MapOverview: NSView {
    weak var scroll: MapScrollView?
    private let inset: Double = 12
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let scroll, bounds.width > inset * 2 else { return }
        let draft = scroll.map.draft
        let scale = (bounds.width - inset * 2) / draft.mapWidth
        StagePainter.background.blended(withFraction: 0.07, of: .white)?.setFill()
        NSBezierPath.fill(bounds)
        let viewport = scroll.documentVisibleRect
        let visible = NSRect(x: inset + max(0, viewport.minX) * scale, y: 5,
                             width: max(0, min(draft.mapWidth, viewport.maxX) - max(0, viewport.minX)) * scale,
                             height: bounds.height - 10)
        StagePainter.ink.withAlphaComponent(0.10).setFill()
        NSBezierPath.fill(visible)
        StagePainter.label("OVERVIEW", at: NSPoint(x: inset + 4, y: 7), size: 9, color: StagePainter.muted)
        for item in draft.items {
            let x = inset + item.x * scale
            let y = 18 + 24 * min(RouteDraft.height, max(0, draft.top(for: item))) / RouteDraft.height
            StagePainter.color(for: item.layer).setFill()
            let rect = item.layer.isPlatform
                ? NSRect(x: x, y: y, width: max(1, item.width * scale), height: 2)
                : NSRect(x: x - 1.5, y: y - 4, width: 3, height: 3)
            NSBezierPath.fill(rect)
        }
        let frame = NSBezierPath(rect: visible)
        StagePainter.ink.withAlphaComponent(0.48).setStroke()
        frame.lineWidth = 1
        frame.stroke()
    }

    override func mouseDown(with event: NSEvent) { scrub(event) }
    override func mouseDragged(with event: NSEvent) { scrub(event) }

    private func scrub(_ event: NSEvent) {
        guard let scroll, bounds.width > inset * 2 else { return }
        let local = convert(event.locationInWindow, from: nil)
        let fraction = min(1, max(0, (local.x - inset) / (bounds.width - inset * 2)))
        scroll.center(x: fraction * scroll.map.draft.mapWidth)
    }
}

private final class CenteredMapClip: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let frame = documentView?.frame, rect.height > frame.height {
            rect.origin.y = frame.midY - rect.height / 2
        }
        return rect
    }
}

final class MapScrollView: NSScrollView {
    let map = MapEditorView(frame: NSRect(x: 0, y: 0, width: 3200, height: StagePainter.canvasHeight))
    var lastZoom: MapZoom?
    var onViewportChange: (() -> Void)?
    private var fitted = false

    init() {
        super.init(frame: .zero)
        contentView = CenteredMapClip(frame: .zero)
        documentView = map
        borderType = .noBorder
        backgroundColor = StagePainter.background
        hasHorizontalScroller = true
        hasVerticalScroller = true
        allowsMagnification = true
        minMagnification = 0.016
        maxMagnification = 2.5
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                               name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func viewportChanged() { onViewportChange?() }

    override func layout() {
        super.layout()
        if !fitted, contentSize.width > 100, contentSize.height > 100 {
            fitted = true
            fit(width: RouteDraft.screenWidth)
        }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        map.needsDisplay = true
    }

    func fit(width: Double? = nil) {
        guard contentSize.width > 20, contentSize.height > 20 else { return }
        let ratio = min((contentSize.width - 2) / (width ?? map.frame.width),
                        (contentSize.height - 2) / map.frame.height)
        magnification = min(maxMagnification, max(minMagnification, ratio))
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: .zero, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
        map.needsDisplay = true
        onViewportChange?()
    }

    func adjustZoom(factor: Double) {
        let visible = documentVisibleRect
        let focus = CGPoint(x: visible.midX, y: visible.midY)
        setMagnification(min(maxMagnification, max(minMagnification, magnification * factor)), centeredAt: focus)
        map.needsDisplay = true
        onViewportChange?()
    }

    func reveal(x: Double) {
        let visible = documentVisibleRect
        guard x < visible.minX || x > visible.maxX else { return }
        center(x: x)
    }

    func center(x: Double) {
        let current = contentView.bounds
        let target = NSRect(x: x - current.width / 2, y: current.minY, width: current.width, height: current.height)
        contentView.scroll(to: contentView.constrainBoundsRect(target).origin)
        reflectScrolledClipView(contentView)
        onViewportChange?()
    }
}

final class MapEditorView: NSView {
    private enum DragTarget {
        case item(RouteItem, resize: Bool)
        case boss(Double)
    }

    private struct Drag {
        let target: DragTarget
        let origin: NSPoint
        var item: RouteItem?
        var boss: Double?
    }

    var draft: RouteDraft = .example
    var selection: MapSelection?
    var snap = true
    var select: ((MapSelection) -> Void)?
    var updateItem: ((RouteItem) -> Void)?
    var moveBoss: ((Double) -> Void)?
    var delete: (() -> Void)?
    private var drag: Drag?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var zoom: Double { Double(enclosingScrollView?.magnification ?? 1) }

    override func draw(_ dirtyRect: NSRect) {
        var showing = draft
        if let item = drag?.item, let index = showing.items.firstIndex(where: { $0.id == item.id }) {
            showing.items[index] = item
        }
        if let boss = drag?.boss { showing.boss = boss }
        StagePainter.draw(showing, dirty: dirtyRect, zoom: zoom, selection: selection, grid: true)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let hitRadius = max(9, min(34, 8 / zoom))
        if let item = draft.items.reversed().first(where: {
            !$0.layer.isPlatform && StagePainter.marker(for: $0, in: draft, radius: hitRadius).contains(point)
        }) {
            beginDrag(item, at: point, resize: false)
        } else if abs(point.x - draft.boss) <= hitRadius &&
                    (point.y < StagePainter.ruler || abs(point.y - StagePainter.ruler - RouteDraft.floorY + 60) < 70) {
            selection = .boss
            select?(.boss)
            drag = Drag(target: .boss(draft.boss), origin: point)
        } else if let item = draft.items.reversed().first(where: {
            $0.layer.isPlatform && StagePainter.platform(for: $0).insetBy(dx: 0, dy: -6 / zoom).contains(point)
        }) {
            let rightEdge = abs(point.x - item.x - item.width) < 9 / zoom
            beginDrag(item, at: point, resize: rightEdge && selection == .item(item.id))
        } else {
            selection = .route
            select?(.route)
        }
        needsDisplay = true
    }

    private func beginDrag(_ item: RouteItem, at origin: NSPoint, resize: Bool) {
        selection = .item(item.id)
        select?(.item(item.id))
        drag = Drag(target: .item(item, resize: resize), origin: origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let grid = snap && !event.modifierFlags.contains(.option) ? 8.0 : 1.0
        let dx = ((point.x - drag.origin.x) / grid).rounded() * grid
        let dy = ((point.y - drag.origin.y) / grid).rounded() * grid
        switch drag.target {
        case .boss(let x):
            drag.boss = min(draft.mapWidth, max(0, x + dx))
        case .item(let original, let resize):
            var item = original
            if resize {
                item.set(.number(min(max(16, original.width + dx), max(16, draft.mapWidth - original.x))), at: 1)
            } else {
                item.x = min(max(0, draft.mapWidth - original.width), max(0, original.x + dx))
                if dy != 0, let _ = item.layer.yIndex {
                    let top = min(RouteDraft.height - 1, max(0, draft.top(for: original) + dy))
                    item.y = item.layer.isEnemy ? matchingSupport(at: item.x, near: top) ?? top : top
                }
            }
            drag.item = item
        }
        self.drag = drag
        autoscroll(with: event)
        needsDisplay = true
    }

    private func matchingSupport(at x: Double, near top: Double) -> Double? {
        draft.items
            .filter { $0.layer.isPlatform && $0.x <= x && x <= $0.x + $0.width }
            .compactMap(\.y)
            .min(by: { abs($0 - top) < abs($1 - top) })
            .flatMap { abs($0 - top) <= 42 ? $0 : nil }
    }

    override func mouseUp(with event: NSEvent) {
        let final = drag
        drag = nil
        if let item = final?.item { updateItem?(item) }
        if let x = final?.boss { moveBoss?(x) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            delete?()
            return
        }
        let delta: (Double, Double)
        switch event.keyCode {
        case 123: delta = (-1, 0)
        case 124: delta = (1, 0)
        case 125: delta = (0, 1)
        case 126: delta = (0, -1)
        default: super.keyDown(with: event); return
        }
        let step = event.modifierFlags.contains(.shift) ? 16.0 : 1.0
        switch selection {
        case .boss:
            if delta.0 != 0 { moveBoss?(min(draft.mapWidth, max(0, draft.boss + delta.0 * step))) }
        case .item(let id):
            guard var item = draft.items.first(where: { $0.id == id }) else { return }
            item.x = min(max(0, draft.mapWidth - item.width), max(0, item.x + delta.0 * step))
            if delta.1 != 0, item.layer.yIndex != nil {
                item.y = min(RouteDraft.height - 1, max(0, draft.top(for: item) + delta.1 * step))
            }
            updateItem?(item)
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
enum StagePainter {
    static let ruler: Double = 44
    static let canvasHeight: Double = RouteDraft.height + ruler
    static let background = NSColor(srgbRed: 0.090, green: 0.105, blue: 0.137, alpha: 1)
    static let ink = NSColor(srgbRed: 0.87, green: 0.89, blue: 0.92, alpha: 1)
    static let brass = NSColor(srgbRed: 0.98, green: 0.76, blue: 0.38, alpha: 1)
    static let muted = NSColor(srgbRed: 0.54, green: 0.60, blue: 0.66, alpha: 1)

    static func color(for layer: RouteLayer) -> NSColor {
        switch layer {
        case .ground: NSColor(srgbRed: 0.30, green: 0.55, blue: 0.53, alpha: 1)
        case .ledges: NSColor(srgbRed: 0.42, green: 0.66, blue: 0.72, alpha: 1)
        case .cast: NSColor(srgbRed: 0.94, green: 0.45, blue: 0.44, alpha: 1)
        case .arcadeCast: NSColor(srgbRed: 0.86, green: 0.53, blue: 0.75, alpha: 1)
        case .props: muted
        case .pickups: brass
        }
    }

    static func platform(for item: RouteItem) -> NSRect {
        let y = item.y ?? RouteDraft.floorY
        return NSRect(x: item.x, y: ruler + y, width: max(1, item.width),
                      height: item.layer == .ground ? max(1, RouteDraft.height - y) : 22)
    }

    static func marker(for item: RouteItem, in draft: RouteDraft, radius: Double) -> NSRect {
        let rise = item.layer.isEnemy ? radius * 1.55 : item.layer == .props ? radius * 1.12 : 0
        return NSRect(x: item.x - radius, y: ruler + draft.top(for: item) - radius - rise,
                      width: radius * 2, height: radius * 2)
    }

    static func draw(_ draft: RouteDraft, dirty: NSRect, zoom: Double,
                     selection: MapSelection?, grid: Bool, inactive: Set<UUID> = []) {
        background.setFill()
        NSBezierPath.fill(dirty)
        let screen = RouteDraft.screenWidth
        let first = max(0, Int(dirty.minX / screen))
        let last = max(first, Int(min(draft.mapWidth, dirty.maxX) / screen))
        let labelSize = min(58, max(12, 10 / zoom))
        let lineWidth = max(1, 1 / zoom)

        if grid {
            if zoom >= 0.19 {
                let minX = max(0, (dirty.minX / 80).rounded(.down) * 80)
                for x in stride(from: minX, through: min(draft.mapWidth, dirty.maxX), by: 80) {
                    line(NSPoint(x: x, y: ruler), NSPoint(x: x, y: canvasHeight), ink.withAlphaComponent(0.055), width: lineWidth)
                }
                for y in stride(from: ruler + 80, through: canvasHeight, by: 80) {
                    line(NSPoint(x: dirty.minX, y: y), NSPoint(x: dirty.maxX, y: y), ink.withAlphaComponent(0.055), width: lineWidth)
                }
            }
            for index in first...last {
                let x = Double(index) * screen
                line(NSPoint(x: x, y: 0), NSPoint(x: x, y: canvasHeight), muted.withAlphaComponent(0.32), width: lineWidth)
                if x + 200 < draft.mapWidth, Double(index).truncatingRemainder(dividingBy: zoom < 0.10 ? 4 : 1) == 0 {
                    label("SCREEN \(index + 1)   /   \(Int(x))", at: NSPoint(x: x + 13, y: 5), size: labelSize, color: muted)
                }
            }
            line(NSPoint(x: dirty.minX, y: ruler), NSPoint(x: dirty.maxX, y: ruler),
                 muted.withAlphaComponent(0.25), width: lineWidth)
        }

        for layer in RouteLayer.allCases {
            let color = color(for: layer)
            for item in draft.items where item.layer == layer && !inactive.contains(item.id) {
                let selected = selection == .item(item.id)
                if layer.isPlatform {
                    let rect = platform(for: item)
                    guard rect.insetBy(dx: -32, dy: -item.travel.magnitude - 24).intersects(dirty) else { continue }
                    if item.travel != 0 {
                        let bounds = rect.insetBy(dx: 0, dy: -item.travel.magnitude)
                        color.withAlphaComponent(0.08).setFill()
                        NSBezierPath.fill(bounds)
                    }
                    color.withAlphaComponent(layer == .ground ? 0.24 : 0.46).setFill()
                    NSBezierPath.fill(rect)
                    line(NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                         selected ? brass : color, width: selected ? lineWidth * 2 : lineWidth)
                    if item.gate != nil, zoom > 0.22 {
                        label("HELMET", at: NSPoint(x: rect.minX + 10, y: rect.minY - labelSize - 5),
                              size: labelSize, color: brass)
                    }
                    if selected {
                        outline(rect, color: brass, width: lineWidth)
                        brass.setFill()
                        let handle = 7 / zoom
                        NSBezierPath.fill(NSRect(x: rect.maxX - handle / 2, y: rect.minY - handle / 2,
                                                 width: handle, height: handle))
                    }
                } else {
                    let rect = marker(for: item, in: draft, radius: max(10, min(26, 6 / zoom)))
                    guard rect.insetBy(dx: -105, dy: -24).intersects(dirty) else { continue }
                    let path = NSBezierPath()
                    if layer == .pickups {
                        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
                        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
                        path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
                        path.line(to: NSPoint(x: rect.minX, y: rect.midY))
                        path.close()
                    } else if layer.isEnemy {
                        path.appendRoundedRect(rect, xRadius: rect.width * 0.21, yRadius: rect.height * 0.21)
                    } else {
                        path.appendOval(in: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15))
                    }
                    color.withAlphaComponent(layer == .props ? 0.37 : 0.85).setFill()
                    path.fill()
                    if selected { brass.setStroke(); path.lineWidth = lineWidth * 1.5; path.stroke() }
                    if zoom > 0.45 || selected {
                        label(item.label, at: NSPoint(x: rect.maxX + 6 / zoom, y: rect.midY - labelSize / 2),
                              size: labelSize, color: selected ? brass : ink)
                    }
                }
            }
        }
        if grid {
            anchor("START", x: RouteDraft.spawnX, y: RouteDraft.floorY, color: color(for: .ledges), zoom: zoom)
            anchor("BOSS", x: draft.boss, y: RouteDraft.floorY, color: selection == .boss ? ink : brass, zoom: zoom)
            if zoom >= 0.17 {
                anchor("EXIT", x: max(0, draft.length - 115), y: RouteDraft.floorY, color: muted, zoom: zoom)
            }
        }
    }

    static func label(_ text: String, at point: NSPoint, size: Double, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [
            .foregroundColor: color, .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        ])
    }

    static func line(_ from: NSPoint, _ to: NSPoint, _ color: NSColor, width: Double) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func outline(_ rect: NSRect, color: NSColor, width: Double) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func anchor(_ title: String, x: Double, y: Double, color: NSColor, zoom: Double) {
        let size = min(48, max(13, 10 / zoom))
        let y = ruler + y
        line(NSPoint(x: x, y: y - 84), NSPoint(x: x, y: y), color, width: max(2, 2 / zoom))
        label(title, at: NSPoint(x: max(3, x - size * 1.4), y: y - 90 - size), size: size, color: color)
    }
}
