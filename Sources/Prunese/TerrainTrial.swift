import Foundation

struct TrialInput {
    let horizontal: Double
    let jump: Bool
    let down: Bool
}

struct TerrainTrial {
    let draft: RouteDraft
    private let platforms: [RouteItem]
    private let helmets: [RouteItem]
    private let gravity: Double
    private let takeoffSpeed: Double
    private let traction: Double
    private let wind: Double
    private let pull: Double

    private(set) var x = RouteDraft.spawnX
    private(set) var y = RouteDraft.floorY
    private(set) var vx = 0.0
    private(set) var vy = 0.0
    private(set) var time = 0.0
    private(set) var falls = 0
    private(set) var reachedExit = false
    private(set) var helmet: UUID?
    private var support: RouteItem?
    private var grounded = true
    private var coyote = 0.0
    private var buffer = 0.0
    private var heldJump = false
    private var extraJump = true

    init(draft: RouteDraft) {
        self.draft = draft
        platforms = draft.items.filter { $0.layer.isPlatform && $0.isValidTuple }
        helmets = draft.items.filter { $0.layer == .pickups && $0.kind == "helmet" }
        let planetary = draft.table == .planets
        gravity = planetary ? max(1, draft.fields["gravity"]?.number ?? 1880) : 1880
        takeoffSpeed = planetary ? max(1, draft.fields["jump"]?.number ?? 760) : 760
        traction = planetary ? max(0.01, draft.fields["traction"]?.number ?? 1) : 1
        wind = planetary ? (draft.fields["wind"]?.number ?? 0) : 0
        pull = planetary ? (draft.fields["pull"]?.number ?? 0) : 0
    }

    mutating func advance(_ input: TrialInput, by dt: Double) {
        guard !reachedExit else { return }
        let previousTime = time
        time += dt
        let pressed = input.jump && !heldJump
        heldJump = input.jump

        if let support {
            y += height(of: support, at: time) - height(of: support, at: previousTime)
        }
        coyote = grounded ? 0.13 : max(0, coyote - dt)
        buffer = pressed ? 0.14 : max(0, buffer - dt)
        if input.down, pressed, support?.layer == .ledges {
            y += 9
            vy = 70
            support = nil
            grounded = false
            coyote = 0
            buffer = 0
        } else if buffer > 0, grounded || coyote > 0 || helmet != nil && extraJump {
            if !grounded, coyote == 0 { extraJump = false }
            vy = -takeoffSpeed
            support = nil
            grounded = false
            coyote = 0
            buffer = 0
        }

        let pullDirection = x == draft.boss ? 0.0 : x < draft.boss ? 1.0 : -1.0
        let drift = wind + pullDirection * pull
        let target = min(1, max(-1, input.horizontal)) * 374 + drift
        vx = approach(vx, target, by: (grounded ? 2250 * traction : 1350) * dt)
        if input.horizontal == 0 {
            vx = approach(vx, drift, by: (grounded ? 1850 * traction : 430) * dt)
        }
        x = min(max(18, draft.mapWidth - 18), max(18, x + vx * dt))
        let previousY = y
        vy = min(1020, vy + gravity * (heldJump && vy < 0 ? 0.66 : 1) * dt)
        y += vy * dt

        support = nil
        grounded = false
        if vy >= 0 {
            var highest = Double.infinity
            for span in platforms where isOpen(span) && x + 25 > span.x && x - 25 < span.x + span.width {
                let top = height(of: span, at: time)
                if previousY <= height(of: span, at: previousTime) + 5, y >= top, top < highest {
                    highest = top
                    support = span
                }
            }
            if support != nil {
                y = highest
                vy = 0
                grounded = true
                extraJump = true
            }
        }
        if helmet == nil, let item = helmets.first(where: { abs($0.x - x) < 42 && abs(draft.top(for: $0) - (y - 92)) < 58 }) {
            helmet = item.id
        }
        if y > RouteDraft.height + 120 {
            falls += 1
            x = RouteDraft.spawnX
            y = RouteDraft.floorY
            vx = 0
            vy = 0
            coyote = 0
            buffer = 0
            grounded = true
            extraJump = true
            helmet = nil
        }
        reachedExit = x > draft.length - 115 && y < RouteDraft.height
    }

    func height(of span: RouteItem, at time: Double) -> Double {
        (span.y ?? RouteDraft.floorY) + sin(time * 1.3 + span.x / 170) * span.travel
    }

    func isOpen(_ span: RouteItem) -> Bool {
        span.gate != "moon-air" || draft.stage == 22 && helmet != nil
    }

    private func approach(_ value: Double, _ target: Double, by amount: Double) -> Double {
        value < target ? min(target, value + amount) : max(target, value - amount)
    }
}
