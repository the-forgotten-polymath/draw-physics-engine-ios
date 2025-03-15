import XCTest
import KidsGameCore
@testable import DrawPhysics

final class InkMeterTests: XCTestCase {

    private let meter = InkMeter()
    private let pipeline = StrokePipeline()

    /// Every band's most generous budget. If the blob strategy fails against the largest
    /// budget in the game it fails against all of them.
    private var bandBudgets: [(AgeBand, Double)] {
        [(.early, 2600), (.middle, 1500), (.upper, 950)]
    }

    // MARK: - Named invariants (§9)

    func testSingleGiantBlobExceedsEveryBandBudget() {
        // Without an area charge this is the answer to every level in the game: enclose the
        // ball and the cup in one huge shape and let gravity do the rest. Its outline is
        // short, so arc length alone barely notices.
        let blob = (0..<160).map { index -> Vec2 in
            let angle = 2 * .pi * Double(index) / 160
            return Vec2(375 + cos(angle) * 330, 500 + sin(angle) * 440)
        }
        guard let processed = StrokeSimplifier().process(rawPoints: blob) else {
            return XCTFail("the blob should be a valid closed shape — it just must be unaffordable")
        }
        XCTAssertTrue(processed.isClosed)
        let cost = meter.cost(of: processed)

        for (band, budget) in bandBudgets {
            XCTAssertGreaterThan(cost, budget,
                                 "\(band) could afford the blob: cost \(cost) vs budget \(budget)")
        }

        // And show the charge is doing the work, not the perimeter: on perimeter alone it
        // would be affordable at the early band, which is exactly the hole being closed.
        XCTAssertLessThan(processed.inkLength, 2600)
    }

    func testUndoRefundsExactlyTheStrokeCost() {
        var budget = InkBudget(total: 2000)
        let costs = [123.5, 47.25, 512.0]
        for cost in costs { XCTAssertTrue(budget.charge(cost)) }
        XCTAssertEqual(budget.spent, costs.reduce(0, +), accuracy: 1e-12)

        // Exact, not approximate. Undo is unlimited and free, so a rounding error here leaks
        // budget on every undo and eventually makes a solvable level unsolvable.
        XCTAssertEqual(budget.refundLast(), 512.0)
        XCTAssertEqual(budget.spent, 123.5 + 47.25, accuracy: 1e-12)
        XCTAssertEqual(budget.refundLast(), 47.25)
        XCTAssertEqual(budget.refundLast(), 123.5)
        XCTAssertEqual(budget.spent, 0)
        XCTAssertNil(budget.refundLast())
        XCTAssertEqual(budget.remaining, 2000)
    }

    func testRepeatedDrawUndoCyclesDoNotLeakBudget() {
        var budget = InkBudget(total: 1000)
        let line = (0..<40).map { Vec2(60 + Double($0) * 8, 400) }
        for id in 0..<200 {
            guard case let .accepted(_, cost) = pipeline.makeShape(id: id, rawPoints: line,
                                                                 source: .freehand, budget: budget) else {
                return XCTFail("stroke rejected on cycle \(id)")
            }
            budget.charge(cost)
            budget.refundLast()
        }
        XCTAssertEqual(budget.spent, 0)
        XCTAssertEqual(budget.remaining, 1000)
    }

    // MARK: - The other side of the calibration

    func testALegitimateRampFitsTheTightestBudget() {
        // The budget has to exclude the blob WITHOUT excluding a real answer. A single
        // sensible ramp must fit the tightest band with room to spare, or the constraint has
        // stopped creating thinking and started preventing it.
        let ramp = [Vec2(70, 620), Vec2(400, 560)]
        guard let processed = StrokeSimplifier().process(rawPoints: ramp) else {
            return XCTFail("ramp rejected")
        }
        let cost = meter.cost(of: processed)
        XCTAssertLessThan(cost, 550, "an ordinary ramp costs \(cost), which is too much")
    }

    func testASmallDeliberateBlockRemainsAffordable() {
        // Closed shapes must stay usable — the area charge is aimed at the scene-sized blob,
        // not at a child who wants a solid block to sit under the ball.
        let block = [Vec2(300, 300), Vec2(360, 300), Vec2(360, 360), Vec2(300, 360), Vec2(302, 302)]
        guard let processed = StrokeSimplifier().process(rawPoints: block) else {
            return XCTFail("block rejected")
        }
        XCTAssertTrue(processed.isClosed)
        XCTAssertLessThan(meter.cost(of: processed), 700)
    }

    func testMinimumStrokeLengthRejectsAccidentalTaps() {
        let budget = InkBudget(total: 1000)
        let tap = [Vec2(200, 200), Vec2(204, 203), Vec2(206, 201)]
        guard case let .rejected(reason) = pipeline.makeShape(id: 0, rawPoints: tap,
                                                             source: .freehand, budget: budget) else {
            return XCTFail("a tap must not create a body")
        }
        XCTAssertEqual(reason, .tooShort)
    }

    func testOverBudgetStrokeIsRejectedWithItsCost() {
        // The rejection carries the numbers so the HUD can say "that one is too big" instead
        // of silently doing nothing, which reads as the app being broken.
        let budget = InkBudget(total: 120)
        let long = (0..<80).map { Vec2(60 + Double($0) * 8, 400) }
        guard case let .rejected(.overBudget(cost, remaining)) =
                pipeline.makeShape(id: 0, rawPoints: long, source: .freehand, budget: budget) else {
            return XCTFail("expected an over-budget rejection")
        }
        XCTAssertGreaterThan(cost, remaining)
        XCTAssertEqual(remaining, 120)
    }

    func testClosedShapeIsChargedForAreaAsWellAsPerimeter() {
        let square = [Vec2(0, 0), Vec2(200, 0), Vec2(200, 200), Vec2(0, 200)]
        let perimeterOnly = Polygon.perimeter(square)
        let charged = meter.cost(perimeterOrLength: perimeterOnly,
                                 enclosedArea: Polygon.area(square),
                                 isClosed: true)
        XCTAssertEqual(charged, perimeterOnly + 200 * 200 * meter.areaCharge, accuracy: 1e-9)
        XCTAssertGreaterThan(charged, perimeterOnly * 3)
    }
}
