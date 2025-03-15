import SwiftUI
import SpriteKit

struct ReplayView: View {
    let level: LevelDefinition
    let record: SolutionRecord
    
    @State private var result: SolutionSimulator.Result?
    @State private var scene: ReplayScene?
    @State private var frameIndex = 0
    @State private var isPlaying = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(level.title)
                    .font(.headline)
                Spacer()
                Text("Replay")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            // Scene
            if let scene = scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .background(Color(white: 0.95))
            } else {
                VStack {
                    Spacer()
                    ProgressView("Simulating...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.95))
            }
            
            // Footer Controls
            HStack(spacing: 40) {
                Button(action: {
                    frameIndex = 0
                    isPlaying = false
                    updateSceneFrame()
                }) {
                    Image(systemName: "backward.end.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                .disabled(result == nil)
                
                Button(action: {
                    if isPlaying {
                        isPlaying = false
                    } else {
                        if frameIndex >= (result?.frames.count ?? 0) - 1 {
                            frameIndex = 0
                        }
                        isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(isPlaying ? .red : .green)
                }
                .disabled(result == nil)
                
                // Export Button stub (behind ParentGate normally)
                Button(action: {
                    // Export video
                    print("Export video tapped")
                }) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                .disabled(result == nil)
            }
            .padding()
        }
        .task {
            // Run simulation off main actor
            if let payload = try? record.decodedPayload() {
                let simResult = await Task.detached {
                    let sim = SolutionSimulator()
                    return sim.run(level: level, strokes: payload.strokes, captureEveryNthStep: 2)
                }.value
                
                self.result = simResult
                self.scene = ReplayScene(level: level, shapes: simResult.shapes)
                if let first = simResult.frames.first {
                    self.scene?.render(frame: first)
                }
                self.isPlaying = true
            }
        }
        .onReceive(Timer.publish(every: 2.0/60.0, on: .main, in: .common).autoconnect()) { _ in
            if isPlaying, let res = result {
                if frameIndex < res.frames.count - 1 {
                    frameIndex += 1
                    updateSceneFrame()
                } else {
                    isPlaying = false
                }
            }
        }
    }
    
    private func updateSceneFrame() {
        if let res = result, let scene = scene, frameIndex < res.frames.count {
            scene.render(frame: res.frames[frameIndex])
        }
    }
}
