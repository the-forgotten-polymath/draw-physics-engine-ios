import Foundation
import Observation

enum Phase { case drawing, running, solved }

@MainActor @Observable final class GameSession {
    private(set) var phase: Phase
    private(set) var world: FixedStepWorld
    private(set) var budget: InkBudget
    private(set) var committedShapes: [DrawnShape]          // for the renderer and undo
    private(set) var recordedStrokes: [RecordedStroke]
    private(set) var liveStroke: [Vec2]                     // in-progress, scene space
    private(set) var rejection: StrokePipeline.Rejection?   // transient, for the HUD
    private(set) var outcome: SolutionOutcome?
    let level: LevelDefinition
    
    private let pipeline = StrokePipeline()
    private var judge: OutcomeJudge
    private var bodyIDsForStrokes: [Int] = []
    private var strokeCounter = 0
    private var store: SolutionStore?
    
    init(level: LevelDefinition, store: SolutionStore? = nil) {
        self.level = level
        self.store = store
        let built = SceneBuilder.build(level: level)
        self.world = built.world
        self.budget = InkBudget(total: level.inkBudget)
        self.phase = .drawing
        self.committedShapes = []
        self.recordedStrokes = []
        self.liveStroke = []
        self.judge = OutcomeJudge(goal: level.goal)
    }

    func beginStroke(at point: Vec2) {
        if phase == .solved { return }
        if phase == .running && !level.drawWhileRunning { return }
        rejection = nil
        liveStroke = [point]
        HapticEngine.shared.startDrawing()
    }
    
    func extendStroke(to point: Vec2) {
        if liveStroke.isEmpty { return } // Ignored if beginStroke was rejected
        
        let lastPoint = liveStroke.last!
        let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        let speed = distance * 60.0 // rough approximation
        
        liveStroke.append(point)
        
        // Play draw sound based on speed
        if speed > 10.0 {
            SoundBank.shared.playDraw(speed: speed)
        }
    }
    
    func endStroke() {
        HapticEngine.shared.stopDrawing()
        guard !liveStroke.isEmpty else { return }
        let points = liveStroke
        liveStroke = [] // clear live early
        
        let result = pipeline.makeShape(id: strokeCounter, rawPoints: points, source: .freehand, budget: budget)
        switch result {
        case .accepted(let shape, let cost):
            budget.charge(cost)
            committedShapes.append(shape)
            recordedStrokes.append(RecordedStroke(points: points, committedAtStep: world.stepIndex, source: .freehand))
            let body = SceneBuilder.addDrawnShape(shape, to: world)
            if let id = body?.id {
                bodyIDsForStrokes.append(id)
            } else {
                bodyIDsForStrokes.append(-1)
            }
            strokeCounter += 1
        case .rejected(let r):
            rejection = r
        }
    }
    
    func placeLibraryShape(points: [Vec2], id: String) {
        if phase == .solved { return }
        if phase == .running && !level.drawWhileRunning { return }
        rejection = nil
        
        let result = pipeline.makeShape(id: strokeCounter, rawPoints: points, source: .library(id), budget: budget)
        switch result {
        case .accepted(let shape, let cost):
            budget.charge(cost)
            committedShapes.append(shape)
            recordedStrokes.append(RecordedStroke(points: points, committedAtStep: world.stepIndex, source: .library(id)))
            let body = SceneBuilder.addDrawnShape(shape, to: world)
            if let bodyID = body?.id {
                bodyIDsForStrokes.append(bodyID)
            } else {
                bodyIDsForStrokes.append(-1)
            }
            strokeCounter += 1
        case .rejected(let r):
            rejection = r
        }
    }
    
    func undo() {
        guard !committedShapes.isEmpty else { return }
        
        committedShapes.removeLast()
        recordedStrokes.removeLast()
        _ = budget.refundLast()
        let bodyID = bodyIDsForStrokes.removeLast()
        if bodyID != -1 {
            world.removeBody(id: bodyID)
        }
    }
    
    func play() {
        if phase == .solved { return }
        phase = .running
        world.discardAccumulatedTime()
    }
    
    func advance(by frameDelta: Double) {
        guard phase == .running else { return }
        
        _ = world.advance(by: frameDelta) { [weak self] stepIndex in
            guard let self = self else { return }
            self.judge.evaluate(world: self.world, stepIndex: stepIndex)
        }
        
        if !world.latestImpulses.isEmpty {
            for impulse in world.latestImpulses {
                SoundBank.shared.playContact(impulse: impulse)
                HapticEngine.shared.playContact(impulse: impulse)
            }
            world.latestImpulses.removeAll(keepingCapacity: true)
        }
        
        let hasFailed = world.stepIndex >= level.maximumSteps
        
        if judge.didReachGoal || hasFailed {
            if judge.didReachGoal {
                phase = .solved
                SoundBank.shared.playGoal()
                HapticEngine.shared.playGoal()
                let newOutcome = SolutionOutcome(
                    didReachGoal: true,
                    stepsToGoal: judge.stepReached,
                    inkUsed: level.inkBudget - budget.remaining,
                    strokeCount: strokeCounter,
                    judgedAt: Date()
                )
                self.outcome = newOutcome
                
                let payload = SolutionPayload(levelID: level.id, strokes: recordedStrokes, stepsToGoal: judge.stepReached ?? world.stepIndex)
                if let store = store, let record = try? SolutionRecord(payload: payload, outcome: newOutcome) {
                    store.save(record)
                }
            } else {
                // Timeout or failure, stop running but keep strokes
                phase = .drawing
            }
        }
    }
    
    func resetKeepingStrokes() {
        let built = SceneBuilder.build(level: level)
        self.world = built.world
        self.phase = .drawing
        self.judge = OutcomeJudge(goal: level.goal)
        self.bodyIDsForStrokes.removeAll()
        
        for shape in committedShapes {
            let body = SceneBuilder.addDrawnShape(shape, to: world)
            if let id = body?.id {
                bodyIDsForStrokes.append(id)
            } else {
                bodyIDsForStrokes.append(-1)
            }
        }
    }
    
    func resetClearingStrokes() {
        let built = SceneBuilder.build(level: level)
        self.world = built.world
        self.budget = InkBudget(total: level.inkBudget)
        self.phase = .drawing
        self.committedShapes.removeAll()
        self.recordedStrokes.removeAll()
        self.liveStroke.removeAll()
        self.rejection = nil
        self.outcome = nil
        self.judge = OutcomeJudge(goal: level.goal)
        self.bodyIDsForStrokes.removeAll()
        self.strokeCounter = 0
    }
}
