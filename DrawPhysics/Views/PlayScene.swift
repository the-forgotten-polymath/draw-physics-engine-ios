import SpriteKit
import SwiftUI

@MainActor
final class PlayScene: SKScene {
    private let session: GameSession
    
    // Node tracking mapping tags to nodes
    private var bodyNodes: [BodyTag: SKNode] = [:]
    
    // In-progress stroke
    private var currentStrokeNode: SKShapeNode?
    
    init(session: GameSession) {
        self.session = session
        super.init(size: CGSize(width: session.level.sceneSize.width, height: session.level.sceneSize.height))
        self.scaleMode = .aspectFit
        self.backgroundColor = SKColor(white: 0.95, alpha: 1.0)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        setupStaticWorld()
    }
    
    private func setupStaticWorld() {
        // Draw fixtures
        for fixture in session.level.fixtures {
            let node = SKShapeNode()
            let path = CGMutablePath()
            switch fixture.kind {
            case .box(let center, let size, let rotation):
                node.position = CGPoint(x: center.x, y: center.y)
                node.zRotation = rotation
                path.addRect(CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
            case .polygon(let points):
                if let first = points.first {
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for pt in points.dropFirst() {
                        path.addLine(to: CGPoint(x: pt.x, y: pt.y))
                    }
                    path.closeSubpath()
                }
            case .cup(let center, let width, let height, let wallThickness):
                node.position = CGPoint(x: center.x, y: center.y)
                path.addRect(CGRect(x: -width/2, y: -height/2, width: width, height: wallThickness)) // floor
                path.addRect(CGRect(x: -width/2, y: -height/2, width: wallThickness, height: height)) // left wall
                path.addRect(CGRect(x: width/2 - wallThickness, y: -height/2, width: wallThickness, height: height)) // right wall
            case .movingPlatform(let center, let size, _, _):
                node.position = CGPoint(x: center.x, y: center.y)
                path.addRect(CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
            case .seesaw(let pivot, let length, let thickness, _):
                node.position = CGPoint(x: pivot.x, y: pivot.y)
                path.addRect(CGRect(x: -length/2, y: -thickness/2, width: length, height: thickness))
            }
            node.path = path
            node.fillColor = SKColor(white: 0.2, alpha: 1.0)
            node.strokeColor = .clear
            addChild(node)
        }
        
        // Draw goal region (very faint for debugging/visualization)
        switch session.level.goal {
        case .ballInRegion(_, let region, _):
            let goalNode = SKShapeNode(rect: CGRect(x: region.minX, y: region.minY, width: region.size.width, height: region.size.height))
            goalNode.fillColor = SKColor.green.withAlphaComponent(0.1)
            goalNode.strokeColor = SKColor.green.withAlphaComponent(0.3)
            goalNode.lineWidth = 2
            addChild(goalNode)
        case .ballThroughGapThenRegion(_, let gap, let region, _):
            let gapNode = SKShapeNode(rect: CGRect(x: gap.minX, y: gap.minY, width: gap.size.width, height: gap.size.height))
            gapNode.fillColor = SKColor.blue.withAlphaComponent(0.1)
            gapNode.strokeColor = SKColor.blue.withAlphaComponent(0.3)
            gapNode.lineWidth = 2
            addChild(gapNode)
            
            let goalNode = SKShapeNode(rect: CGRect(x: region.minX, y: region.minY, width: region.size.width, height: region.size.height))
            goalNode.fillColor = SKColor.green.withAlphaComponent(0.1)
            goalNode.strokeColor = SKColor.green.withAlphaComponent(0.3)
            goalNode.lineWidth = 2
            addChild(goalNode)
        case .allBallsInRegion(_, let region, _):
            let goalNode = SKShapeNode(rect: CGRect(x: region.minX, y: region.minY, width: region.size.width, height: region.size.height))
            goalNode.fillColor = SKColor.green.withAlphaComponent(0.1)
            goalNode.strokeColor = SKColor.green.withAlphaComponent(0.3)
            goalNode.lineWidth = 2
            addChild(goalNode)
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Advance simulation if playing
        if session.phase == .running {
            // Ideally we'd use delta time, but FixedStepWorld expects fixed steps.
            // We advance by fixed 1/60s per frame.
            session.advance(by: 1.0 / 60.0)
        }
        
        // Sync dynamic bodies
        for body in session.world.bodies {
            if body.motion == .static { continue } // Only movables and committed shapes move
            
            let node: SKNode
            if let existing = bodyNodes[body.tag] {
                node = existing
            } else {
                node = createNode(for: body)
                bodyNodes[body.tag] = node
                addChild(node)
            }
            
            node.position = CGPoint(x: body.position.x, y: body.position.y)
            node.zRotation = CGFloat(body.rotation)
        }
        
        // Remove nodes for bodies that were deleted (e.g. undo)
        let activeTags = Set(session.world.bodies.map { $0.tag })
        for (tag, node) in bodyNodes {
            if !activeTags.contains(tag) {
                node.removeFromParent()
                bodyNodes.removeValue(forKey: tag)
            }
        }
        
        // Update in-progress stroke if drawn
        if session.liveStroke.count > 1 {
            if currentStrokeNode == nil {
                currentStrokeNode = SKShapeNode()
                currentStrokeNode?.strokeColor = .blue
                currentStrokeNode?.lineWidth = 6
                currentStrokeNode?.lineCap = .round
                currentStrokeNode?.lineJoin = .round
                addChild(currentStrokeNode!)
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: session.liveStroke[0].x, y: session.liveStroke[0].y))
            for pt in session.liveStroke.dropFirst() {
                path.addLine(to: CGPoint(x: pt.x, y: pt.y))
            }
            currentStrokeNode?.path = path
        } else {
            currentStrokeNode?.removeFromParent()
            currentStrokeNode = nil
        }
    }
    
    private func createNode(for body: RigidBody) -> SKNode {
        // Find if this tag matches a movable to get its shape
        if let movable = session.level.movables.first(where: { $0.tag == body.tag.raw }) {
            switch movable.kind {
            case .ball(_, let radius):
                let node = SKShapeNode(circleOfRadius: CGFloat(radius))
                node.fillColor = .red
                node.strokeColor = .white
                node.lineWidth = 2
                
                // Add a line to show rotation
                let line = SKShapeNode(path: {
                    let p = CGMutablePath()
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: radius, y: 0))
                    return p
                }())
                line.strokeColor = .white
                line.lineWidth = 2
                node.addChild(line)
                return node
            case .crate(_, let size, _):
                let node = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
                node.fillColor = .red
                node.strokeColor = .white
                node.lineWidth = 2
                return node
            }
        }
        
        // Find if this tag is a shape
        if let shape = session.committedShapes.first(where: { "shape-\($0.id)" == body.tag.raw }) {
            let node = SKShapeNode()
            let path = CGMutablePath()
            
            // To render a dynamic shape, we need its original points relative to its local center.
            // Wait, the 'points' in DrawnShape are in world space!
            // But the physics body is created with those points and its center of mass is computed.
            // If the body's position is its center of mass, we must offset the path so that
            // when the node is at body.position, it aligns correctly.
            // Actually, in `FixedStepWorld`, we just pass `points` to create the body. Box2D computes the centroid.
            // Let's just create the path centered at (0,0) by subtracting body.position from the shape's original points.
            if let first = shape.simplifiedPoints.first {
                path.move(to: CGPoint(x: first.x - body.position.x, y: first.y - body.position.y))
                for pt in shape.simplifiedPoints.dropFirst() {
                    path.addLine(to: CGPoint(x: pt.x - body.position.x, y: pt.y - body.position.y))
                }
                path.closeSubpath()
            }
            node.path = path
            node.fillColor = SKColor.blue.withAlphaComponent(0.8)
            node.strokeColor = .white
            node.lineWidth = 2
            return node
        }
        
        // Fallback
        let node = SKShapeNode(circleOfRadius: 10)
        node.fillColor = .gray
        return node
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pos = touch.location(in: self)
        session.beginStroke(at: Vec2(Double(pos.x), Double(pos.y)))
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pos = touch.location(in: self)
        session.extendStroke(to: Vec2(Double(pos.x), Double(pos.y)))
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        session.endStroke()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        session.endStroke()
    }
}
