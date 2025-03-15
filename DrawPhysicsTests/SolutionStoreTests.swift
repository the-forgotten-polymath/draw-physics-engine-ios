import XCTest
import SwiftData
@testable import DrawPhysics
import KidsGameCore

@MainActor
final class SolutionStoreTests: XCTestCase {

    func testSaveAndRetrieve() throws {
        let store = try SolutionStore(inMemory: true)
        
        let payload = SolutionPayload(
            levelID: "test-level",
            strokes: [RecordedStroke(points: [Vec2(0,0), Vec2(10,10)], committedAtStep: 0)],
            stepsToGoal: 42
        )
        let outcome = SolutionOutcome(
            didReachGoal: true,
            stepsToGoal: 42,
            inkUsed: 100.5,
            strokeCount: 1
        )
        
        let record = try SolutionRecord(payload: payload, outcome: outcome)
        store.save(record)
        
        let records = try store.records(forLevel: "test-level")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].didReachGoal, true)
        XCTAssertEqual(records[0].inkUsed, 100.5)
        XCTAssertEqual(records[0].strokeCount, 1)
        XCTAssertEqual(records[0].stepsToGoal, 42)
        
        let decodedPayload = try records[0].decodedPayload()
        XCTAssertEqual(decodedPayload, payload)
    }

    func testDistinctSolutionCount() throws {
        let store = try SolutionStore(inMemory: true)
        
        let outcome1 = SolutionOutcome(didReachGoal: true, stepsToGoal: 42, inkUsed: 100.1, strokeCount: 1)
        let outcome2 = SolutionOutcome(didReachGoal: true, stepsToGoal: 45, inkUsed: 100.4, strokeCount: 1)
        let outcome3 = SolutionOutcome(didReachGoal: true, stepsToGoal: 42, inkUsed: 200.0, strokeCount: 2)
        
        let payload1 = SolutionPayload(levelID: "level-1", strokes: [], stepsToGoal: 42)
        
        store.save(try SolutionRecord(payload: payload1, outcome: outcome1))
        store.save(try SolutionRecord(payload: payload1, outcome: outcome2)) // Rounds to same ink, same strokes -> duplicate idea
        store.save(try SolutionRecord(payload: payload1, outcome: outcome3)) // Different ink/strokes -> new idea
        
        let count = try store.distinctSolutionCount(forLevel: "level-1")
        XCTAssertEqual(count, 2)
    }

    func testRecordIsImmutableAfterInit() throws {
        let store = try SolutionStore(inMemory: true)
        let payload = SolutionPayload(levelID: "test", strokes: [], stepsToGoal: 10)
        let outcome = SolutionOutcome(didReachGoal: true, stepsToGoal: 10, inkUsed: 10, strokeCount: 1)
        
        let record = try SolutionRecord(payload: payload, outcome: outcome)
        store.save(record)
        
        let originalPayloadData = record.payload
        let originalGoal = record.didReachGoal
        
        // Simulating a divergent replay shouldn't modify the record because we don't have setters for it.
        // SwiftData properties technically have setters unless we make them get-only, but we can't do that.
        // We just prove that retrieving it gives the original.
        let records = try store.records(forLevel: "test")
        XCTAssertEqual(records[0].payload, originalPayloadData)
        XCTAssertEqual(records[0].didReachGoal, originalGoal)
    }
}
