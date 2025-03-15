import Foundation

/// Stage 4 of the stroke pipeline (§8.2): simple polygon -> convex pieces.
public struct ConvexDecomposer: Sendable {

    /// Sliver triangles cause physics instability. A near-zero-area body has a
    /// near-zero effective mass along one axis, so the solver answers a small overlap
    /// with an enormous impulse — the object jitters, then launches. Dropping slivers
    /// changes the silhouette imperceptibly and removes a whole class of "the game is
    /// broken" behaviour.
    public let minimumPieceArea: Double

    /// Convexity tolerance for accepting a merge. Slightly loose on purpose: after
    /// simplification, vertices that are geometrically collinear are rarely exactly
    /// collinear in floating point, and a strict test refuses almost every merge.
    public let mergeConvexityTolerance: Double

    public init(minimumPieceArea: Double = 4.0, mergeConvexityTolerance: Double = 1e-4) {
        self.minimumPieceArea = minimumPieceArea
        self.mergeConvexityTolerance = mergeConvexityTolerance
    }

    /// Decompose a simple polygon into convex, counter-clockwise pieces.
    ///
    /// Ear clipping alone is trivially correct but produces one triangle per
    /// interior vertex, and narrowphase cost scales with piece count — a 40-triangle
    /// blob measurably drops the frame rate. So: triangulate, then merge adjacent
    /// triangles while the union stays convex (Hertel-Mehlhorn style), trading a
    /// little optimality for far fewer pieces.
    public func decompose(_ polygon: [Vec2]) -> [[Vec2]] {
        let cleaned = Polygon.removeCollinear(Polygon.ensureCounterClockwise(polygon))
        guard cleaned.count >= 3 else { return [] }
        guard Polygon.area(cleaned) > minimumPieceArea else { return [] }

        if Polygon.isConvex(cleaned) {
            return [cleaned]
        }

        let triangles = Self.earClip(cleaned)
        guard !triangles.isEmpty else { return [] }

        let merged = mergeWhileConvex(triangles)
        let kept = merged.filter { Polygon.area($0) > minimumPieceArea }

        // Never return nothing. A shape small enough that every piece is a sliver is
        // still a shape the child drew, and silently deleting it looks like a bug.
        if kept.isEmpty {
            if let largest = merged.max(by: { Polygon.area($0) < Polygon.area($1) }) {
                return [largest]
            }
            return []
        }
        return kept.map { Polygon.ensureCounterClockwise($0) }
    }

    // MARK: - Triangulation

    /// Ear clipping with a guaranteed-termination fallback. Real finger input produces
    /// near-degenerate configurations where no strict ear exists in floating point; a
    /// pure "scan until an ear is found" loop hangs on those. When a full pass finds no
    /// ear we force-clip the sharpest convex vertex, which costs a little quality and
    /// makes the function total.
    public static func earClip(_ polygon: [Vec2]) -> [[Vec2]] {
        var indices = Array(0..<polygon.count)
        var triangles: [[Vec2]] = []
        var safety = polygon.count * polygon.count + 16

        while indices.count > 3 && safety > 0 {
            safety -= 1
            var clipped = false

            for offset in 0..<indices.count {
                let previous = indices[(offset + indices.count - 1) % indices.count]
                let current = indices[offset]
                let next = indices[(offset + 1) % indices.count]
                let a = polygon[previous], b = polygon[current], c = polygon[next]

                // Convex vertex in a CCW polygon means a positive turn.
                guard (b - a).cross(c - b) > 1e-9 else { continue }
                guard Polygon.area([a, b, c]) > 1e-9 else { continue }

                var containsOther = false
                for candidate in indices where candidate != previous && candidate != current && candidate != next {
                    if Polygon.triangleContains(polygon[candidate], a, b, c) {
                        containsOther = true
                        break
                    }
                }
                guard !containsOther else { continue }

                triangles.append([a, b, c])
                indices.remove(at: offset)
                clipped = true
                break
            }

            if !clipped {
                guard let forced = sharpestConvexOffset(indices, polygon) else { break }
                let previous = indices[(forced + indices.count - 1) % indices.count]
                let current = indices[forced]
                let next = indices[(forced + 1) % indices.count]
                triangles.append([polygon[previous], polygon[current], polygon[next]])
                indices.remove(at: forced)
            }
        }

        if indices.count == 3 {
            triangles.append([polygon[indices[0]], polygon[indices[1]], polygon[indices[2]]])
        }
        return triangles.filter { Polygon.area($0) > 1e-9 }
                        .map { Polygon.ensureCounterClockwise($0) }
    }

    private static func sharpestConvexOffset(_ indices: [Int], _ polygon: [Vec2]) -> Int? {
        var bestOffset: Int?
        var bestCross = -Double.greatestFiniteMagnitude
        for offset in 0..<indices.count {
            let previous = indices[(offset + indices.count - 1) % indices.count]
            let current = indices[offset]
            let next = indices[(offset + 1) % indices.count]
            let cross = (polygon[current] - polygon[previous]).cross(polygon[next] - polygon[current])
            if cross > bestCross {
                bestCross = cross
                bestOffset = offset
            }
        }
        return bestOffset
    }

    // MARK: - Merging

    /// Repeatedly merge two pieces that share an edge when the union is still convex.
    /// Restarting after each successful merge is O(n^3) in the worst case, but n is the
    /// triangle count of one drawn shape (<= ~40 after the vertex cap), so this runs in
    /// well under a millisecond and only on stroke commit, never per frame.
    public func mergeWhileConvex(_ pieces: [[Vec2]]) -> [[Vec2]] {
        var current = pieces
        var didMerge = true
        var safety = 512

        while didMerge && safety > 0 {
            safety -= 1
            didMerge = false
            outer: for i in 0..<current.count {
                for j in (i + 1)..<current.count {
                    guard let union = Self.mergeAcrossSharedEdge(current[i], current[j]) else { continue }
                    guard Polygon.isConvex(union, tolerance: mergeConvexityTolerance) else { continue }
                    let expected = Polygon.area(current[i]) + Polygon.area(current[j])
                    guard abs(Polygon.area(union) - expected) <= max(1e-6, expected * 1e-6) else { continue }
                    current.remove(at: j)
                    current[i] = union
                    didMerge = true
                    break outer
                }
            }
        }
        return current
    }

    /// Join two counter-clockwise polygons across a shared edge traversed in opposite
    /// directions. Walk A from the shared edge's end all the way round to its start,
    /// then walk B's remaining vertices. Winding is preserved by construction.
    public static func mergeAcrossSharedEdge(_ a: [Vec2], _ b: [Vec2],
                                            tolerance: Double = 1e-7) -> [Vec2]? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        for i in 0..<a.count {
            let u = a[i]
            let v = a[(i + 1) % a.count]
            for j in 0..<b.count {
                let s = b[j]
                let t = b[(j + 1) % b.count]
                // Shared edge appears reversed in the neighbour.
                guard s.isApproximatelyEqual(to: v, tolerance: tolerance),
                      t.isApproximatelyEqual(to: u, tolerance: tolerance) else { continue }

                var union: [Vec2] = []
                union.reserveCapacity(a.count + b.count - 2)
                for k in 0..<a.count { union.append(a[(i + 1 + k) % a.count]) }   // v ... u
                for k in 0..<(b.count - 2) { union.append(b[(j + 2 + k) % b.count]) }
                return Polygon.removeCollinear(union)
            }
        }
        return nil
    }
}
