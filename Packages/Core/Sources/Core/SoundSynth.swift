import Foundation

/// The game's two sounds, synthesized to sample buffers rather than shipped as
/// audio files (no assets to source or license). Pure DSP with a fixed noise
/// seed, so it is deterministic and testable without any audio hardware.
public enum SoundSynth {
    /// A tile snapped into place: a quiet, muffled rim-shot tick. Band-passed
    /// noise (the "crack") over a very brief low sine (the body), both decaying fast.
    public static func snapClick(sampleRate: Double = 44100) -> [Float] {
        render(
            sampleRate: sampleRate, noiseSeconds: 0.04, bodySeconds: 0.07,
            noiseFilter: .bandpass(frequency: 1400, q: 0.6),
            noiseGain: Envelope(from: 0.07, to: 0.0004, seconds: 0.03),
            bodyGlide: (from: 170, to: 85, seconds: 0.05),
            bodyGain: Envelope(from: 0.04, to: 0.0004, seconds: 0.06))
    }

    /// A new tile appeared: the same two layers dialed way down: duller, quieter,
    /// a slower glide over a longer decay, a soft relaxed "bloop" rather than a snap.
    public static func tileAdd(sampleRate: Double = 44100) -> [Float] {
        render(
            sampleRate: sampleRate, noiseSeconds: 0.10, bodySeconds: 0.18,
            noiseFilter: .lowpass(frequency: 700),
            noiseGain: Envelope(from: 0.02, to: 0.0003, seconds: 0.09),
            bodyGlide: (from: 220, to: 130, seconds: 0.14),
            bodyGain: Envelope(from: 0.045, to: 0.0003, seconds: 0.16))
    }

    // MARK: Building blocks

    /// Exponential ramp from `from` to `to` over `seconds`, then holds `to`.
    struct Envelope {
        let from: Double
        let to: Double
        let seconds: Double

        func value(at t: Double) -> Double {
            t >= seconds ? to : from * pow(to / from, t / seconds)
        }
    }

    enum FilterKind {
        case bandpass(frequency: Double, q: Double)
        case lowpass(frequency: Double)
    }

    /// A biquad filter (RBJ cookbook) processing one sample at a time.
    struct Biquad {
        private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        init(_ kind: FilterKind, sampleRate: Double) {
            let f: Double, q: Double
            switch kind {
            case .bandpass(let frequency, let qq): f = frequency; q = qq
            case .lowpass(let frequency): f = frequency; q = 0.7071
            }
            let w0 = 2 * Double.pi * f / sampleRate
            let alpha = sin(w0) / (2 * q)
            let cosW = cos(w0)
            let a0 = 1 + alpha
            switch kind {
            case .bandpass:  // constant 0 dB peak gain
                b0 = alpha / a0; b1 = 0; b2 = -alpha / a0
            case .lowpass:
                b0 = (1 - cosW) / 2 / a0; b1 = (1 - cosW) / a0; b2 = (1 - cosW) / 2 / a0
            }
            a1 = -2 * cosW / a0
            a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private static func render(
        sampleRate: Double, noiseSeconds: Double, bodySeconds: Double, noiseFilter: FilterKind,
        noiseGain: Envelope, bodyGlide: (from: Double, to: Double, seconds: Double), bodyGain: Envelope
    ) -> [Float] {
        let count = Int((max(noiseSeconds, bodySeconds) * sampleRate).rounded(.up))
        var out = [Float](repeating: 0, count: count)

        // noise: a fixed-seed generator, so every run sounds the same
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextNoise() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53) * 2 - 1
        }
        var filter = Biquad(noiseFilter, sampleRate: sampleRate)
        let noiseCount = Int(noiseSeconds * sampleRate)
        for i in 0..<noiseCount {
            let t = Double(i) / sampleRate
            out[i] += Float(filter.process(nextNoise()) * noiseGain.value(at: t))
        }

        // body: a sine gliding exponentially from one pitch to another
        var phase = 0.0
        let bodyCount = Int(bodySeconds * sampleRate)
        for i in 0..<bodyCount {
            let t = Double(i) / sampleRate
            let f = Envelope(from: bodyGlide.from, to: bodyGlide.to, seconds: bodyGlide.seconds).value(at: t)
            phase += 2 * Double.pi * f / sampleRate
            out[i] += Float(sin(phase) * bodyGain.value(at: t))
        }
        return out.map { max(-1, min(1, $0)) }
    }
}
