import SwiftUI
import SpriteKit

struct PlayView: View {
    @State var session: GameSession
    @State private var scene: PlayScene?
    @State private var showingShapeLibrary = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Title, Budget
            HStack {
                Text(session.level.title)
                    .font(.headline)
                Spacer()
                InkMeterView(remaining: session.budget.remaining, total: session.level.inkBudget)
                    .frame(width: 150)
            }
            .padding()
            
            // The PlayScene via SpriteView
            if let scene = scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .background(Color(white: 0.95))
            } else {
                Color(white: 0.95)
            }
            
            // Footer Controls
            HStack(spacing: 40) {
                Button(action: { session.undo() }) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                .disabled(session.committedShapes.isEmpty || session.phase != .drawing)
                
                Button(action: { showingShapeLibrary = true }) {
                    Image(systemName: "square.on.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                .disabled(session.phase != .drawing)
                .popover(isPresented: $showingShapeLibrary) {
                    VStack {
                        Text("Shape Library").font(.headline).padding()
                        ScrollView {
                            VStack(alignment: .leading) {
                                ForEach(ShapeLibrary.shapes) { shape in
                                    Button(action: {
                                        // Default location in centre of screen
                                        let pts = shape.points(at: Vec2(400, 300), scale: 1.0)
                                        session.placeLibraryShape(points: pts, id: shape.id)
                                        showingShapeLibrary = false
                                    }) {
                                        HStack {
                                            Image(systemName: shape.symbolName)
                                                .frame(width: 30)
                                            Text(shape.spokenName)
                                        }
                                        .padding()
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 200, height: 300)
                    .padding()
                }
                
                Button(action: {
                    if session.phase == .running {
                        session.resetKeepingStrokes()
                    } else {
                        session.play()
                    }
                }) {
                    Image(systemName: session.phase == .running ? "stop.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(session.phase == .running ? .red : .green)
                }
                
                Button(action: { session.resetClearingStrokes() }) {
                    Image(systemName: "trash.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                .disabled(session.phase != .drawing)
            }
            .padding()
        }
        .onAppear {
            if scene == nil {
                scene = PlayScene(session: session)
            }
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .solved {
                // We'd show a success overlay or transition here
                print("Level solved!")
            }
        }
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
    PlayView(session: GameSession(level: level))
}
