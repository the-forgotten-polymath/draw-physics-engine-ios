import Foundation

/// Stage 1-3 of the stroke pipeline (§8.2): simplify, classify closure, repair
/// self-intersection. Stage 4 (decomposition) lives in `ConvexDecomposer`.
public struct StrokeSimplifier: Sendable {

    public struct Configuration: Sendable {
        /// Ramer-Douglas-Peucker tolerance for closed shapes, in scene units.
        /// Tuned by eye on device: below ~2 the vertex count stays high enough to
        /// slow decomposition; above ~5 a child's deliberate curve visibly squares off.
        public var closedTolerance: Double = 3.0
        /// Open strokes can be simplified harder — a barrier reads as a line, and
        /// every extra vertex is another quad in the chain.
        public var openTolerance: Double = 5.0
        /// Endpoints within this distance mean "the child meant to close the loop".
        public var closureDistance: Double = 28.0
        public var minimumSpacing: Double = 2.0
        /// Hard cap on vertices after simplification. Decomposition is O(n^2)-ish and
        /// a 400-vertex blob would stall the frame it is committed on.
        public var maximumVertices: Int = 40
        /// A closed candidate must enclose at least this much area, otherwise it is a
        /// scribble that happens to end where it started and is better as a chain.
        public var minimumClosedArea: Double = 250.0
        public var repairIterations: Int = 8
        public var chainThickness: Double = 11.0

        public init() {}
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Entry point

    /// Full classification + repair. Returns nil only for input that cannot become
    /// anything meaningful (a tap, or a stroke shorter than the minimum).
    /// `minimumStrokeLength` is enforced by `InkMeter`, not here.
    public func process(rawPoints: [Vec2]) -> ProcessedStroke? {
        let cleaned = Polygon.dedupe(rawPoints, minSpacing: configuration.minimumSpacing)
        guard cleaned.count >= 2 else { return nil }

        if let closed = closedCandidate(from: cleaned) {
            return closed
        }

        let simplified = Self.simplify(cleaned, tolerance: configuration.openTolerance)
        guard simplified.count >= 2 else { return nil }
        return ProcessedStroke(simplifiedPoints: simplified,
                               isClosed: false,
                               enclosedArea: 0,
                               inkLength: Polygon.polylineLength(simplified))
    }

    public struct ProcessedStroke: Equatable, Sendable {
        public var simplifiedPoints: [Vec2]
        public var isClosed: Bool
        public var enclosedArea: Double
        public var inkLength: Double
    }

    // MARK: - Stage 2: closure detection

    private func closedCandidate(from cleaned: [Vec2]) -> ProcessedStroke? {
        guard cleaned.count >= 4 else { return nil }
        let span = cleaned[0].distance(to: cleaned[cleaned.count - 1])
        guard span <= configuration.closureDistance else { return nil }
        // A short there-and-back stroke also has near-coincident endpoints. Require the
        // path to be meaningfully longer than the gap it closes.
        guard Polygon.polylineLength(cleaned) > configuration.closureDistance * 2 else { return nil }

        var ring = cleaned
        // The trailing point is within closureDistance of the leading one; keeping both
        // gives a near-zero-length closing edge, which every predicate hates.
        if ring.count >= 4, ring[0].distance(to: ring[ring.count - 1]) < configuration.minimumSpacing * 2 {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return nil }

        var simplified = Self.simplifyRing(ring, tolerance: configuration.closedTolerance)
        guard simplified.count >= 3 else { return nil }

        simplified = Self.repairSelfIntersections(simplified,
                                                 iterations: configuration.repairIterations)
        guard simplified.count >= 3 else { return nil }

        simplified = Self.enforceVertexCap(simplified, cap: configuration.maximumVertices)
        simplified = Polygon.removeCollinear(simplified)
        simplified = Polygon.ensureCounterClockwise(simplified)

        let enclosed = Polygon.area(simplified)
        guard enclosed >= configuration.minimumClosedArea else { return nil }

        return ProcessedStroke(simplifiedPoints: simplified,
                               isClosed: true,
                               enclosedArea: enclosed,
                               inkLength: Polygon.perimeter(simplified))
    }

    // MARK: - Stage 1: Ramer-Douglas-Peucker

    /// Iterative RDP. Recursion depth is O(n) in the worst case (a monotone spiral,
    /// which children draw constantly), so the stack is explicit.
    public static func simplify(_ points: [Vec2], tolerance: Double) -> [Vec2] {
        guard points.count > 2, tolerance > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var worstIndex = -1
            var worstDistance = 0.0
            for i in (start + 1)..<end {
                let d = perpendicularDistance(points[i], from: points[start], to: points[end])
                if d > worstDistance {
                    worstDistance = d
                    worstIndex = i
                }
            }
            if worstDistance > tolerance, worstIndex > 0 {
                keep[worstIndex] = true
                stack.append((start, worstIndex))
                stack.append((worstIndex, end))
            }
        }
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// RDP on a closed ring. Splitting at the two most distant vertices first stops
    /// the algorithm from collapsing a loop into a line, which is what happens if you
    /// naively run open-path RDP from index 0 to index 0.
    public static func simplifyRing(_ ring: [Vec2], tolerance: Double) -> [Vec2] {
        guard ring.count > 4 else { return ring }
        var farthestIndex = 0
        var farthestDistance = 0.0
        for i in 1..<ring.count {
            let d = ring[i].distance(to: ring[0])
            if d > farthestDistance {
                farthestDistance = d
                farthestIndex = i
            }
        }
        guard farthestIndex > 1, farthestIndex < ring.count - 1 else {
            return simplify(ring, tolerance: tolerance)
        }
        let firstHalf = simplify(Array(ring[0...farthestIndex]), tolerance: tolerance)
        let secondHalf = simplify(Array(ring[farthestIndex..<ring.count]) + [ring[0]],
                                  tolerance: tolerance)
        // Drop the duplicated join vertex and the duplicated wrap vertex.
        var merged = firstHalf
        if secondHalf.count > 2 {
            merged.append(contentsOf: secondHalf.dropFirst().dropLast())
        }
        return merged
    }

    public static func perpendicularDistance(_ p: Vec2, from a: Vec2, to b: Vec2) -> Double {
        let ab = b - a
        let lengthSquared = ab.lengthSquared
        guard lengthSquared > 1e-12 else { return p.distance(to: a) }
        let t = ((p - a).dot(ab) / lengthSquared).clamped(to: 0...1)
        return p.distance(to: a + ab * t)
    }

    private static func enforceVertexCap(_ points: [Vec2], cap: Int) -> [Vec2] {
        guard points.count > cap else { return points }
        var tolerance = 4.0
        var result = points
        var guardCounter = 0
        while result.count > cap && guardCounter < 12 {
            result = simplifyRing(points, tolerance: tolerance)
            tolerance *= 1.6
            guardCounter += 1
        }
        return result
    }

    // MARK: - Stage 3: self-intersection repair

    /// A self-intersecting polygon has no well-defined interior, so decomposition is
    /// meaningless on it. General repair (planar subdivision, then boolean union) is a
    /// much larger problem than this game needs.
    ///
    /// Instead: take the largest simple sub-loop. For a child's accidental crossing —
    /// a loop closed slightly past its own start, a figure-of-eight where one lobe is
    /// clearly the intended shape — the biggest simple loop is nearly always what they
    /// meant. The limitation is documented in `ENGINEERING.md`: a deliberate
    /// figure-of-eight loses its smaller lobe.
    public static func repairSelfIntersections(_ polygon: [Vec2], iterations: Int) -> [Vec2] {
        var current = polygon
        for _ in 0..<max(iterations, 1) {
            let intersections = Polygon.allSelfIntersections(current)
            if intersections.isEmpty { return current }
            guard let best = largestSubloop(of: current, using: intersections) else {
                return current
            }
            // No progress possible: bail out with what we have rather than spin.
            if best.count >= current.count { return best }
            current = best
        }
        return current
    }

    /// For a crossing between edge `i` and edge `j`, the vertices strictly between
    /// them plus the crossing point form a closed loop. Every crossing yields one
    /// such candidate; the largest by area wins.
    private static func largestSubloop(of polygon: [Vec2],
                                       using intersections: [Polygon.SelfIntersection]) -> [Vec2]? {
        var bestLoop: [Vec2]?
        var bestArea = 0.0
        for hit in intersections {
            let lower = hit.firstEdge + 1
            let upper = hit.secondEdge
            guard lower <= upper else { continue }
            var loop = [hit.point]
            for index in lower...upper { loop.append(polygon[index]) }
            guard loop.count >= 3 else { continue }
            let a = Polygon.area(loop)
            if a > bestArea {
                bestArea = a
                bestLoop = loop
            }
            // The complement is also a candidate: everything outside the crossing.
            var complement = [hit.point]
            var index = (hit.secondEdge + 1) % polygon.count
            var stepGuard = 0
            while index != lower && stepGuard <= polygon.count {
                complement.append(polygon[index])
                index = (index + 1) % polygon.count
                stepGuard += 1
            }
            if complement.count >= 3 {
                let ca = Polygon.area(complement)
                if ca > bestArea {
                    bestArea = ca
                    bestLoop = complement
                }
            }
        }
        return bestLoop
    }

    // MARK: - Open strokes become a thin chain

    /// One convex quad per simplified segment, each extended half a thickness along
    /// its own direction so the joints overlap instead of leaving a notch a ball can
    /// catch on. All quads end up in a single static body.
    public static func chainPieces(_ points: [Vec2], thickness: Double) -> [[Vec2]] {
        guard points.count >= 2, thickness > 0 else { return [] }
        let half = thickness / 2
        var pieces: [[Vec2]] = []
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let direction = (b - a).normalized()
            guard direction.lengthSquared > 0 else { continue }
            let normal = direction.perpendicularCCW
            let start = a - direction * half
            let end = b + direction * half
            let quad = [
                start + normal * half,
                end + normal * half,
                end - normal * half,
                start - normal * half
            ]
            pieces.append(Polygon.ensureCounterClockwise(quad))
        }
        return pieces
    }
}
