import Foundation

/// The simulation (§8.3).
///
/// **Why this is hand-written rather than `SKPhysicsWorld`.** SpriteKit does not expose
/// any way to advance its physics world by a chosen amount of time — there is no public
/// stepping call, only "one internal step per rendered frame". That makes a fixed
/// timestep impossible, and a fixed timestep is not a nicety here: the whole replay
/// feature depends on the same input producing the same outcome, and a frame-rate-coupled
/// step size means a 60Hz device, a 120Hz device, and a device under momentary load all
/// simulate differently. So SpriteKit renders and this steps.
///
/// Determinism rules the implementation obeys, all of them load-bearing:
/// - Every collection iterated in insertion order. No `Set` or `Dictionary` iteration
///   anywhere in the step, because their order is not specified.
/// - No wall-clock time inside a step. Kinematic motion is a function of `stepIndex`.
/// - Integer step counting, never accumulated floating-point time.
///
/// What this buys, and what it does not: identical results across runs and across frame
/// rates on one device. It does NOT buy bit-identical results across devices — see
/// `OutcomeJudge` and §8.3 for how the design makes that harmless.
public final class FixedStepWorld {

    /// 120Hz. Fast enough that a small ball never tunnels through a thin drawn barrier
    /// at the speeds this game produces, cheap enough to run two substeps per display
    /// frame on a 60Hz device.
    public static let stepSeconds = 1.0 / 120.0

    public private(set) var stepIndex = 0
    public private(set) var bodies: [RigidBody] = []
    public private(set) var joints: [RevoluteJoint] = []
    
    public var latestImpulses: [Double] = []

    public var gravity = Vec2(0, -980)

    /// Velocity iterations. Twelve holds a ball on a drawn ramp without visible sink at
    /// the scene complexity this game reaches; the measured cost is in `ENGINEERING.md`.
    public var velocityIterations = 12

    /// Position iterations for the split-impulse pass. Four is enough to clear the
    /// penetration a single frame can produce at the clamped speed ceiling.
    public var positionIterations = 4

    /// Contact impulses are re-derived every step rather than warm-started. Warm starting
    /// needs stable contact-point identity across steps, and drawn geometry changes shape
    /// set the moment a child commits a stroke, so identity is exactly what is missing.
    /// Twelve iterations plus low restitution reaches the same stability without it.
    private var nextBodyID = 0
    private var accumulator = 0.0

    public init() {}

    // MARK: - Construction

    @discardableResult
    public func add(_ makeBody: (Int) -> RigidBody) -> RigidBody {
        let body = makeBody(nextBodyID)
        nextBodyID += 1
        bodies.append(body)
        return body
    }

    @discardableResult
    public func addJoint(a: RigidBody, b: RigidBody, worldAnchor: Vec2) -> RevoluteJoint {
        let joint = RevoluteJoint(a: a, b: b, worldAnchor: worldAnchor)
        joints.append(joint)
        return joint
    }

    public func body(tagged tag: BodyTag) -> RigidBody? {
        bodies.first { $0.tag == tag }
    }

    func isJointed(_ a: RigidBody, _ b: RigidBody) -> Bool {
        // Linear scan over an array that holds at most a handful of joints per level. A set
        // would be faster and would introduce unordered iteration into the step, which is
        // exactly what the determinism contract forbids.
        for joint in joints {
            if (joint.a === a && joint.b === b) || (joint.a === b && joint.b === a) { return true }
        }
        return false
    }

    public func removeBody(id: Int) {
        joints.removeAll { $0.a.id == id || $0.b.id == id }
        bodies.removeAll { $0.id == id }
    }

    // MARK: - Stepping

    /// Advance by a FIXED amount, however long the frame actually took, and report how
    /// many steps ran so the caller can drive per-step logic (stroke commits, goal
    /// judging) at simulation rate rather than frame rate.
    ///
    /// The clamp matters: without it, a stall — a push notification, an app switch —
    /// hands us a huge delta, we run hundreds of steps to catch up, that takes longer
    /// than a frame, and the next delta is bigger still. The simulation spirals and the
    /// app appears to hang.
    @discardableResult
    public func advance(by frameDelta: TimeInterval, onStep: ((Int) -> Void)? = nil) -> Int {
        accumulator += min(max(frameDelta, 0), 0.25)
        var stepsTaken = 0
        while accumulator >= Self.stepSeconds {
            stepOnce()
            onStep?(stepIndex)
            accumulator -= Self.stepSeconds
            stepsTaken += 1
        }
        return stepsTaken
    }

    public func stepOnce() {
        let dt = Self.stepSeconds

        // 1. Integrate velocities.
        for body in bodies where body.isMovable {
            body.velocity += gravity * dt
            body.velocity *= 1 / (1 + dt * body.linearDamping)
            body.angularVelocity *= 1 / (1 + dt * body.angularDamping)
        }

        // 2. Kinematic drivers. Velocity is set from the path so contacts push correctly,
        //    while position stays a pure function of the step index.
        for body in bodies {
            guard case .kinematic = body.motion, let path = body.kinematicPath else { continue }
            let next = path.position(atStep: stepIndex + 1)
            body.velocity = (next - body.position) / dt
            body.position = next
        }

        // 3. Broadphase then narrowphase, in body order.
        var constraints: [ContactConstraint] = []
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i], b = bodies[j]
                if !a.isMovable && !b.isMovable { continue }
                if a.shapes.isEmpty || b.shapes.isEmpty { continue }
                // Jointed pairs never collide. A pinned plank overlaps its own pivot by
                // definition, and letting the contact solver argue with the joint about it
                // makes the plank creep off the pin over a few hundred steps.
                if isJointed(a, b) { continue }
                guard a.worldBounds().intersects(b.worldBounds()) else { continue }
                for manifold in Collision.manifolds(between: a, b) {
                    constraints.append(contentsOf: ContactConstraint.make(from: manifold, deltaTime: dt))
                }
            }
        }

        // 4. Solve velocities. Joints and contacts share the iteration loop so a loaded
        //    see-saw converges instead of the two constraints fighting each other.
        for joint in joints { joint.prepare(deltaTime: dt) }
        for _ in 0..<velocityIterations {
            for joint in joints { joint.solve() }
            for index in constraints.indices { constraints[index].solveVelocity() }
        }

        // 5. Push penetration out using pseudo-velocity only.
        for body in bodies where body.isMovable {
            body.pseudoVelocity = .zero
            body.pseudoAngularVelocity = 0
        }
        for _ in 0..<positionIterations {
            for index in constraints.indices { constraints[index].solvePosition() }
        }

        // We only care about large impacts, not resting contacts
        let newImpulses = constraints.map { $0.accumulatedNormal }.filter { $0 > 1.0 }
        if !newImpulses.isEmpty {
            self.latestImpulses.append(contentsOf: newImpulses)
        }

        // 6. Integrate. Real velocity moves the body; pseudo-velocity only un-overlaps it
        //    and is discarded, so separating a stack costs no energy.
        for body in bodies where body.isMovable {
            body.velocity = Self.clampSpeed(body.velocity)
            body.position += (body.velocity + body.pseudoVelocity) * dt
            body.rotation += (body.angularVelocity + body.pseudoAngularVelocity) * dt
        }

        stepIndex += 1
    }

    /// Speed ceiling. At 120Hz a body moving faster than this travels more than half the
    /// ball's radius per step, which is where thin drawn barriers start being tunnelled
    /// through. Nothing in a level legitimately needs to move faster.
    public static let maximumSpeed = 2400.0

    static func clampSpeed(_ v: Vec2) -> Vec2 {
        let speed = v.length
        guard speed > maximumSpeed else { return v }
        return v * (maximumSpeed / speed)
    }

    /// Reset the accumulator without touching bodies. Called when the child pauses to
    /// draw, so the time spent drawing is not "owed" to the simulation and replayed as a
    /// sudden burst the moment play resumes.
    public func discardAccumulatedTime() {
        accumulator = 0
    }
}

/// One contact point, precomputed for the iteration loop.
struct ContactConstraint {
    let a: RigidBody
    let b: RigidBody
    let point: Vec2
    let normal: Vec2
    let tangent: Vec2
    let rA: Vec2
    let rB: Vec2
    let normalMass: Double
    let tangentMass: Double
    let bias: Double
    let restitutionTarget: Double
    let friction: Double

    var accumulatedNormal: Double = 0
    var accumulatedTangent: Double = 0
    var accumulatedPseudoNormal: Double = 0

    /// Fraction of the remaining overlap removed per step, and the overlap left alone.
    /// Clearing penetration completely in one step makes resting stacks twitch; leaving
    /// half a unit is invisible and stable.
    static let biasFactor = 0.2
    static let allowedPenetration = 0.5
    /// Below this approach speed restitution is suppressed. Otherwise a resting ball
    /// bounces forever on the microscopic velocity gravity adds each step.
    static let restitutionThreshold = 60.0

    static func make(from manifold: Manifold, deltaTime: Double) -> [ContactConstraint] {
        manifold.points.compactMap { contact in
            let a = manifold.a, b = manifold.b
            let rA = contact.position - a.position
            let rB = contact.position - b.position
            let normal = manifold.normal
            let tangent = normal.perpendicularCCW

            let normalDenominator = effectiveMass(a, b, rA, rB, normal)
            guard normalDenominator > 1e-12 else { return nil }
            let tangentDenominator = effectiveMass(a, b, rA, rB, tangent)

            let relative = b.velocity(at: contact.position) - a.velocity(at: contact.position)
            let approach = relative.dot(normal)
            let restitutionTarget = approach < -restitutionThreshold
                ? -manifold.restitution * approach
                : 0

            return ContactConstraint(
                a: a, b: b,
                point: contact.position,
                normal: normal,
                tangent: tangent,
                rA: rA, rB: rB,
                normalMass: 1 / normalDenominator,
                tangentMass: tangentDenominator > 1e-12 ? 1 / tangentDenominator : 0,
                bias: biasFactor / deltaTime * max(0, contact.penetration - allowedPenetration),
                restitutionTarget: restitutionTarget,
                friction: manifold.friction
            )
        }
    }

    private static func effectiveMass(_ a: RigidBody, _ b: RigidBody,
                                     _ rA: Vec2, _ rB: Vec2, _ axis: Vec2) -> Double {
        let crossA = rA.cross(axis)
        let crossB = rB.cross(axis)
        return a.invMass + b.invMass
            + a.invInertia * crossA * crossA
            + b.invInertia * crossB * crossB
    }

    mutating func solveVelocity() {
        let relative = b.velocity(at: point) - a.velocity(at: point)

        // Normal impulse, accumulated and clamped non-negative so the solver can pull back
        // an over-correction from an earlier iteration but never pull bodies together.
        // No penetration bias here — that is the position pass's job.
        let normalVelocity = relative.dot(normal)
        var deltaNormal = normalMass * (-normalVelocity + restitutionTarget)
        let clampedNormal = max(accumulatedNormal + deltaNormal, 0)
        deltaNormal = clampedNormal - accumulatedNormal
        accumulatedNormal = clampedNormal
        apply(impulse: normal * deltaNormal)

        // Coulomb friction, bounded by the normal impulse accumulated so far. This is what
        // lets a ball roll rather than slide, and what makes a steep drawn ramp hold a
        // crate instead of shedding it.
        guard tangentMass > 0 else { return }
        let updatedRelative = b.velocity(at: point) - a.velocity(at: point)
        let tangentVelocity = updatedRelative.dot(tangent)
        var deltaTangent = tangentMass * (-tangentVelocity)
        let maxTangent = friction * accumulatedNormal
        let clampedTangent = (accumulatedTangent + deltaTangent).clamped(to: -maxTangent...maxTangent)
        deltaTangent = clampedTangent - accumulatedTangent
        accumulatedTangent = clampedTangent
        apply(impulse: tangent * deltaTangent)
    }

    mutating func solvePosition() {
        guard bias > 0 else { return }
        let relative = b.pseudoVelocity(at: point) - a.pseudoVelocity(at: point)
        var delta = normalMass * (-relative.dot(normal) + bias)
        let clamped = max(accumulatedPseudoNormal + delta, 0)
        delta = clamped - accumulatedPseudoNormal
        accumulatedPseudoNormal = clamped
        applyPseudo(impulse: normal * delta)
    }

    private func apply(impulse: Vec2) {
        if a.isMovable {
            a.velocity -= impulse * a.invMass
            a.angularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.velocity += impulse * b.invMass
            b.angularVelocity += rB.cross(impulse) * b.invInertia
        }
    }

    private func applyPseudo(impulse: Vec2) {
        if a.isMovable {
            a.pseudoVelocity -= impulse * a.invMass
            a.pseudoAngularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.pseudoVelocity += impulse * b.invMass
            b.pseudoAngularVelocity += rB.cross(impulse) * b.invInertia
        }
    }
}
