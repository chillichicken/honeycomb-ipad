import AVFoundation
import Core

/// Plays the game's two sounds. The buffers are synthesized once (see `SoundSynth`)
/// and played through a small round-robin pool of players, so rapid sounds (the
/// "+" button held down) overlap instead of cutting each other off.
@Observable @MainActor
final class SoundPlayer {
    private static let key = "soundEnabled"
    private static let voices = 4

    /// On by default; remembered across launches. Respects the silent switch.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var players: [AVAudioPlayerNode] = []
    @ObservationIgnored private var nextVoice = 0
    @ObservationIgnored private let snap: AVAudioPCMBuffer
    @ObservationIgnored private let add: AVAudioPCMBuffer

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        snap = Self.buffer(SoundSynth.snapClick(), format)
        add = Self.buffer(SoundSynth.tileAdd(), format)
        for _ in 0..<Self.voices {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
    }

    func playSnap() { play(snap) }
    func playTileAdd() { play(add) }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard enabled, startEngine() else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// Started on first use (and again if the system stopped it, e.g. after a call).
    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private static func buffer(_ samples: [Float], _ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
