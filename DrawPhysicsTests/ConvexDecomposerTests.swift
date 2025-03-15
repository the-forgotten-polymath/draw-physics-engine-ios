import XCTest
import KidsGameCore
@testable import DrawPhysics

/// The gate that blocks everything else (§7 M2). If decomposition is wrong, objects fall
/// through drawn surfaces or launch across the screen, and no amount of work elsewhere
/// makes the game playable.
final class ConvexDecomposerTests: XCTestCase {

    private let decomposer = ConvexDecomposer()

    // MARK: - Fixtures

    /// Classic L: one reflex vertex, the simplest shape ear clipping must handle.
    private var lShape: [Vec2] {
        [Vec2(0, 0), Vec2(120, 0), Vec2(120, 40), Vec2(40, 40), Vec2(40, 120), Vec2(0, 120)]
    }

    /// Five-pointed star: five reflex vertices, and the shape most likely to expose a
    /// winding bug because its interior is easy to get backwards.
    private var star: [Vec2] {
        var points: [Vec2] = []
        let outer = 100.0, inner = 42.0
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            points.append(Vec2(cos(angle) * radius, sin(angle) * radius))
        }
        return points
    }

    /// A comb. Many reflex vertices, which is where a naive merge pass starts producing
    /// non-convex unions if the area check is missing.
    private var comb: [Vec2] {
        var points: [Vec2] = [Vec2(0, 0), Vec2(240, 0), Vec2(240, 30)]
        var x = 240.0
        while x > 0 {
            points.append(Vec2(x, 30))
            points.append(Vec2(x, 90))
            points.append(Vec2(x - 20, 90))
            points.append(Vec2(x - 20, 30))
            x -= 40
        }
        points.append(Vec2(0, 30))
        return points
    }

    private var allFixtures: [(String, [Vec2])] {
        [("L", lShape), ("star", star), ("comb", comb)]
    }

    // MARK: - Named invariants (§9)

    func testEveryPieceIsConvex() {
        for (name, polygon) in allFixtures {
            let pieces = decomposer.decompose(polygon)
            XCTAssertFalse(pieces.isEmpty, "\(name) produced no pieces")
            for (index, piece) in pieces.enumerated() {
                XCTAssertGreaterThanOrEqual(piece.count, 3, "\(name) piece \(index) is degenerate")
                XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4),
                              "\(name) piece \(index) is not convex: \(piece)")
            }
        }
    }

    func testWindingIsCanonicalised() {
        for (name, polygon) in allFixtures {
            // Feed both windings. Output winding must not depend on input winding, because
            // edge normals are derived from vertex order and an inverted normal means the
            // ball falls straight through the thing the child drew.
            for (label, input) in [("ccw", polygon), ("cw", Array(polygon.reversed()))] {
                for piece in decomposer.decompose(input) {
                    XCTAssertGreaterThan(Polygon.signedArea(piece), 0,
                                         "\(name)/\(label) produced a clockwise piece")
                }
            }
        }
    }

    func testUnionAreaMatchesInputWithinTolerance() {
        for (name, polygon) in allFixtures {
            let expected = Polygon.area(polygon)
            let actual = decomposer.decompose(polygon).reduce(0) { $0 + Polygon.area($1) }
            // 1% covers the sliver pieces intentionally dropped below `minimumPieceArea`.
            XCTAssertEqual(actual, expected, accuracy: expected * 0.01,
                           "\(name): union area \(actual) vs input \(expected)")
        }
    }

    func testSliverTrianglesAreDropped() {
        // A rectangle with a hair-thin spike. The spike triangle has an area far below the
        // threshold and must not survive as a body: a near-zero-area body has near-zero
        // effective mass along one axis, so a small overlap produces an enormous impulse and
        // the object jitters, then launches.
        let spiked = [Vec2(0, 0), Vec2(200, 0), Vec2(200, 60),
                      Vec2(100, 60.05), Vec2(0, 60)]
        let pieces = decomposer.decompose(spiked)
        XCTAssertFalse(pieces.isEmpty)
        for piece in pieces {
            XCTAssertGreaterThan(Polygon.area(piece), decomposer.minimumPieceArea,
                                 "a sliver survived: \(piece)")
        }
    }

    // MARK: - Supporting behaviour

    func testConvexInputIsReturnedAsASinglePiece() {
        let square = [Vec2(0, 0), Vec2(80, 0), Vec2(80, 80), Vec2(0, 80)]
        XCTAssertEqual(decomposer.decompose(square).count, 1)
    }

    func testMergingProducesFewerPiecesThanTriangulation() {
        // The entire reason merging exists: narrowphase cost tracks piece count, so a
        // 40-triangle blob measurably drops the frame rate.
        for (name, polygon) in allFixtures {
            let canonical = Polygon.ensureCounterClockwise(polygon)
            let triangles = ConvexDecomposer.earClip(canonical).count
            let merged = decomposer.decompose(polygon).count
            XCTAssertLessThan(merged, triangles,
                              "\(name): merging did not reduce piece count (\(merged) vs \(triangles))")
        }
    }

    func testDecompositionTerminatesOnPathologicalInput() {
        // Near-duplicate and collinear vertices are what real finger input looks like after
        // simplification, and they are what makes a naive "scan until an ear appears" loop
        // spin forever.
        var pathological: [Vec2] = []
        for index in 0..<40 {
            let t = Double(index)
            pathological.append(Vec2(t, (t * 0.0001).rounded()))
        }
        pathological.append(Vec2(39, 60))
        pathological.append(Vec2(0, 60))
        let pieces = decomposer.decompose(pathological)
        for piece in pieces {
            XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4))
        }
    }

    func testMergedPieceAreaNeverExceedsTheInput() {
        // A merge that produced a non-simple union would inflate area. The area check in
        // `mergeWhileConvex` exists precisely to reject that, so assert it holds.
        for (_, polygon) in allFixtures {
            let total = decomposer.decompose(polygon).reduce(0) { $0 + Polygon.area($1) }
            XCTAssertLessThanOrEqual(total, Polygon.area(polygon) * 1.0001)
        }
    }
}
