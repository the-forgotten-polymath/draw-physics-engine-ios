import CoreGraphics
import Foundation

struct SceneRenderer {
    let sceneSize: Size
    let pixelSize: CGSize
    
    func draw(bodies: [SolutionSimulator.BodySnapshot], shapes: [DrawnShape],
              level: LevelDefinition, into context: CGContext) {
        
        context.saveGState()
        
        // Background
        context.setFillColor(gray: 0.95, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: pixelSize))
        
        // Match SpriteKit coordinate system (y=0 at bottom)
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Calculate scaling from sceneSize to pixelSize
        let scaleX = pixelSize.width / sceneSize.width
        let scaleY = pixelSize.height / sceneSize.height
        let scale = min(scaleX, scaleY)
        
        let offsetX = (pixelSize.width - sceneSize.width * scale) / 2
        let offsetY = (pixelSize.height - sceneSize.height * scale) / 2
        
        // Apply transform
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)
        
        // Goal Region
        if case .ballInRegion(_, let region, _) = level.goal {
            context.setFillColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.1)
            context.setStrokeColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.3)
            context.setLineWidth(2 / scale)
            let rect = CGRect(x: region.minX, y: region.minY, width: region.size.width, height: region.size.height)
            context.addRect(rect)
            context.drawPath(using: .fillStroke)
        }
        
        // Fixtures
        context.setFillColor(gray: 0.2, alpha: 1.0)
        for fixture in level.fixtures {
            switch fixture.kind {
            case .box(let center, let size, let rotation):
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: rotation)
                context.addRect(CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
                context.fillPath()
                context.restoreGState()
            case .polygon(let points):
                if let first = points.first {
                    context.move(to: CGPoint(x: first.x, y: first.y))
                    for pt in points.dropFirst() {
                        context.addLine(to: CGPoint(x: pt.x, y: pt.y))
                    }
                    context.closePath()
                    context.fillPath()
                }
            case .cup(let center, let width, let height, let wallThickness):
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.addRect(CGRect(x: -width/2, y: -height/2, width: width, height: wallThickness)) // floor
                context.addRect(CGRect(x: -width/2, y: -height/2, width: wallThickness, height: height)) // left wall
                context.addRect(CGRect(x: width/2 - wallThickness, y: -height/2, width: wallThickness, height: height)) // right wall
                context.fillPath()
                context.restoreGState()
            case .movingPlatform(let center, let size, _, _):
                context.addRect(CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height))
                context.fillPath()
            case .seesaw(let pivot, let length, let thickness, _):
                context.saveGState()
                context.translateBy(x: pivot.x, y: pivot.y)
                context.addRect(CGRect(x: -length/2, y: -thickness/2, width: length, height: thickness))
                context.fillPath()
                context.restoreGState()
            }
        }
        
        // Dynamic bodies
        // Build map of shapes
        let shapesByTag = Dictionary(uniqueKeysWithValues: shapes.map { ("shape-\($0.id)", $0) })
        let movablesByTag = Dictionary(uniqueKeysWithValues: level.movables.map { ($0.tag, $0) })
        
        for body in bodies {
            context.saveGState()
            context.translateBy(x: body.position.x, y: body.position.y)
            context.rotate(by: body.rotation)
            
            if let movable = movablesByTag[body.tag] {
                switch movable.kind {
                case .ball(_, let radius):
                    context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                    context.setStrokeColor(gray: 1.0, alpha: 1.0)
                    context.setLineWidth(2 / scale)
                    let rect = CGRect(x: -radius, y: -radius,
                                      width: radius * 2, height: radius * 2)
                    context.addEllipse(in: rect)
                    context.drawPath(using: .fillStroke)
                    
                    context.move(to: .zero)
                    context.addLine(to: CGPoint(x: radius, y: 0))
                    context.strokePath()
                case .crate(_, let size, _):
                    context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                    context.setStrokeColor(gray: 1.0, alpha: 1.0)
                    context.setLineWidth(2 / scale)
                    let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
                    context.addRect(rect)
                    context.drawPath(using: .fillStroke)
                }
            } else if let shape = shapesByTag[body.tag] {
                // Reconstruct the shape path relative to its body.position
                context.setFillColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.8)
                context.setStrokeColor(gray: 1.0, alpha: 1.0)
                context.setLineWidth(2 / scale)
                
                if let first = shape.simplifiedPoints.first {
                    context.move(to: CGPoint(x: first.x - body.position.x, y: first.y - body.position.y))
                    for pt in shape.simplifiedPoints.dropFirst() {
                        context.addLine(to: CGPoint(x: pt.x - body.position.x, y: pt.y - body.position.y))
                    }
                    context.closePath()
                    context.drawPath(using: .fillStroke)
                }
            } else {
                // fallback
                context.setFillColor(gray: 0.5, alpha: 1.0)
                let r: CGFloat = 10
                context.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                context.fillPath()
            }
            
            context.restoreGState()
        }
        
        context.restoreGState()
    }
}
