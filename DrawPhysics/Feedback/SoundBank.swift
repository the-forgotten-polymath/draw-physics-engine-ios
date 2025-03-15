import AVFoundation

@MainActor
public final class SoundBank {
    public static let shared = SoundBank()
    
    private let engine = AVAudioEngine()
    private let drawPlayer = AVAudioPlayerNode()
    private let contactPlayer = AVAudioPlayerNode()
    private let goalPlayer = AVAudioPlayerNode()
    
    // Procedural buffers
    private var contactBuffers: [AVAudioPCMBuffer] = []
    private var goalBuffer: AVAudioPCMBuffer?
    
    private init() {
        setup()
        generateBuffers()
    }
    
    private func setup() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        
        engine.attach(drawPlayer)
        engine.attach(contactPlayer)
        engine.attach(goalPlayer)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        engine.connect(drawPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(contactPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(goalPlayer, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func generateBuffers() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        
        // 1. Contact Buffers: Short sine thuds with varying pitches
        let baseFrequencies = [100.0, 150.0, 200.0, 250.0]
        for freq in baseFrequencies {
            if let buf = generateThud(frequency: freq, duration: 0.1, format: format) {
                contactBuffers.append(buf)
            }
        }
        
        // 2. Goal Buffer: Rising perfect fifth (C4 to G4) pentatonic
        goalBuffer = generateRisingFifth(format: format)
    }
    
    private func generateThud(frequency: Double, duration: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        
        let channelData = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let increment = frequency * twoPi / format.sampleRate
        var phase = 0.0
        
        for i in 0..<Int(frameCount) {
            let t = Double(i) / Double(frameCount)
            let envelope = Float(exp(-5.0 * t))
            channelData[i] = Float(sin(phase)) * envelope * 0.5
            phase += increment
            if phase >= twoPi { phase -= twoPi }
        }
        return buffer
    }
    
    private func generateRisingFifth(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let freqs = [261.63, 329.63, 392.00]
        let durationPerNote = 0.15
        let totalDuration = durationPerNote * Double(freqs.count)
        
        let frameCount = AVAudioFrameCount(totalDuration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        
        let channelData = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        
        var currentFrame = 0
        for freq in freqs {
            let increment = freq * twoPi / format.sampleRate
            var phase = 0.0
            let framesForNote = Int(durationPerNote * format.sampleRate)
            
            for i in 0..<framesForNote {
                if currentFrame >= Int(frameCount) { break }
                let t = Double(i) / Double(framesForNote)
                let envelope = Float(sin(t * Double.pi))
                channelData[currentFrame] = Float(sin(phase)) * envelope * 0.4
                phase += increment
                if phase >= twoPi { phase -= twoPi }
                currentFrame += 1
            }
        }
        return buffer
    }
    
    public func playContact(impulse: Double) {
        guard !contactBuffers.isEmpty else { return }
        let intensity = min(max(impulse / 100.0, 0.0), 1.0)
        let index = Int(intensity * Double(contactBuffers.count - 1))
        let buffer = contactBuffers[index]
        
        if engine.isRunning {
            contactPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !contactPlayer.isPlaying {
                contactPlayer.play()
            }
        }
    }
    
    public func playDraw(speed: Double) {
        // We could synthesize noise here, but for now just play a very short soft noise thud.
        // A full noise burst generator is complex to manage continuously without asset files,
        // so we map speed to one of the contact buffers at very low volume.
        guard !contactBuffers.isEmpty else { return }
        let index = 0 // lowest pitch
        let buffer = contactBuffers[index]
        
        if engine.isRunning {
            drawPlayer.volume = Float(min(max(speed / 1000.0, 0.1), 0.5)) // volume mapped to speed
            drawPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !drawPlayer.isPlaying {
                drawPlayer.play()
            }
        }
    }
    
    public func playGoal() {
        guard let buffer = goalBuffer else { return }
        if engine.isRunning {
            goalPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !goalPlayer.isPlaying {
                goalPlayer.play()
            }
        }
    }
}
