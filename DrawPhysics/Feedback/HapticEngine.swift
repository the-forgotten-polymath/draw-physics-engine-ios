import CoreHaptics
import Foundation

@MainActor
public final class HapticEngine {
    public static let shared = HapticEngine()
    
    private var engine: CHHapticEngine?
    private var drawPlayer: CHHapticAdvancedPatternPlayer?
    private var isEngineRunning = false
    
    private init() {
        setup()
    }
    
    private func setup() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason)")
                Task { @MainActor in
                    self?.isEngineRunning = false
                }
            }
            
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                Task { @MainActor in
                    self?.startEngine()
                }
            }
            
            startEngine()
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    private func startEngine() {
        guard let engine = engine else { return }
        do {
            try engine.start()
            isEngineRunning = true
            setupDrawPlayer()
        } catch {
            print("Failed to start haptic engine: \(error)")
        }
    }
    
    private func setupDrawPlayer() {
        guard let engine = engine, isEngineRunning else { return }
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
        
        // A continuous event for the duration of the drawing
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 100)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            drawPlayer = try engine.makeAdvancedPlayer(with: pattern)
        } catch {
            print("Failed to create draw haptic player: \(error)")
        }
    }
    
    public func startDrawing() {
        guard isEngineRunning else {
            startEngine()
            return
        }
        do {
            try drawPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to start drawing haptic: \(error)")
        }
    }
    
    public func stopDrawing() {
        do {
            try drawPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop drawing haptic: \(error)")
        }
    }
    
    public func playContact(impulse: Double) {
        guard isEngineRunning, let engine = engine else { return }
        // Ignore resting contacts
        if impulse < 5.0 { return }
        
        let intensityValue = Float(min(max(impulse / 100.0, 0.3), 1.0))
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensityValue)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play contact haptic: \(error)")
        }
    }
    
    public func playGoal() {
        guard isEngineRunning, let engine = engine else { return }
        
        // Distinct pattern: two quick strong pulses
        let intensity1 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness1 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let event1 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity1, sharpness1], relativeTime: 0)
        
        let intensity2 = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness2 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let event2 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity2, sharpness2], relativeTime: 0.15)
        
        do {
            let pattern = try CHHapticPattern(events: [event1, event2], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play goal haptic: \(error)")
        }
    }
}
