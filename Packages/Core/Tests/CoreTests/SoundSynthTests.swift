import Foundation
import Testing
@testable import Core

@Suite struct SoundSynthTests {
    func rms(_ s: ArraySlice<Float>) -> Double {
        (s.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(s.count, 1))).squareRoot()
    }

    @Test func lengthsMatchTheDesign() {
        #expect(SoundSynth.snapClick().count == Int((0.07 * 44100).rounded(.up)))
        #expect(SoundSynth.tileAdd().count == Int((0.18 * 44100).rounded(.up)))
    }

    @Test func soundsAreAudibleButQuiet() {
        for s in [SoundSynth.snapClick(), SoundSynth.tileAdd()] {
            let peak = s.map { abs($0) }.max()!
            #expect(peak > 0.005)
            #expect(peak < 0.25)
            #expect(s.allSatisfy { $0.isFinite })
        }
    }

    @Test func theyDecayToNearSilence() {
        for s in [SoundSynth.snapClick(), SoundSynth.tileAdd()] {
            let n = s.count
            #expect(rms(s[(n * 4 / 5)...]) < rms(s[..<(n / 5)]) * 0.2)
        }
    }

    @Test func deterministic() {
        #expect(SoundSynth.snapClick() == SoundSynth.snapClick())
        #expect(SoundSynth.tileAdd() == SoundSynth.tileAdd())
    }

    @Test func tileAddIsLongerAndSofterThanTheSnap() {
        let snap = SoundSynth.snapClick(), add = SoundSynth.tileAdd()
        #expect(add.count > snap.count)
        #expect(add.map { abs($0) }.max()! < snap.map { abs($0) }.max()! * 1.5)
    }

    @Test func otherSampleRatesWork() {
        #expect(SoundSynth.snapClick(sampleRate: 48000).count == Int((0.07 * 48000).rounded(.up)))
    }

    @Test func lowpassKeepsLowFrequenciesAndCutsHighOnes() {
        func gain(at frequency: Double) -> Double {
            var f = SoundSynth.Biquad(.lowpass(frequency: 700), sampleRate: 44100)
            var peak = 0.0
            for i in 0..<4410 {
                let y = f.process(sin(2 * .pi * frequency * Double(i) / 44100))
                if i > 2000 { peak = max(peak, abs(y)) }
            }
            return peak
        }
        #expect(gain(at: 100) > 0.9)
        #expect(gain(at: 8000) < 0.05)
    }
}
