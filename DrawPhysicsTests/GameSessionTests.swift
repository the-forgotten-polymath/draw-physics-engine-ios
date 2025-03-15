import XCTest
@testable import DrawPhysics

@MainActor
final class GameSessionTests: XCTestCase {
    
    private func createTestLevel() -> LevelDefinition {
        return LevelDefinition(
            id: "test",
            title: "Test Level",
            band: .early,
            inkBudget: 1000,
            drawWhileRunning: true,
            spokenHint: "Test",
            fixtures: [],
            movables: [],
            goal: .ballInRegion(ballTag: "ball", region: Rect(x: 0, y: 0, width: 10, height: 10), dwellSteps: 10),
            referenceSolutions: [],
            maximumSteps: 1000
        )
    }

    func testUndoDraw3Undo3() {
        let level = createTestLevel()
        
        let session = GameSession(level: level)
        let initialBodiesCount = session.world.bodies.count
        
        // Draw 3 valid strokes
        session.beginStroke(at: Vec2(0, 0))
        session.extendStroke(to: Vec2(100, 100))
        session.endStroke()
        
        session.beginStroke(at: Vec2(100, 100))
        session.extendStroke(to: Vec2(200, 200))
        session.endStroke()
        
        session.beginStroke(at: Vec2(200, 200))
        session.extendStroke(to: Vec2(300, 300))
        session.endStroke()
        
        XCTAssertEqual(session.committedShapes.count, 3)
        XCTAssertLessThan(session.budget.remaining, 1000)
        XCTAssertGreaterThan(session.world.bodies.count, initialBodiesCount)
        
        // Undo 3 times
        session.undo()
        session.undo()
        session.undo()
        
        XCTAssertEqual(session.committedShapes.count, 0)
        XCTAssertEqual(session.budget.remaining, 1000)
        XCTAssertEqual(session.world.bodies.count, initialBodiesCount)
    }
    
    func testResetKeepingStrokesMaintainsShapesInOrder() {
        let level = createTestLevel()
        
        let session = GameSession(level: level)
        session.beginStroke(at: Vec2(0, 0))
        session.extendStroke(to: Vec2(100, 100))
        session.endStroke()
        
        let shapeID = session.committedShapes.first?.id
        
        session.resetKeepingStrokes()
        
        XCTAssertEqual(session.committedShapes.count, 1)
        XCTAssertEqual(session.committedShapes.first?.id, shapeID)
    }
}
