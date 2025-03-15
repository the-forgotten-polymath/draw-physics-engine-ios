import Foundation
import AVFoundation
import Observation

/// Audio + icon instruction. Every game is playable without reading, at every age band
/// (`00_README.md` §6), so speech is not an accessibility extra — it is the primary channel.
@MainActor
@Observable
public final class Instructor {
    private let synthesizer = AVSpeechSynthesizer()

    public private(set) var isSpeaking = false
    /// Child-controlled. Off means icons and haptics carry everything, which some children
    /// prefer and some rooms require.
    public var isVoiceEnabled = true
    public var rate: Float = 0.44

    public init() {}

    public func say(_ text: String, interrupting: Bool = true) {
        guard isVoiceEnabled, !text.isEmpty else { return }
        if interrupting, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.1
        // Deliberately not forcing a specific voice: the child's chosen system voice is the
        // one they can understand, and overriding it breaks VoiceOver users' expectations.
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        synthesizer.speak(utterance)
        // AVSpeechSynthesizer's delegate is the accurate signal, but for a HUD flag the
        // approximation is enough and avoids an NSObject subclass for one boolean.
        Task { @MainActor in
            while synthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            isSpeaking = false
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

/// A no-reading-required instruction step: an SF Symbol, a spoken line, and nothing else.
public struct InstructionStep: Identifiable, Sendable {
    public let id: Int
    public let symbolName: String
    public let spoken: String

    public init(id: Int, symbolName: String, spoken: String) {
        self.id = id
        self.symbolName = symbolName
        self.spoken = spoken
    }
}

public struct InstructionScript: Sendable {
    public let steps: [InstructionStep]
    public init(steps: [InstructionStep]) { self.steps = steps }
}
