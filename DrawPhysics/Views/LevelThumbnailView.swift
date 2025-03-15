import SwiftUI

struct LevelThumbnailView: View {
    let level: LevelDefinition
    
    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / level.sceneSize.width
            let scaleY = size.height / level.sceneSize.height
            // Fit the scene
            let scale = min(scaleX, scaleY)
            
            // Center the drawing
            let offsetX = (size.width - level.sceneSize.width * scale) / 2
            let offsetY = (size.height - level.sceneSize.height * scale) / 2
            
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
            
            // Fill background
            let bgRect = CGRect(x: 0, y: 0, width: level.sceneSize.width, height: level.sceneSize.height)
            context.fill(Path(bgRect), with: .color(Color(white: 0.95)))
            
            // Draw fixtures
            for fixture in level.fixtures {
                switch fixture.kind {
                case .box(let center, let size, let rotation):
                    context.drawLayer { ctx in
                        ctx.translateBy(x: center.x, y: center.y)
                        ctx.rotate(by: .radians(rotation))
                        let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
                        ctx.fill(Path(rect), with: .color(Color(white: 0.2)))
                    }
                case .polygon(let points):
                    var path = Path()
                    if let first = points.first {
                        path.move(to: CGPoint(x: first.x, y: first.y))
                        for pt in points.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x, y: pt.y))
                        }
                        path.closeSubpath()
                    }
                    context.fill(path, with: .color(Color(white: 0.2)))
                case .cup(let center, let width, let height, let wallThickness):
                    context.drawLayer { ctx in
                        ctx.translateBy(x: center.x, y: center.y)
                        var path = Path()
                        path.addRect(CGRect(x: -width/2, y: -height/2, width: width, height: wallThickness)) // floor
                        path.addRect(CGRect(x: -width/2, y: -height/2, width: wallThickness, height: height)) // left wall
                        path.addRect(CGRect(x: width/2 - wallThickness, y: -height/2, width: wallThickness, height: height)) // right wall
                        ctx.fill(path, with: .color(Color(white: 0.2)))
                    }
                case .movingPlatform(let center, let size, _, _):
                    let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
                    context.fill(Path(rect), with: .color(Color(white: 0.2)))
                case .seesaw(let pivot, let length, let thickness, _):
                    context.drawLayer { ctx in
                        ctx.translateBy(x: pivot.x, y: pivot.y)
                        let rect = CGRect(x: -length/2, y: -thickness/2, width: length, height: thickness)
                        ctx.fill(Path(rect), with: .color(Color(white: 0.2)))
                    }
                }
            }
            
            // Draw movables
            for movable in level.movables {
                switch movable.kind {
                case .ball(let center, let radius):
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.red))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2 / scale)
                case .crate(let center, let size, let rotation):
                    context.drawLayer { ctx in
                        ctx.translateBy(x: center.x, y: center.y)
                        ctx.rotate(by: .radians(rotation))
                        let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
                        ctx.fill(Path(rect), with: .color(.red))
                        ctx.stroke(Path(rect), with: .color(.white), lineWidth: 2 / scale)
                    }
                }
            }
            
            // Draw goal region faintly
            switch level.goal {
            case .ballInRegion(_, let region, _),
                 .ballThroughGapThenRegion(_, _, let region, _),
                 .allBallsInRegion(_, let region, _):
                let rect = CGRect(x: region.minX, y: region.minY, width: region.size.width, height: region.size.height)
                context.fill(Path(rect), with: .color(Color.green.opacity(0.1)))
                context.stroke(Path(rect), with: .color(Color.green.opacity(0.3)), lineWidth: 2 / scale)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    let level = LevelDefinition(
        id: "preview",
        title: "Preview Level",
        band: .early,
        inkBudget: 500,
        drawWhileRunning: false,
        spokenHint: "Draw something!",
        fixtures: [
            FixtureDefinition(kind: .polygon(points: [Vec2(0, 100), Vec2(750, 100), Vec2(750, 0), Vec2(0, 0)]))
        ],
        movables: [
            MovableDefinition(tag: "ball", kind: .ball(center: Vec2(100, 500), radius: 20))
        ],
        goal: .ballInRegion(ballTag: "ball", region: Rect(x: 300, y: 100, width: 100, height: 100), dwellSteps: 10),
        referenceSolutions: [],
        maximumSteps: 1000
    )
    LevelThumbnailView(level: level)
        .frame(width: 200, height: 260)
        .padding()
}
