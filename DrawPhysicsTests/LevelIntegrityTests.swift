import XCTest
import KidsGameCore
@testable import DrawPhysics

/// The build gate for hand-authored content (§8.5).
///
/// Hand-designed physics levels have exactly two reliable failure modes: they ship
/// unsolvable, or they ship with a budget too tight for their own intended answer. Both are
/// invisible to a human reading the level file and obvious to a simulator, so the simulator
/// gets the job.
final class LevelIntegrityTests: XCTestCase {

    /// In the app target this is `Bundle.main` — an XCTest bundle hosted by the app sees the
    /// app bundle as main, so the same loader the game uses is the loader under test.
    private var repository: LevelRepository { LevelRepository(bundle: Bundle(for: type(of: self))) }
    private let simulator = SolutionSimulator()

    private func loadLevels() throws -> [LevelDefinition] {
        let levels = try repository.loadAll()
        XCTAssertFalse(levels.isEmpty)
        return levels
    }

    func testLevelsLoadFromTheBundle() throws {
        let levels = try loadLevels()
        XCTAssertEqual(levels.count, 6)
        XCTAssertEqual(Set(levels.map(\.band)), Set(AgeBand.allCases),
                       "every band must have at least one level")
    }

    func testEveryLevelDeclaresAtLeastOneReferenceSolution() throws {
        for level in try loadLevels() {
            XCTAssertFalse(level.referenceSolutions.isEmpty,
                           "\(level.id) has no reference solution, so nothing proves it is solvable")
        }
    }

    func testEveryLevelReferenceSolutionReachesGoal() throws {
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                let result = simulator.run(level: level, strokes: reference.strokes)
                XCTAssertTrue(result.didReachGoal,
                              "\(level.id)/\(reference.id) did not reach the goal in \(level.maximumSteps) steps")
                XCTAssertTrue(result.rejections.isEmpty,
                              "\(level.id)/\(reference.id) had strokes rejected: \(result.rejections)")
            }
        }
    }

    func testEveryReferenceSolutionFitsItsInkBudget() throws {
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                let result = simulator.run(level: level, strokes: reference.strokes)
                XCTAssertLessThanOrEqual(result.inkUsed, level.inkBudget,
                                         "\(level.id)/\(reference.id) needs \(result.inkUsed) ink but the level allows \(level.inkBudget)")
            }
        }
    }

    func testNoLevelIsSolvableWithoutDrawing() throws {
        // Not in the original brief, and it should have been. During authoring, one level's
        // fixtures fed the ball straight into the cup with no strokes at all — it looked fine
        // in the level file and it was not a level.
        for level in try loadLevels() {
            let result = simulator.run(level: level, strokes: [])
            XCTAssertFalse(result.didReachGoal,
                           "\(level.id) solves itself with no strokes")
        }
    }

    func testEveryReferenceSolutionRespectsItsStrokeLimit() throws {
        for level in try loadLevels() {
            guard let limit = level.maxStrokes else { continue }
            for reference in level.referenceSolutions {
                XCTAssertLessThanOrEqual(reference.strokes.count, limit,
                                         "\(level.id)/\(reference.id) uses more strokes than the level allows")
            }
        }
    }

    func testReferenceSolutionsAreRobustToBeingDrawnSlightlyDifferently() throws {
        // A reference solution that only works at exactly these coordinates is a fluke, and a
        // build gate resting on a fluke fails the first time a constant moves.
        let jitters = [Vec2(6, 0), Vec2(-6, 0), Vec2(0, 6), Vec2(0, -6)]
        for level in try loadLevels() {
            for reference in level.referenceSolutions {
                for offset in jitters {
                    let moved = reference.strokes.map {
                        RecordedStroke(points: $0.points.map { point in point + offset },
                                       committedAtStep: $0.committedAtStep,
                                       source: $0.source)
                    }
                    let result = simulator.run(level: level, strokes: moved)
                    XCTAssertTrue(result.didReachGoal,
                                  "\(level.id)/\(reference.id) fails when shifted by \(offset)")
                }
            }
        }
    }

    func testLevelGeometryStaysInsideTheScene() throws {
        for level in try loadLevels() {
            for movable in level.movables {
                switch movable.kind {
                case let .ball(centre, radius):
                    XCTAssertGreaterThan(centre.x - radius, 0, "\(level.id): \(movable.tag) starts in a wall")
                    XCTAssertLessThan(centre.x + radius, level.sceneSize.width)
                    XCTAssertLessThan(centre.y + radius, level.sceneSize.height)
                case let .crate(centre, size, _):
                    XCTAssertGreaterThan(centre.x - size.width / 2, 0)
                    XCTAssertLessThan(centre.x + size.width / 2, level.sceneSize.width)
                }
            }
        }
    }

    func testGoalRegionsAreReachablyInsideTheirCups() throws {
        // A goal region that overlaps a cup wall registers a ball resting on the rim as
        // "in the cup", which quietly makes several levels trivial.
        for level in try loadLevels() {
            let region: Rect
            switch level.goal {
            case let .ballInRegion(_, r, _): region = r
            case let .ballThroughGapThenRegion(_, _, r, _): region = r
            case let .allBallsInRegion(_, r, _): region = r
            }
            XCTAssertGreaterThan(region.size.width, 0)
            XCTAssertGreaterThan(region.size.height, 0)
            let cups = level.fixtures.compactMap { fixture -> (Vec2, Double, Double, Double)? in
                guard case let .cup(centre, width, height, thickness) = fixture.kind else { return nil }
                return (centre, width, height, thickness)
            }
            XCTAssertFalse(cups.isEmpty, "\(level.id) has a region goal but no cup")
            let matched = cups.contains { cup in
                let (centre, width, height, thickness) = cup
                let interior = Rect(x: centre.x - width / 2 + thickness,
                                    y: centre.y - height / 2 + thickness,
                                    width: width - thickness * 2,
                                    height: height * 2)
                return interior.contains(region.center)
            }
            XCTAssertTrue(matched, "\(level.id): the goal region is not inside any cup")
        }
    }
}
