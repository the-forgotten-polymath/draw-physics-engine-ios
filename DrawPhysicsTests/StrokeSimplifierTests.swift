import XCTest
import KidsGameCore
@testable import DrawPhysics

final class StrokeSimplifierTests: XCTestCase {

    private let simplifier = StrokeSimplifier()
    private let pipeline = StrokePipeline()

    // MARK: - Helpers

    /// Dense sampled input, which is what a finger actually produces — a few hundred points
    /// with sub-pixel spacing, not a tidy polygon.
    private func sampledCircle(centre: Vec2, radius: Double, samples: Int = 220,
                              sweep: Double = 2 * .pi) -> [Vec2] {
        (0..<samples).map { index in
            let angle = sweep * Double(index) / Double(samples)
            return centre + Vec2(cos(angle) * radius, sin(angle) * radius)
        }
    }

    // MARK: - Named invariants (§9)

    func testSelfIntersectingLoopYieldsValidGeometry() {
        // A figure-of-eight: two lobes crossing in the middle. A self-intersecting polygon
        // has no well-defined interior, so decomposition on it is meaningless — the pipeline
        // must repair it into a simple loop first.
        var points: [Vec2] = []
        for index in 0..<200 {
            let t = 2 * .pi * Double(index) / 200
            points.append(Vec2(140 + cos(t) * 90, 300 + sin(2 * t) * 70))
        }
        points.append(points[0])

        guard let processed = simplifier.process(rawPoints: points) else {
            return XCTFail("a large self-crossing loop should not be discarded")
        }
        XCTAssertTrue(processed.isClosed)
        XCTAssertTrue(Polygon.isSimple(processed.simplifiedPoints),
                      "repair left a self-intersection behind")
        XCTAssertGreaterThan(Polygon.area(processed.simplifiedPoints), 0)

        let pieces = ConvexDecomposer().decompose(processed.simplifiedPoints)
        XCTAssertFalse(pieces.isEmpty, "repaired geometry produced no bodies")
        for piece in pieces {
            XCTAssertTrue(Polygon.isConvex(piece, tolerance: 1e-4))
            XCTAssertGreaterThan(Polygon.area(piece), 0)
        }
    }

    func testClosureDetectionDistinguishesLoopFromLine() {
        // A child notices this distinction immediately: a closed loop should be a solid blob
        // things rest on, an open line a thin barrier they slide along.
        let loop = sampledCircle(centre: Vec2(300, 400), radius: 80)
        guard let closed = simplifier.process(rawPoints: loop) else {
            return XCTFail("a full circle should classify as closed")
        }
        XCTAssertTrue(closed.isClosed)
        XCTAssertGreaterThan(closed.enclosedArea, 0)

        let line = (0..<120).map { Vec2(60 + Double($0) * 4, 500 - Double($0) * 1.5) }
        guard let open = simplifier.process(rawPoints: line) else {
            return XCTFail("a long line should classify as open")
        }
        XCTAssertFalse(open.isClosed)
        XCTAssertEqual(open.enclosedArea, 0)

        // Three-quarters of a circle: endpoints far apart, so it stays open even though it
        // curves back on itself.
        let arc = sampledCircle(centre: Vec2(300, 400), radius: 80, sweep: 1.5 * .pi)
        XCTAssertEqual(simplifier.process(rawPoints: arc)?.isClosed, false)
    }

    func testSimplificationPreservesShapeWithinTolerance() {
        let radius = 90.0
        let circle = sampledCircle(centre: Vec2(200, 200), radius: radius, samples: 300)
        guard let processed = simplifier.process(rawPoints: circle) else {
            return XCTFail("circle rejected")
        }
        // Vertex count must come down a long way or decomposition is slow...
        XCTAssertLessThanOrEqual(processed.simplifiedPoints.count,
                                 simplifier.configuration.maximumVertices)
        // ...but the shape the child drew must still be recognisably what they drew. An
        // inscribed polygon always loses a little area; 6% is the measured budget.
        let expected = .pi * radius * radius
        XCTAssertEqual(Polygon.area(processed.simplifiedPoints), expected,
                       accuracy: expected * 0.06)
    }

    func testOpenStrokeBecomesAThinChainOfConvexQuads() {
        let line = (0..<80).map { Vec2(60 + Double($0) * 6, 420 + sin(Double($0) / 9) * 40) }
        let budget = InkBudget(total: 5000)
        guard case let .accepted(shape, _) = pipeline.makeShape(id: 0, rawPoints: line,
                                                               source: .freehand, budget: budget) else {
            return XCTFail("open stroke rejected")
        }
        XCTAssertFalse(shape.isClosed)
        XCTAssertFalse(shape.convexPieces.isEmpty)
        for quad in shape.convexPieces {
            XCTAssertEqual(quad.count, 4)
            XCTAssertTrue(Polygon.isConvex(quad, tolerance: 1e-6))
            XCTAssertGreaterThan(Polygon.signedArea(quad), 0)
        }
    }

    // MARK: - Supporting behaviour

    func testTapsAndFlecksAreRejected() {
        XCTAssertNil(simplifier.process(rawPoints: [Vec2(100, 100)]))
        let fleck = [Vec2(100, 100), Vec2(103, 101), Vec2(105, 100)]
        let budget = InkBudget(total: 1000)
        guard case let .rejected(reason) = pipeline.makeShape(id: 0, rawPoints: fleck,
                                                             source: .freehand, budget: budget) else {
            return XCTFail("a 5-unit fleck must not become a body")
        }
        XCTAssertEqual(reason, .tooShort)
    }

    func testTinyClosedScribbleIsTreatedAsALineNotASolid() {
        // Endpoints coincide but almost no area is enclosed. Making that a "solid" gives a
        // near-degenerate body, which is the launch-across-the-screen bug.
        let scribble = sampledCircle(centre: Vec2(200, 200), radius: 6, samples: 40)
        let processed = simplifier.process(rawPoints: scribble)
        XCTAssertNotEqual(processed?.isClosed, true)
    }

    func testRamerDouglasPeuckerKeepsEndpoints() {
        let points = (0..<50).map { Vec2(Double($0) * 10, 0) }
        let simplified = StrokeSimplifier.simplify(points, tolerance: 2)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
        XCTAssertEqual(simplified.count, 2, "a straight line should reduce to its endpoints")
    }

    func testSimplificationIsDeterministic() {
        let stroke = sampledCircle(centre: Vec2(310, 480), radius: 77, samples: 251)
        let first = simplifier.process(rawPoints: stroke)
        let second = simplifier.process(rawPoints: stroke)
        XCTAssertEqual(first, second)
    }
}
