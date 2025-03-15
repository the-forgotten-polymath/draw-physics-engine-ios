import Foundation

/// One contact point with its own penetration depth. Two points for a resting
/// face-on-face pair, one for a circle or a corner.
public struct ContactPoint: Sendable {
    public var position: Vec2
    public var penetration: Double
}

/// A resolved pair. `normal` always points from A towards B.
public struct Manifold {
    public let a: RigidBody
    public let b: RigidBody
    public var normal: Vec2
    public var points: [ContactPoint]
    public var restitution: Double
    public var friction: Double
}

public enum Collision {

    /// Combined material values. Geometric mean for friction is the standard choice and
    /// behaves sensibly when one surface is deliberately slippery; `max` for restitution
    /// means a bouncy ball still bounces off a dead wall.
    public static func combinedFriction(_ a: RigidBody, _ b: RigidBody) -> Double {
        (a.friction * b.friction).squareRoot()
    }

    public static func combinedRestitution(_ a: RigidBody, _ b: RigidBody) -> Double {
        max(a.restitution, b.restitution)
    }

    // MARK: - Dispatch

    public static func manifolds(between a: RigidBody, _ b: RigidBody) -> [Manifold] {
        var results: [Manifold] = []
        for shapeA in a.shapes {
            for shapeB in b.shapes {
                if var manifold = manifold(a, shapeA, b, shapeB) {
                    manifold.restitution = combinedRestitution(a, b)
                    manifold.friction = combinedFriction(a, b)
                    results.append(manifold)
                }
            }
        }
        return results
    }

    private static func manifold(_ bodyA: RigidBody, _ shapeA: Shape,
                                 _ bodyB: RigidBody, _ shapeB: Shape) -> Manifold? {
        switch (shapeA.kind, shapeB.kind) {
        case let (.circle(centerA, radiusA), .circle(centerB, radiusB)):
            return circleCircle(bodyA, bodyA.toWorld(centerA), radiusA,
                                bodyB, bodyB.toWorld(centerB), radiusB)

        case let (.circle(centerA, radiusA), .polygon(verticesB)):
            return circlePolygon(bodyA, bodyA.toWorld(centerA), radiusA,
                                 bodyB, verticesB.map { bodyB.toWorld($0) },
                                 flipped: false)

        case let (.polygon(verticesA), .circle(centerB, radiusB)):
            return circlePolygon(bodyB, bodyB.toWorld(centerB), radiusB,
                                 bodyA, verticesA.map { bodyA.toWorld($0) },
                                 flipped: true)

        case let (.polygon(verticesA), .polygon(verticesB)):
            return polygonPolygon(bodyA, verticesA.map { bodyA.toWorld($0) },
                                  bodyB, verticesB.map { bodyB.toWorld($0) })
        }
    }

    // MARK: - Circle / circle

    private static func circleCircle(_ a: RigidBody, _ centerA: Vec2, _ radiusA: Double,
                                    _ b: RigidBody, _ centerB: Vec2, _ radiusB: Double) -> Manifold? {
        let delta = centerB - centerA
        let distance = delta.length
        let sum = radiusA + radiusB
        guard distance < sum else { return nil }
        // Perfectly coincident centres have no defined normal; pick one rather than NaN.
        let normal = distance > 1e-9 ? delta / distance : Vec2(0, 1)
        let point = centerA + normal * (radiusA - (sum - distance) / 2)
        return Manifold(a: a, b: b,
                        normal: normal,
                        points: [ContactPoint(position: point, penetration: sum - distance)],
                        restitution: 0, friction: 0)
    }

    // MARK: - Circle / polygon

    /// `flipped` means the caller's A was the polygon, so the normal must be reversed
    /// before returning — the solver relies on "normal points from A to B" absolutely.
    private static func circlePolygon(_ circleBody: RigidBody, _ center: Vec2, _ radius: Double,
                                      _ polygonBody: RigidBody, _ vertices: [Vec2],
                                      flipped: Bool) -> Manifold? {
        guard vertices.count >= 3 else { return nil }

        // Deepest edge, measured by signed distance from the circle centre.
        var bestIndex = 0
        var bestSeparation = -Double.greatestFiniteMagnitude
        for i in 0..<vertices.count {
            let p = vertices[i]
            let q = vertices[(i + 1) % vertices.count]
            let outward = (q - p).perpendicularCW.normalized()
            let separation = outward.dot(center - p)
            if separation > bestSeparation {
                bestSeparation = separation
                bestIndex = i
            }
        }
        guard bestSeparation <= radius else { return nil }

        let p = vertices[bestIndex]
        let q = vertices[(bestIndex + 1) % vertices.count]

        let normalCircleToPolygon: Vec2
        let contact: Vec2
        let penetration: Double

        if bestSeparation < 1e-9 {
            // Centre is inside the polygon: push out along the least-penetrating face.
            let outward = (q - p).perpendicularCW.normalized()
            normalCircleToPolygon = -outward
            penetration = radius - bestSeparation
            contact = center + outward * bestSeparation
        } else {
            // Outside: closest point on the deepest edge decides face vs corner contact.
            let edge = q - p
            let t = ((center - p).dot(edge) / max(edge.lengthSquared, 1e-12)).clamped(to: 0...1)
            let closest = p + edge * t
            let delta = center - closest
            let distance = delta.length
            guard distance <= radius else { return nil }
            let outward = distance > 1e-9 ? delta / distance : (q - p).perpendicularCW.normalized()
            normalCircleToPolygon = -outward
            penetration = radius - distance
            contact = closest
        }

        let normal = flipped ? -normalCircleToPolygon : normalCircleToPolygon
        let a = flipped ? polygonBody : circleBody
        let b = flipped ? circleBody : polygonBody
        return Manifold(a: a, b: b,
                        normal: normal,
                        points: [ContactPoint(position: contact, penetration: penetration)],
                        restitution: 0, friction: 0)
    }

    // MARK: - Polygon / polygon

    private struct Separation {
        var edgeIndex: Int
        var value: Double
    }

    /// Separating-axis test restricted to face normals, which is sufficient and exact
    /// for convex polygons in 2D.
    private static func maximumSeparation(_ subject: [Vec2], against other: [Vec2]) -> Separation {
        var best = Separation(edgeIndex: 0, value: -Double.greatestFiniteMagnitude)
        for i in 0..<subject.count {
            let p = subject[i]
            let q = subject[(i + 1) % subject.count]
            let outward = (q - p).perpendicularCW.normalized()
            var minimum = Double.greatestFiniteMagnitude
            for v in other { minimum = min(minimum, outward.dot(v - p)) }
            if minimum > best.value {
                best = Separation(edgeIndex: i, value: minimum)
            }
        }
        return best
    }

    private static func polygonPolygon(_ bodyA: RigidBody, _ verticesA: [Vec2],
                                       _ bodyB: RigidBody, _ verticesB: [Vec2]) -> Manifold? {
        guard verticesA.count >= 3, verticesB.count >= 3 else { return nil }

        let separationA = maximumSeparation(verticesA, against: verticesB)
        if separationA.value > 0 { return nil }
        let separationB = maximumSeparation(verticesB, against: verticesA)
        if separationB.value > 0 { return nil }

        // Prefer A's face on a tie. The bias keeps the choice stable across steps when
        // two faces are near-parallel; flip-flopping the reference face makes a resting
        // box buzz.
        let useA = separationA.value >= separationB.value - 1e-6
        let referenceVertices = useA ? verticesA : verticesB
        let incidentVertices = useA ? verticesB : verticesA
        let referenceIndex = useA ? separationA.edgeIndex : separationB.edgeIndex

        let refStart = referenceVertices[referenceIndex]
        let refEnd = referenceVertices[(referenceIndex + 1) % referenceVertices.count]
        let refNormal = (refEnd - refStart).perpendicularCW.normalized()
        let refTangent = (refEnd - refStart).normalized()

        // Incident face is the one on the incident polygon most anti-parallel to it.
        var incidentIndex = 0
        var mostOpposed = Double.greatestFiniteMagnitude
        for i in 0..<incidentVertices.count {
            let p = incidentVertices[i]
            let q = incidentVertices[(i + 1) % incidentVertices.count]
            let outward = (q - p).perpendicularCW.normalized()
            let alignment = outward.dot(refNormal)
            if alignment < mostOpposed {
                mostOpposed = alignment
                incidentIndex = i
            }
        }
        var clipped = [incidentVertices[incidentIndex],
                       incidentVertices[(incidentIndex + 1) % incidentVertices.count]]

        // Clip the incident face to the reference face's side planes.
        clipped = clipSegment(clipped, normal: refTangent, offset: refTangent.dot(refStart))
        guard clipped.count == 2 else { return nil }
        clipped = clipSegment(clipped, normal: -refTangent, offset: (-refTangent).dot(refEnd))
        guard clipped.count == 2 else { return nil }

        var points: [ContactPoint] = []
        for candidate in clipped {
            let separation = refNormal.dot(candidate - refStart)
            if separation <= 0 {
                points.append(ContactPoint(position: candidate, penetration: -separation))
            }
        }
        guard !points.isEmpty else { return nil }

        // refNormal points away from the reference polygon; the solver wants A -> B.
        let normal = useA ? refNormal : -refNormal
        return Manifold(a: bodyA, b: bodyB,
                        normal: normal,
                        points: points,
                        restitution: 0, friction: 0)
    }

    /// Keep the part of a segment on the positive side of a plane, inserting the
    /// crossing point when the segment straddles it.
    private static func clipSegment(_ segment: [Vec2], normal: Vec2, offset: Double) -> [Vec2] {
        guard segment.count == 2 else { return [] }
        let d0 = normal.dot(segment[0]) - offset
        let d1 = normal.dot(segment[1]) - offset
        var result: [Vec2] = []
        if d0 >= 0 { result.append(segment[0]) }
        if d1 >= 0 { result.append(segment[1]) }
        if d0 * d1 < 0 {
            let t = d0 / (d0 - d1)
            result.append(segment[0] + (segment[1] - segment[0]) * t)
        }
        if result.count > 2 { result = Array(result.prefix(2)) }
        return result
    }
}
