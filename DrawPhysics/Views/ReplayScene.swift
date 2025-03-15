import SpriteKit

@MainActor
final class ReplayScene: SKScene {
    private let level: LevelDefinition
    private let shapes: [DrawnShape]
    
    private var bodyNodes: [String: SKNode] = [:]
    
    init(level: LevelDefinition, shapes: [DrawnShape]) {
        self.level = level
        self.shapes = shapes
        super.init(size: CGSize(width: level.sceneSize.width, height: level.sceneSize.height))
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
        for fixture in level.fixtures {
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
        
        switch level.goal {
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
    
    func render(frame: SolutionSimulator.Frame) {
        let shapesByTag = Dictionary(uniqueKeysWithValues: shapes.map { ("shape-\($0.id)", $0) })
        let movablesByTag = Dictionary(uniqueKeysWithValues: level.movables.map { ($0.tag, $0) })
        
        for snapshot in frame.bodies {
            let node: SKNode
            if let existing = bodyNodes[snapshot.tag] {
                node = existing
            } else {
                node = createNode(for: snapshot, movables: movablesByTag, shapes: shapesByTag)
                bodyNodes[snapshot.tag] = node
                addChild(node)
            }
            
            node.position = CGPoint(x: snapshot.position.x, y: snapshot.position.y)
            node.zRotation = CGFloat(snapshot.rotation)
        }
        
        // Remove old bodies not in this frame
        let activeTags = Set(frame.bodies.map { $0.tag })
        for (tag, node) in bodyNodes {
            if !activeTags.contains(tag) {
                node.removeFromParent()
                bodyNodes.removeValue(forKey: tag)
            }
        }
    }
    
    private func createNode(for snapshot: SolutionSimulator.BodySnapshot,
                            movables: [String: MovableDefinition],
                            shapes: [String: DrawnShape]) -> SKNode {
        if let movable = movables[snapshot.tag] {
            switch movable.kind {
            case .ball(_, let radius):
                let node = SKShapeNode(circleOfRadius: CGFloat(radius))
                node.fillColor = .systemRed
                node.strokeColor = .white
                node.lineWidth = 2
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
                node.fillColor = .systemRed
                node.strokeColor = .white
                node.lineWidth = 2
                return node
            }
        }
        
        if let shape = shapes[snapshot.tag] {
            let node = SKShapeNode()
            let path = CGMutablePath()
            if let first = shape.simplifiedPoints.first {
                path.move(to: CGPoint(x: first.x - snapshot.position.x, y: first.y - snapshot.position.y))
                for pt in shape.simplifiedPoints.dropFirst() {
                    path.addLine(to: CGPoint(x: pt.x - snapshot.position.x, y: pt.y - snapshot.position.y))
                }
                path.closeSubpath()
            }
            node.path = path
            node.fillColor = SKColor.systemBlue.withAlphaComponent(0.8)
            node.strokeColor = .white
            node.lineWidth = 2
            return node
        }
        
        let node = SKShapeNode(circleOfRadius: 10)
        node.fillColor = .gray
        return node
    }
}
