import Foundation

/// One convex collider in body-local coordinates.
///
/// The ball is a real circle rather than a polygon approximation. A 20-gon rolls with
/// a faint but perceptible bump every 18 degrees, and "the ball rolls down the ramp you
/// drew" is the core sensation of the game.
public struct Shape: Sendable {
    public enum Kind: Sendable {
        case circle(center: Vec2, radius: Double)
        /// Counter-clockwise, convex, local space.
        case polygon(vertices: [Vec2])
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static func circle(center: Vec2 = .zero, radius: Double) -> Shape {
        Shape(kind: .circle(center: center, radius: radius))
    }

    public static func polygon(_ vertices: [Vec2]) -> Shape {
        Shape(kind: .polygon(vertices: Polygon.ensureCounterClockwise(vertices)))
    }

    public var area: Double {
        switch kind {
        case let .circle(_, radius): return .pi * radius * radius
        case let .polygon(vertices): return Polygon.area(vertices)
        }
    }

    /// Second moment about the body origin, per unit density.
    public var momentAboutOrigin: Double {
        switch kind {
        case let .circle(center, radius):
            let own = 0.5 * (.pi * radius * radius) * radius * radius
            return own + (.pi * radius * radius) * center.lengthSquared
        case let .polygon(vertices):
            let a = Polygon.area(vertices)
            let c = Polygon.centroid(vertices)
            // Parallel axis theorem, per unit density: I_origin = A * (I_c/A + |c|^2).
            return a * (Polygon.momentOfInertiaAboutCentroid(vertices) + c.lengthSquared)
        }
    }

    public func localBounds() -> Rect {
        switch kind {
        case let .circle(center, radius):
            return Rect(x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2)
        case let .polygon(vertices):
            return Polygon.boundingBox(vertices)
        }
    }
}

public enum BodyMotion: Sendable {
    /// Never moves. Walls, the cup, everything the child draws.
    case `static`
    /// Moves on a schedule the simulation dictates, unaffected by collisions.
    case kinematic
    case dynamic
}

/// Semantic role, used by the goal judge and the renderer. A string tag rather than an
/// enum because levels are authored data and must be able to name their own bodies.
public struct BodyTag: Equatable, Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static let wall = BodyTag("wall")
    public static let floor = BodyTag("floor")
}

public final class RigidBody {
    public let id: Int
    public var tag: BodyTag
    public var shapes: [Shape]
    public var motion: BodyMotion

    public var position: Vec2
    public var rotation: Double
    public var velocity: Vec2
    public var angularVelocity: Double

    /// Split-impulse scratch. Penetration is pushed out with a SEPARATE velocity that is
    /// applied to position and then thrown away, never added to real velocity.
    ///
    /// The alternative — folding the penetration bias into the normal impulse — literally
    /// injects energy: a ball landing hard enough to overlap by 10 units gets a couple of
    /// hundred units per second of free upward speed and visibly pops off the surface. That
    /// is the "why did the ball launch" bug, and it is a solver choice, not a tuning problem.
    public var pseudoVelocity: Vec2 = .zero
    public var pseudoAngularVelocity: Double = 0

    public var invMass: Double
    public var invInertia: Double

    public var restitution: Double
    public var friction: Double
    public var linearDamping: Double
    public var angularDamping: Double

    /// Kinematic bodies follow this. Given the fixed step index, position is a pure
    /// function of time — which keeps moving platforms exactly as reproducible as
    /// everything else.
    public var kinematicPath: KinematicPath?

    public init(id: Int,
                tag: BodyTag,
                shapes: [Shape],
                motion: BodyMotion,
                position: Vec2,
                rotation: Double = 0,
                density: Double = 1.0,
                restitution: Double = 0.15,
                friction: Double = 0.55,
                linearDamping: Double = 0.06,
                angularDamping: Double = 0.10) {
        self.id = id
        self.tag = tag
        self.shapes = shapes
        self.motion = motion
        self.position = position
        self.rotation = rotation
        self.velocity = .zero
        self.angularVelocity = 0
        self.restitution = restitution
        self.friction = friction
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.kinematicPath = nil

        switch motion {
        case .static, .kinematic:
            self.invMass = 0
            self.invInertia = 0
        case .dynamic:
            let area = shapes.reduce(0.0) { $0 + $1.area }
            let mass = max(area * density, 1e-6)
            let moment = shapes.reduce(0.0) { $0 + $1.momentAboutOrigin } * density
            self.invMass = 1 / mass
            self.invInertia = moment > 1e-9 ? 1 / moment : 0
        }
    }

    public var isMovable: Bool {
        if case .dynamic = motion { return true }
        return false
    }

    public func toWorld(_ local: Vec2) -> Vec2 {
        position + local.rotated(by: rotation)
    }

    public func worldVertices(of shape: Shape) -> [Vec2] {
        guard case let .polygon(vertices) = shape.kind else { return [] }
        return vertices.map { toWorld($0) }
    }

    public func worldBounds() -> Rect {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for shape in shapes {
            switch shape.kind {
            case let .circle(center, radius):
                let c = toWorld(center)
                minX = min(minX, c.x - radius); maxX = max(maxX, c.x + radius)
                minY = min(minY, c.y - radius); maxY = max(maxY, c.y + radius)
            case let .polygon(vertices):
                for local in vertices {
                    let w = toWorld(local)
                    minX = min(minX, w.x); maxX = max(maxX, w.x)
                    minY = min(minY, w.y); maxY = max(maxY, w.y)
                }
            }
        }
        guard minX <= maxX else { return Rect(x: position.x, y: position.y, width: 0, height: 0) }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func applyImpulse(_ impulse: Vec2, at contact: Vec2) {
        guard isMovable else { return }
        velocity += impulse * invMass
        angularVelocity += (contact - position).cross(impulse) * invInertia
    }

    public func velocity(at worldPoint: Vec2) -> Vec2 {
        velocity + (worldPoint - position).perpendicularCCW * angularVelocity
    }

    public func pseudoVelocity(at worldPoint: Vec2) -> Vec2 {
        pseudoVelocity + (worldPoint - position).perpendicularCCW * pseudoAngularVelocity
    }
}

/// A closed-form kinematic path. Evaluated from the integer step index, never from
/// wall-clock time, so a moving platform is in exactly the same place on step 900 of
/// every run.
public struct KinematicPath: Sendable {
    public var origin: Vec2
    public var travel: Vec2
    public var periodSteps: Int

    public init(origin: Vec2, travel: Vec2, periodSteps: Int) {
        self.origin = origin
        self.travel = travel
        self.periodSteps = max(periodSteps, 1)
    }

    public func position(atStep step: Int) -> Vec2 {
        let phase = Double(step % periodSteps) / Double(periodSteps)
        // Triangle wave: linear out, linear back. Constant speed reads as a machine,
        // which is easier for a child to plan around than a sinusoid.
        let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        return origin + travel * t
    }
}
