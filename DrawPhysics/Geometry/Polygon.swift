import Foundation

/// Pure polygon predicates and measures. Everything downstream — closure detection,
/// self-intersection repair, convex decomposition, collision — is built on these five
/// or six functions, so they are kept small and individually testable.
public enum Polygon {

    // MARK: - Measures

    /// Positive for counter-clockwise winding, negative for clockwise.
    public static func signedArea(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            total += (points[j].x * points[i].y) - (points[i].x * points[j].y)
            j = i
        }
        return total / 2
    }

    public static func area(_ points: [Vec2]) -> Double { abs(signedArea(points)) }

    /// Area-weighted centroid. Falls back to the vertex mean for degenerate input so
    /// callers never receive NaN.
    public static func centroid(_ points: [Vec2]) -> Vec2 {
        guard points.count >= 3 else {
            guard !points.isEmpty else { return .zero }
            let sum = points.reduce(Vec2.zero, +)
            return sum / Double(points.count)
        }
        let a = signedArea(points)
        guard abs(a) > 1e-9 else {
            let sum = points.reduce(Vec2.zero, +)
            return sum / Double(points.count)
        }
        var cx = 0.0, cy = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            let cross = points[j].cross(points[i])
            cx += (points[j].x + points[i].x) * cross
            cy += (points[j].y + points[i].y) * cross
            j = i
        }
        return Vec2(cx / (6 * a), cy / (6 * a))
    }

    /// Second moment of area about the centroid, per unit density. Needed so drawn
    /// and authored polygons rotate with a plausible inertia instead of a guess.
    public static func momentOfInertiaAboutCentroid(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return 0 }
        let c = centroid(points)
        let p = points.map { $0 - c }
        var numerator = 0.0
        var denominator = 0.0
        var j = p.count - 1
        for i in 0..<p.count {
            let cross = abs(p[j].cross(p[i]))
            numerator += cross * (p[j].dot(p[j]) + p[j].dot(p[i]) + p[i].dot(p[i]))
            denominator += cross
            j = i
        }
        guard denominator > 1e-9 else { return 0 }
        // (1/12) * sum(cross * (a.a + a.b + b.b)) / (sum(cross)/2)  -> per unit area
        return (numerator / 12) / (denominator / 2)
    }

    public static func polylineLength(_ points: [Vec2]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count { total += points[i].distance(to: points[i - 1]) }
        return total
    }

    public static func perimeter(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return polylineLength(points) }
        return polylineLength(points) + points[points.count - 1].distance(to: points[0])
    }

    public static func boundingBox(_ points: [Vec2]) -> Rect {
        guard let first = points.first else { return Rect(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Winding

    public static func isCounterClockwise(_ points: [Vec2]) -> Bool {
        signedArea(points) > 0
    }

    /// Canonicalise winding. This is not cosmetic: edge normals are derived from
    /// vertex order, so a clockwise polygon produces inward-facing normals and
    /// objects fall straight through it.
    public static func ensureCounterClockwise(_ points: [Vec2]) -> [Vec2] {
        isCounterClockwise(points) ? points : points.reversed()
    }

    // MARK: - Convexity

    /// True when every turn has the same sign. Collinear vertices (cross == 0) are
    /// tolerated because simplification legitimately produces them.
    public static func isConvex(_ points: [Vec2], tolerance: Double = 1e-7) -> Bool {
        guard points.count >= 3 else { return false }
        var sawPositive = false
        var sawNegative = false
        let n = points.count
        for i in 0..<n {
            let a = points[i]
            let b = points[(i + 1) % n]
            let c = points[(i + 2) % n]
            let cross = (b - a).cross(c - b)
            if cross > tolerance { sawPositive = true }
            if cross < -tolerance { sawNegative = true }
            if sawPositive && sawNegative { return false }
        }
        return true
    }

    // MARK: - Containment

    public static func contains(_ point: Vec2, polygon: [Vec2]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Strict containment used by ear clipping: a vertex sitting exactly on a
    /// triangle edge must not veto the ear, or clipping can stall.
    public static func triangleContains(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2,
                                        tolerance: Double = 1e-9) -> Bool {
        let d1 = (b - a).cross(p - a)
        let d2 = (c - b).cross(p - b)
        let d3 = (a - c).cross(p - c)
        let allPositive = d1 > tolerance && d2 > tolerance && d3 > tolerance
        let allNegative = d1 < -tolerance && d2 < -tolerance && d3 < -tolerance
        return allPositive || allNegative
    }

    // MARK: - Intersection

    /// Proper crossing point of two open segments, or nil. Endpoint touches are
    /// deliberately excluded (`epsilon` keeps `t`/`u` strictly interior) because
    /// adjacent polyline segments always share an endpoint and would otherwise
    /// register as self-intersections everywhere.
    public static func segmentIntersection(_ a: Vec2, _ b: Vec2,
                                           _ c: Vec2, _ d: Vec2,
                                           epsilon: Double = 1e-9) -> Vec2? {
        let r = b - a
        let s = d - c
        let denominator = r.cross(s)
        guard abs(denominator) > 1e-12 else { return nil }   // parallel or collinear
        let t = (c - a).cross(s) / denominator
        let u = (c - a).cross(r) / denominator
        guard t > epsilon, t < 1 - epsilon, u > epsilon, u < 1 - epsilon else { return nil }
        return a + r * t
    }

    /// A polygon is simple when no pair of non-adjacent edges crosses.
    public static func isSimple(_ points: [Vec2]) -> Bool {
        firstSelfIntersection(points) == nil
    }

    public struct SelfIntersection: Equatable, Sendable {
        public let firstEdge: Int
        public let secondEdge: Int
        public let point: Vec2
    }

    public static func firstSelfIntersection(_ points: [Vec2]) -> SelfIntersection? {
        allSelfIntersections(points, stopAtFirst: true).first
    }

    public static func allSelfIntersections(_ points: [Vec2],
                                            stopAtFirst: Bool = false) -> [SelfIntersection] {
        let n = points.count
        guard n >= 4 else { return [] }
        var found: [SelfIntersection] = []
        for i in 0..<n {
            let a = points[i], b = points[(i + 1) % n]
            // j starts two edges along; the final wrap-around pair is adjacent to i == 0.
            var j = i + 2
            while j < n {
                if i == 0 && j == n - 1 { j += 1; continue }
                let c = points[j], d = points[(j + 1) % n]
                if let p = segmentIntersection(a, b, c, d) {
                    found.append(SelfIntersection(firstEdge: i, secondEdge: j, point: p))
                    if stopAtFirst { return found }
                }
                j += 1
            }
        }
        return found
    }

    // MARK: - Cleaning

    /// Drop points closer than `minSpacing` to the previously kept point. Finger
    /// input delivers dense clusters when the finger pauses; those clusters create
    /// zero-length edges that break every predicate above.
    public static func dedupe(_ points: [Vec2], minSpacing: Double) -> [Vec2] {
        guard let first = points.first else { return [] }
        var result = [first]
        for p in points.dropFirst() where p.distance(to: result[result.count - 1]) >= minSpacing {
            result.append(p)
        }
        return result
    }

    /// Remove vertices that lie on the straight line between their neighbours.
    /// Collinear vertices are legal but waste narrowphase work on every step.
    public static func removeCollinear(_ points: [Vec2], tolerance: Double = 1e-6) -> [Vec2] {
        guard points.count > 3 else { return points }
        var result: [Vec2] = []
        let n = points.count
        for i in 0..<n {
            let prev = points[(i + n - 1) % n]
            let cur = points[i]
            let next = points[(i + 1) % n]
            let cross = (cur - prev).cross(next - cur)
            let scale = max((cur - prev).length * (next - cur).length, 1e-12)
            if abs(cross) / scale > tolerance { result.append(cur) }
        }
        return result.count >= 3 ? result : points
    }
}
