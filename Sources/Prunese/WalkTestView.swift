import AppKit
import GameController
import SwiftUI

struct WalkTestView: View {
    let draft: RouteDraft
    let dismiss: () -> Void
    @State private var restart = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Walk Test").font(.title2.bold())
                    Text(draft.title).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restart") { restart = UUID() }
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
            }
            TrialCanvas(draft: draft, restart: restart)
                .accessibilityLabel("Playable terrain preview")
                .frame(width: 865, height: 486)
            Text("← → or A/D to move · Space to jump · Down + Space to drop · R to restart · Controller: stick/D-pad and A")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Check terrain and jump timing here. The game supplies combat and encounters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }
}

private struct TrialCanvas: NSViewRepresentable {
    let draft: RouteDraft
    let restart: UUID

    func makeNSView(context: Context) -> TrialView { TrialView(draft: draft, restart: restart) }
    func updateNSView(_ view: TrialView, context: Context) {
        if view.restart != restart || view.trial.draft != draft {
            view.restart = restart
            view.reset(draft: draft)
        }
    }
    static func dismantleNSView(_ view: TrialView, coordinator: ()) { view.stop() }
}

private final class TrialView: NSView {
    private var timer: Timer?
    private var keys = Set<UInt16>()
    private var lastFrame = 0.0
    private var timeBank = 0.0
    var trial: TerrainTrial
    var restart: UUID

    init(draft: RouteDraft, restart: UUID) {
        trial = TerrainTrial(draft: draft)
        self.restart = restart
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        lastFrame = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.async { [weak self] in
            if let self { self.window?.makeFirstResponder(self) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        keys.removeAll()
    }

    func reset(draft: RouteDraft) {
        trial = TerrainTrial(draft: draft)
        keys.removeAll()
        timeBank = 0
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 15: reset(draft: trial.draft)
        case 0, 2, 1, 49, 123, 124, 125: keys.insert(event.keyCode)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }

    override func resignFirstResponder() -> Bool {
        keys.removeAll()
        return super.resignFirstResponder()
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, now - lastFrame)
        lastFrame = now
        guard window?.isKeyWindow == true else {
            keys.removeAll()
            return
        }
        let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
        let keyboard = Double((keys.contains(124) || keys.contains(2) ? 1 : 0) - (keys.contains(123) || keys.contains(0) ? 1 : 0))
        let stick = Double(pad?.leftThumbstick.xAxis.value ?? 0)
        let hat = Double(pad?.dpad.xAxis.value ?? 0)
        let vertical = Double(pad?.dpad.yAxis.value ?? 0)
        let input = TrialInput(horizontal: keyboard + (abs(stick) > 0.18 ? stick : hat),
                               jump: keys.contains(49) || pad?.buttonA.isPressed == true,
                               down: keys.contains(125) || keys.contains(1) || vertical < -0.5)
        timeBank += elapsed
        let step = 1.0 / 60
        while timeBank >= step {
            trial.advance(input, by: step)
            timeBank -= step
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        StagePainter.background.setFill()
        NSBezierPath.fill(dirtyRect)
        let zoom = min(bounds.width / RouteDraft.screenWidth, bounds.height / StagePainter.canvasHeight)
        guard zoom > 0 else { return }
        let camera = min(max(0, trial.draft.mapWidth - RouteDraft.screenWidth), max(0, trial.x - 340))
        var showing = trial.draft
        var inactive = Set<UUID>()
        for index in showing.items.indices {
            let item = showing.items[index]
            if item.layer.isPlatform {
                if !trial.isOpen(item) { inactive.insert(item.id) }
                if item.travel != 0 {
                    showing.items[index].y = trial.height(of: item, at: trial.time)
                    showing.items[index].set(.number(0), at: 3)
                }
            }
        }
        if let helmet = trial.helmet { inactive.insert(helmet) }

        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(translationByX: bounds.midX - RouteDraft.screenWidth * zoom / 2 - camera * zoom,
                                        byY: bounds.midY - StagePainter.canvasHeight * zoom / 2)
        let motion = NSAffineTransform()
        motion.transformStruct = NSAffineTransformStruct(m11: zoom, m12: 0, m21: 0, m22: zoom,
                                                           tX: transform.tX, tY: transform.tY)
        motion.concat()
        let visible = NSRect(x: camera, y: 0, width: RouteDraft.screenWidth, height: StagePainter.canvasHeight)
        NSBezierPath(rect: visible).addClip()
        StagePainter.draw(showing, dirty: visible, zoom: zoom, selection: nil, grid: false, inactive: inactive)
        StagePainter.line(NSPoint(x: max(camera, trial.draft.length - 115), y: StagePainter.ruler + 320),
                          NSPoint(x: max(camera, trial.draft.length - 115), y: StagePainter.ruler + 612),
                          StagePainter.brass.withAlphaComponent(0.55), width: 3)
        let footY = trial.y + StagePainter.ruler
        let body = NSRect(x: trial.x - 25, y: footY - 92, width: 50, height: 92)
        StagePainter.brass.setFill()
        NSBezierPath(roundedRect: body, xRadius: 9, yRadius: 9).fill()
        StagePainter.background.setFill()
        NSBezierPath.fill(NSRect(x: trial.x - 14, y: footY - 75, width: 28, height: 14))
        StagePainter.line(NSPoint(x: trial.x - 25, y: footY), NSPoint(x: trial.x + 25, y: footY),
                          StagePainter.ink, width: 3)
        StagePainter.label(trial.reachedExit ? "EXIT REACHED  ·  R RESTART" :
                           "\(Int(trial.x)) / \(Int(trial.draft.mapWidth))   ·   \(trial.falls) FALLS",
                           at: NSPoint(x: camera + 25, y: 21), size: 22, color: StagePainter.ink)
        NSGraphicsContext.restoreGraphicsState()
    }
}
