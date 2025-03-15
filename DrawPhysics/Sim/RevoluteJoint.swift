import Foundation

/// A pin. Used for see-saws and hinged flaps (Middle band onwards).
///
/// Solved as a 2-DOF point-coincidence constraint with sequential impulses, in the same
/// iteration loop as contacts, so a see-saw with a ball resting on it converges instead
/// of fighting itself.
public final class RevoluteJoint {
    public let a: RigidBody
    public let b: RigidBody
    public let localAnchorA: Vec2
    public let localAnchorB: Vec2

    private var rA: Vec2 = .zero
    private var rB: Vec2 = .zero
    private var bias: Vec2 = .zero
    private var m00 = 0.0, m01 = 0.0, m10 = 0.0, m11 = 0.0

    /// Positional drift correction strength. Low enough not to add energy, high enough
    /// that a loaded pivot does not visibly sag.
    private let positionCorrection = 0.2
    private let allowedSlop = 0.05

    public init(a: RigidBody, b: RigidBody, worldAnchor: Vec2) {
        self.a = a
        self.b = b
        // Anchors stored in each body's local frame so the constraint survives rotation.
        self.localAnchorA = (worldAnchor - a.position).rotated(by: -a.rotation)
        self.localAnchorB = (worldAnchor - b.position).rotated(by: -b.rotation)
    }

    public func prepare(deltaTime: Double) {
        rA = localAnchorA.rotated(by: a.rotation)
        rB = localAnchorB.rotated(by: b.rotation)

        let invMassSum = a.invMass + b.invMass
        // K = sum over bodies of (invMass * I + invInertia * skew(r) * skew(r)^T)
        m00 = invMassSum + a.invInertia * rA.y * rA.y + b.invInertia * rB.y * rB.y
        m01 = -a.invInertia * rA.x * rA.y - b.invInertia * rB.x * rB.y
        m10 = m01
        m11 = invMassSum + a.invInertia * rA.x * rA.x + b.invInertia * rB.x * rB.x

        let separation = (b.position + rB) - (a.position + rA)
        let magnitude = separation.length
        let corrected = max(magnitude - allowedSlop, 0)
        bias = magnitude > 1e-9
            ? separation.normalized() * (positionCorrection / deltaTime * corrected)
            : .zero
    }

    public func solve() {
        let velocityA = a.velocity + rA.perpendicularCCW * a.angularVelocity
        let velocityB = b.velocity + rB.perpendicularCCW * b.angularVelocity
        let relative = velocityB - velocityA + bias

        let determinant = m00 * m11 - m01 * m10
        guard abs(determinant) > 1e-12 else { return }
        let rhs = -relative
        let impulse = Vec2((m11 * rhs.x - m01 * rhs.y) / determinant,
                           (m00 * rhs.y - m10 * rhs.x) / determinant)

        if a.isMovable {
            a.velocity -= impulse * a.invMass
            a.angularVelocity -= rA.cross(impulse) * a.invInertia
        }
        if b.isMovable {
            b.velocity += impulse * b.invMass
            b.angularVelocity += rB.cross(impulse) * b.invInertia
        }
    }
}
