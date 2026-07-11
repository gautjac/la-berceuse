import XCTest
@testable import La_Berceuse

final class LaBerceuseTests: XCTestCase {

    // MARK: - Breath pacing math

    func testBreathCycleDuration() {
        XCTAssertEqual(BreathPattern.fourSevenEight.cycleDuration, 19, accuracy: 0.0001)
        XCTAssertEqual(BreathPattern.box.cycleDuration, 16, accuracy: 0.0001)
        XCTAssertEqual(BreathPattern.coherent.cycleDuration, 11, accuracy: 0.0001)
    }

    func testBreathResolvePhases() {
        let p = BreathPattern.box  // 4 in, 4 hold, 4 out, 4 hold
        XCTAssertEqual(p.resolve(at: 0).phase, .inhale)
        XCTAssertEqual(p.resolve(at: 2).phase, .inhale)
        XCTAssertEqual(p.resolve(at: 5).phase, .holdIn)
        XCTAssertEqual(p.resolve(at: 9).phase, .exhale)
        XCTAssertEqual(p.resolve(at: 13).phase, .holdOut)
    }

    func testBreathResolveWrapsAroundCycle() {
        let p = BreathPattern.box
        // 16s cycle: t=17 wraps to 1s → inhale.
        XCTAssertEqual(p.resolve(at: 17).phase, .inhale)
        XCTAssertEqual(p.resolve(at: 17).phaseElapsed, 1, accuracy: 0.0001)
        // Negative time wraps too.
        XCTAssertEqual(p.resolve(at: -1).phase, .holdOut)
    }

    func testBreathPhaseProgress() {
        let p = BreathPattern.box
        let r = p.resolve(at: 2)  // halfway through 4s inhale
        XCTAssertEqual(r.phaseProgress, 0.5, accuracy: 0.0001)
    }

    func testOrbScaleGrowsOnInhaleShrinksOnExhale() {
        let p = BreathPattern.box
        let startInhale = p.orbScale(at: 0.01)
        let endInhale = p.orbScale(at: 3.99)
        XCTAssertLessThan(startInhale, endInhale, "orb should grow during inhale")
        XCTAssertEqual(endInhale, 1.0, accuracy: 0.02)

        let startExhale = p.orbScale(at: 8.01)
        let endExhale = p.orbScale(at: 11.99)
        XCTAssertGreaterThan(startExhale, endExhale, "orb should shrink during exhale")
        XCTAssertEqual(endExhale, BreathPhase.exhaleFloor, accuracy: 0.02)
    }

    func testOrbScaleStaysFullDuringHold() {
        let p = BreathPattern.box
        // holdIn spans 4..8; scale should stay at ~1.0 throughout.
        XCTAssertEqual(p.orbScale(at: 5), 1.0, accuracy: 0.001)
        XCTAssertEqual(p.orbScale(at: 7), 1.0, accuracy: 0.001)
    }

    func testEaseInOutBounds() {
        XCTAssertEqual(BreathPattern.easeInOut(0), 0, accuracy: 0.0001)
        XCTAssertEqual(BreathPattern.easeInOut(1), 1, accuracy: 0.0001)
        XCTAssertEqual(BreathPattern.easeInOut(0.5), 0.5, accuracy: 0.0001)
        // Clamps out-of-range input.
        XCTAssertEqual(BreathPattern.easeInOut(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(BreathPattern.easeInOut(2), 1, accuracy: 0.0001)
    }

    func testZeroDurationPhasesAreSkipped() {
        // Coherent has zero-length holds; resolve must never land on them.
        let p = BreathPattern.coherent
        for t in stride(from: 0.0, to: p.cycleDuration, by: 0.25) {
            let phase = p.resolve(at: t).phase
            XCTAssertTrue(phase == .inhale || phase == .exhale,
                          "coherent should only ever be inhale/exhale, got \(phase) at \(t)")
        }
    }

    // MARK: - Cognitive shuffle generator

    func testShuffleDeterministicWithSeed() {
        var a = CognitiveShuffle(lang: .fr, seed: 42)
        var b = CognitiveShuffle(lang: .fr, seed: 42)
        XCTAssertEqual(a.stream(30), b.stream(30), "same seed → same sequence")
    }

    func testShuffleDiffersWithDifferentSeed() {
        var a = CognitiveShuffle(lang: .en, seed: 1)
        var b = CognitiveShuffle(lang: .en, seed: 2)
        XCTAssertNotEqual(a.stream(20), b.stream(20))
    }

    func testShuffleNoRepeatWithinOnePass() {
        var s = CognitiveShuffle(lang: .fr, seed: 7)
        let n = s.bankSize
        let pass = s.stream(n)
        XCTAssertEqual(Set(pass).count, n, "a full pass should cover the bank with no repeats")
    }

    func testShuffleNoImmediateRepeatAcrossSeam() {
        var s = CognitiveShuffle(lang: .en, seed: 99)
        let n = s.bankSize
        let two = s.stream(n * 2)
        for i in 1..<two.count {
            XCTAssertNotEqual(two[i], two[i - 1], "no word should immediately repeat at index \(i)")
        }
    }

    func testWordBanksAreNeutralAndDistinct() {
        XCTAssertGreaterThan(CognitiveShuffle.bankFR.count, 60)
        XCTAssertGreaterThan(CognitiveShuffle.bankEN.count, 60)
        XCTAssertEqual(Set(CognitiveShuffle.bankFR).count, CognitiveShuffle.bankFR.count, "no dup FR words")
        XCTAssertEqual(Set(CognitiveShuffle.bankEN).count, CognitiveShuffle.bankEN.count, "no dup EN words")
    }

    // MARK: - Fade-curve math

    func testFadeMultiplierFullBeforeFadeWindow() {
        XCTAssertEqual(FadeMath.multiplier(remaining: 120, fadeDuration: 60), 1, accuracy: 0.0001)
        XCTAssertEqual(FadeMath.multiplier(remaining: 60, fadeDuration: 60), 1, accuracy: 0.0001)
    }

    func testFadeMultiplierZeroAtSilence() {
        XCTAssertEqual(FadeMath.multiplier(remaining: 0, fadeDuration: 60), 0, accuracy: 0.0001)
        XCTAssertEqual(FadeMath.multiplier(remaining: -5, fadeDuration: 60), 0, accuracy: 0.0001)
    }

    func testFadeMultiplierMonotonicDecreasing() {
        var last = 1.0
        for r in stride(from: 60.0, through: 0.0, by: -1.0) {
            let m = FadeMath.multiplier(remaining: r, fadeDuration: 60)
            XCTAssertLessThanOrEqual(m, last + 1e-9, "fade should never increase as time runs out")
            last = m
        }
    }

    func testFadeMidpointIsEqualPower() {
        // Halfway through the fade, equal-power curve ≈ cos(π/4) ≈ 0.707.
        let m = FadeMath.multiplier(remaining: 30, fadeDuration: 60)
        XCTAssertEqual(m, 0.7071, accuracy: 0.01)
    }

    // MARK: - Sleep timer logic

    func testSleepTimerOffByDefault() {
        let t = SleepTimer(total: 0)
        XCTAssertFalse(t.isActive)
        XCTAssertEqual(t.volumeMultiplier, 1, accuracy: 0.0001)
    }

    func testSleepTimerCountsDown() {
        var t = SleepTimer(total: 600, fade: 60)
        XCTAssertEqual(t.remaining, 600, accuracy: 0.0001)
        t = t.advanced(by: 100)
        XCTAssertEqual(t.remaining, 500, accuracy: 0.0001)
        XCTAssertFalse(t.isFading)
        XCTAssertEqual(t.volumeMultiplier, 1, accuracy: 0.0001)
    }

    func testSleepTimerEntersFadeAndFinishes() {
        var t = SleepTimer(total: 100, fade: 60)
        t = t.advanced(by: 50)   // remaining 50 → inside fade window
        XCTAssertTrue(t.isFading)
        XCTAssertLessThan(t.volumeMultiplier, 1)
        XCTAssertGreaterThan(t.volumeMultiplier, 0)
        t = t.advanced(by: 60)   // overshoots → finished
        XCTAssertTrue(t.isFinished)
        XCTAssertEqual(t.volumeMultiplier, 0, accuracy: 0.0001)
    }

    func testSleepTimerFadeCappedToTotal() {
        // A 30s timer with a requested 60s fade caps the fade to 30s.
        let t = SleepTimer(total: 30, fade: 60)
        XCTAssertEqual(t.fade, 30, accuracy: 0.0001)
    }

    func testSleepTimerClockString() {
        let t = SleepTimer(total: 125, fade: 60)
        XCTAssertEqual(t.clockString, "2:05")
    }

    func testSleepTimerNeverNegative() {
        let t = SleepTimer(total: 60, fade: 30).advanced(by: 999)
        XCTAssertEqual(t.remaining, 0, accuracy: 0.0001)
        XCTAssertEqual(t.elapsed, 60, accuracy: 0.0001)
    }

    // MARK: - Nidra pacing

    func testNidraPacingFillsDuration() {
        let s = NidraScript.bodyScan10
        let pace = s.secondsPerLine(.fr)
        let total = pace * Double(s.lines(.fr).count)
        XCTAssertEqual(total, Double(s.minutes) * 60, accuracy: 0.001)
    }

    func testNidraScriptsBilingualParity() {
        for s in NidraScript.all {
            XCTAssertEqual(s.linesFR.count, s.linesEN.count,
                           "\(s.id) must have matching FR/EN line counts")
            XCTAssertFalse(s.linesFR.isEmpty)
        }
    }

    // MARK: - Generative music: scales & pitch

    func testScaleWrapsAcrossOctaves() {
        let s = MusicScale.pentatonicMajor   // [0,2,4,7,9]
        XCTAssertEqual(s.midi(rootMidi: 60, index: 0), 60)
        XCTAssertEqual(s.midi(rootMidi: 60, index: 4), 69)         // top of octave
        XCTAssertEqual(s.midi(rootMidi: 60, index: 5), 72)         // tonic, one octave up
        XCTAssertEqual(s.midi(rootMidi: 60, index: -1), 60 + 9 - 12) // degree 4 one octave down
    }

    func testPentatonicHasNoSemitoneClashes() {
        // Adjacent scale degrees in a pentatonic are always ≥ 2 semitones apart,
        // which is what keeps simultaneous notes consonant.
        for scale in [MusicScale.pentatonicMajor, .pentatonicMinor] {
            let d = scale.degrees
            for i in 1..<d.count { XCTAssertGreaterThanOrEqual(d[i] - d[i - 1], 2) }
        }
    }

    func testPitchFrequencyReference() {
        XCTAssertEqual(Pitch.frequency(midi: 69), 440, accuracy: 0.0001)   // A4
        XCTAssertEqual(Pitch.frequency(midi: 57), 220, accuracy: 0.0001)   // A3
    }

    // MARK: - Amplitude-modulation math (the brain.fm layer)

    func testAModStaysWithinBounds() {
        for depthTimes100 in stride(from: 0, through: 60, by: 5) {
            let depth = Double(depthTimes100) / 100.0
            let clamped = min(0.35, depth)
            for p in stride(from: 0.0, through: 1.0, by: 0.05) {
                let g = AModMath.gain(phase: p, depth: depth)
                XCTAssertLessThanOrEqual(g, 1.0 + 1e-9, "never boosts past unity")
                XCTAssertGreaterThanOrEqual(g, 1 - clamped - 1e-9, "never ducks below 1−depth")
            }
        }
    }

    func testAModPhaseExtremes() {
        XCTAssertEqual(AModMath.gain(phase: 0, depth: 0.3), 1.0, accuracy: 1e-9)       // peak
        XCTAssertEqual(AModMath.gain(phase: 0.5, depth: 0.3), 0.7, accuracy: 1e-9)     // trough = 1−depth
        XCTAssertEqual(AModMath.gain(phase: 0.37, depth: 0.0), 1.0, accuracy: 1e-9)    // no effect at 0
    }

    // MARK: - Chord progression voice-leading

    func testProgressionStaysConsonantAndNear() {
        let prog = ChordProgression()            // roots [0,3,4,1,5], maxStep 2
        var rng = SeededRNG(seed: 0xC0FFEE)
        var current = 0
        for _ in 0..<2000 {
            let next = prog.nextRoot(current: current, using: &rng)
            XCTAssertTrue(prog.allowedRoots.contains(next), "stays in the chord pool")
            XCTAssertLessThanOrEqual(abs(next - current), prog.maxStep, "no jarring leap")
            current = next
        }
    }

    func testProgressionIsDeterministicForASeed() {
        func run() -> [Int] {
            let prog = ChordProgression()
            var rng = SeededRNG(seed: 42)
            var cur = 0
            return (0..<20).map { _ in cur = prog.nextRoot(current: cur, using: &rng); return cur }
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: - The adaptive director (Endel layer)

    private func baseContext(progress: Double, hr: Double? = nil,
                             complexity: Double = 1) -> MusicContext {
        MusicContext(program: .detente, userIntensity: 1, userPulse: 1,
                     userComplexity: complexity, sessionProgress: progress,
                     hourOfDay: 22, breathCyclePeriod: 11, heartRate: hr)
    }

    func testSessionDeEnergizesMonotonically() {
        var lastDensity = Double.infinity
        var lastMelody = Double.infinity
        var lastChordSeconds = -Double.infinity
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let p = MusicDirector.params(for: baseContext(progress: step))
            XCTAssertLessThanOrEqual(p.noteDensity, lastDensity + 1e-9, "density only falls")
            XCTAssertLessThanOrEqual(p.melodyGain, lastMelody + 1e-9, "melody only recedes")
            XCTAssertGreaterThanOrEqual(p.chordSeconds, lastChordSeconds - 1e-9, "chords only lengthen")
            lastDensity = p.noteDensity
            lastMelody = p.melodyGain
            lastChordSeconds = p.chordSeconds
        }
    }

    func testRegisterDropsLateInTheSession() {
        let early = MusicDirector.params(for: baseContext(progress: 0))
        let late = MusicDirector.params(for: baseContext(progress: 1))
        XCTAssertLessThanOrEqual(late.rootMidi, early.rootMidi, "drops an octave near sleep")
    }

    func testModulationStaysSubtle() {
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let p = MusicDirector.params(for: baseContext(progress: step))
            XCTAssertLessThanOrEqual(p.modDepth, 0.35, "pulse never becomes a throb")
            XCTAssertGreaterThan(p.modDepth, 0, "pulse present when the user asks for it")
        }
    }

    func testNoPulseWhenUserPulseZero() {
        let ctx = MusicContext(program: .souffle, userIntensity: 0.7, userPulse: 0,
                               sessionProgress: 0, hourOfDay: 23, breathCyclePeriod: 8)
        XCTAssertEqual(MusicDirector.params(for: ctx).modDepth, 0, accuracy: 1e-9)
    }

    func testSouffleLocksPulseToBreathPeriod() {
        let ctx = MusicContext(program: .souffle, userIntensity: 0.6, userPulse: 0.5,
                               sessionProgress: 0, hourOfDay: 23,
                               breathCyclePeriod: 11, heartRate: nil)   // coherent 5.5
        // One modulation cycle per breath → ~0.0909 Hz.
        XCTAssertEqual(MusicDirector.params(for: ctx).modRateHz, 1.0 / 11.0, accuracy: 1e-6)
    }

    func testCircadianIsCalmerOvernight() {
        XCTAssertGreaterThan(MusicDirector.circadianCalm(hourOfDay: 2),
                             MusicDirector.circadianCalm(hourOfDay: 22))
        XCTAssertEqual(MusicDirector.circadianCalm(hourOfDay: 14), 0, accuracy: 1e-9) // daytime neutral
    }

    func testHeartRateNudgeIsBoundedAndGraceful() {
        let none = MusicDirector.params(for: baseContext(progress: 0, hr: nil))
        let low = MusicDirector.params(for: baseContext(progress: 0, hr: 50))
        let high = MusicDirector.params(for: baseContext(progress: 0, hr: 95))
        // A higher HR yields a slightly quicker pulse, a lower one slower — but
        // always within a gentle band around the no-HR baseline.
        XCTAssertGreaterThan(high.modRateHz, low.modRateHz)
        XCTAssertEqual(low.modRateHz, none.modRateHz * 0.92, accuracy: 1e-6)
    }

    func testDirectorOutputsAreFiniteAndInRange() {
        for prog in MusicProgram.allCases {
            for step in stride(from: 0.0, through: 1.0, by: 0.25) {
                let ctx = MusicContext(program: prog, userIntensity: 0.8, userPulse: 0.7,
                                       sessionProgress: step, hourOfDay: 1, breathCyclePeriod: 16, heartRate: 64)
                let p = MusicDirector.params(for: ctx)
                for g in [p.padGain, p.bassGain, p.melodyGain, p.brightness] {
                    XCTAssertTrue(g.isFinite && g >= 0 && g <= 1)
                }
                XCTAssertGreaterThan(p.noteDensity, 0)
                XCTAssertGreaterThan(p.chordSeconds, 0)
                XCTAssertGreaterThan(p.modRateHz, 0)
            }
        }
    }

    // MARK: - Complexity (the new axis)

    private func cxContext(_ complexity: Double, intensity: Double = 0.8,
                           progress: Double = 0) -> MusicContext {
        // Daytime hour keeps circadian neutral so the test isolates `complexity`.
        MusicContext(program: .detente, userIntensity: intensity, userPulse: 0.5,
                     userComplexity: complexity, sessionProgress: progress,
                     hourOfDay: 14, breathCyclePeriod: 11)
    }

    func testComplexityRaisesMusicalActivity() {
        let low = MusicDirector.params(for: cxContext(0.15))
        let high = MusicDirector.params(for: cxContext(0.9))
        XCTAssertGreaterThan(high.noteDensity, low.noteDensity, "busier")
        XCTAssertLessThan(high.chordSeconds, low.chordSeconds, "harmony moves more often")
        XCTAssertGreaterThan(high.melodyGain, low.melodyGain, "melody is more present")
        XCTAssertGreaterThan(high.melodyRange, low.melodyRange, "melody roams wider")
        XCTAssertGreaterThanOrEqual(high.progressionRoots.count, low.progressionRoots.count, "richer harmony")
        XCTAssertGreaterThanOrEqual(high.chordStack.count, low.chordStack.count, "richer voicings")
    }

    func testFullComplexityFlowsDensely() {
        // At full complexity the melody should be close to continuous — a note
        // roughly every ~1.3 s or faster (≥ 45 notes/min), not sparse plinks.
        let p = MusicDirector.params(for: cxContext(1.0))
        XCTAssertGreaterThan(p.noteDensity, 45, "full complexity = a flowing melody")
    }

    func testComplexityGapIsWide() {
        // The whole point of this pass: a big spread between low and high. Full
        // complexity is many times busier than a low setting.
        let lowMid = MusicDirector.params(for: cxContext(0.2))
        let full = MusicDirector.params(for: cxContext(1.0))
        XCTAssertGreaterThan(full.noteDensity, lowMid.noteDensity * 5,
                             "the gap between low and high complexity is wide")
    }

    func testLowestComplexityIsAStaticDrone() {
        let p = MusicDirector.params(for: cxContext(0.0))
        XCTAssertEqual(p.progressionRoots, [0], "stays on the tonic — no chord changes")
        XCTAssertEqual(p.progressionMaxStep, 1)
        XCTAssertLessThan(p.melodyGain, 0.02, "no melodic activity — felt, not heard")
        XCTAssertEqual(p.chordStack, [0, 2], "the simplest voicing")
    }

    func testComplexityIsDecoupledFromIntensity() {
        // The decisive proof of the split: a QUIET-but-RICH setting must be
        // busier than a LOUD-but-SPARSE one. Activity follows complexity, not
        // intensity.
        let quietRich = MusicDirector.params(for: cxContext(0.9, intensity: 0.2))
        let loudSparse = MusicDirector.params(for: cxContext(0.15, intensity: 0.95))
        XCTAssertGreaterThan(quietRich.noteDensity, loudSparse.noteDensity)
        XCTAssertGreaterThan(quietRich.melodyGain, loudSparse.melodyGain)
        // …while presence (pad/brightness) still follows intensity.
        XCTAssertGreaterThan(loudSparse.brightness, quietRich.brightness)
        XCTAssertGreaterThan(loudSparse.padGain, quietRich.padGain)
    }

    func testComplexitySimplifiesOverTheSession() {
        var lastRoots = Int.max
        var lastMelody = Double.infinity
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let p = MusicDirector.params(for: baseContext(progress: step, complexity: 1))
            XCTAssertLessThanOrEqual(p.progressionRoots.count, lastRoots, "harmony only simplifies")
            XCTAssertLessThanOrEqual(p.melodyGain, lastMelody + 1e-9, "melody only recedes")
            lastRoots = p.progressionRoots.count
            lastMelody = p.melodyGain
        }
    }

    func testComplexityMappingIsMonotone() {
        var lastStack = 0, lastRoots = 0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertGreaterThanOrEqual(MusicComplexity.chordStack(step).count, lastStack)
            XCTAssertGreaterThanOrEqual(MusicComplexity.progressionRoots(step).count, lastRoots)
            lastStack = MusicComplexity.chordStack(step).count
            lastRoots = MusicComplexity.progressionRoots(step).count
        }
    }

    // MARK: - Melody reverb + delay (the "back it into the mix" DSP)

    func testDelayLineReadsBackEarlierSample() {
        let line = DelayLine(maxSamples: 16)
        for i in 0..<10 { line.push(Double(i)) }     // last pushed = 9
        // tap(d) = the sample written d pushes ago (1 = most recent); tap(0) is
        // the write head, not yet written.
        XCTAssertEqual(line.tap(1), 9, accuracy: 1e-9)
        XCTAssertEqual(line.tap(2), 8, accuracy: 1e-9)
        XCTAssertEqual(line.tap(3), 7, accuracy: 1e-9)
        XCTAssertEqual(line.tap(0), 0, accuracy: 1e-9)
    }

    func testStereoReverbIsStableAndDecays() {
        let rev = StereoReverb(sampleRate: 44_100)
        var early = 0.0, late = 0.0
        for i in 0..<88_200 {                          // 2 seconds
            let x = i == 0 ? 1.0 : 0.0                  // a single impulse
            let (l, r) = rev.process(x, x, mod: 0)
            XCTAssertTrue(l.isFinite && r.isFinite, "reverb never blows up")
            XCTAssertLessThan(abs(l) + abs(r), 8, "stays bounded")
            if i < 4_410 { early += abs(l) + abs(r) }   // first 0.1 s
            if i >= 83_790 { late += abs(l) + abs(r) }  // last 0.1 s
        }
        XCTAssertLessThan(late, early * 0.2, "the tail decays toward silence")
    }

    func testStereoSpaceLeavesATailThenSettles() {
        let space = StereoSpace(sampleRate: 44_100)
        space.apply(echoWet: 0.4, echoFeedback: 0.45, reverbWet: 0.6, reverbFeedback: 0.82)
        var tailEnergy = 0.0, settled = 0.0
        for i in 0..<176_400 {                          // 4 seconds (shimmer rings longer)
            let dry = i == 0 ? 1.0 : 0.0
            let (l, r) = space.process(dry)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l) + abs(r), 12, "shimmer feedback stays bounded")
            if i > 100, i < 22_050 { tailEnergy += abs(l) + abs(r) }
            if i >= 171_990 { settled += abs(l) + abs(r) }
        }
        XCTAssertGreaterThan(tailEnergy, 0.01, "echo + reverb + shimmer leave an audible tail")
        XCTAssertLessThan(settled, 0.05, "and it eventually settles toward silence")
    }

    func testStereoSpaceIsActuallyStereo() {
        let space = StereoSpace(sampleRate: 44_100)
        space.apply(echoWet: 0.5, echoFeedback: 0.5, reverbWet: 0.6, reverbFeedback: 0.82)
        var diff = 0.0
        for i in 0..<44_100 {                           // 1 second
            let (l, r) = space.process(i == 0 ? 1.0 : 0.0)
            diff += abs(l - r)                          // ping-pong + decorrelated reverb ⇒ L ≠ R
        }
        XCTAssertGreaterThan(diff, 0.1, "the space produces a genuinely stereo image")
    }

    func testStereoSpaceSilenceInSilenceOut() {
        let space = StereoSpace(sampleRate: 44_100)
        space.apply(echoWet: 0.4, echoFeedback: 0.45, reverbWet: 0.6, reverbFeedback: 0.82)
        for _ in 0..<2_000 {
            let (l, r) = space.process(0)
            XCTAssertEqual(l, 0, accuracy: 1e-12)
            XCTAssertEqual(r, 0, accuracy: 1e-12)
        }
    }

    func testOctaveUpShimmerIsBounded() {
        let shifter = OctaveUp(sampleRate: 44_100)
        for i in 0..<44_100 {
            // Feed a 220 Hz tone; the shifter should stay finite and bounded.
            let x = sin(2 * .pi * 220 * Double(i) / 44_100)
            let y = shifter.process(x)
            XCTAssertTrue(y.isFinite)
            XCTAssertLessThan(abs(y), 2.5)
        }
    }

    func testDelayLineInterpolatesFractionalTaps() {
        let line = DelayLine(maxSamples: 16)
        for i in 0..<10 { line.push(Double(i)) }        // last pushed = 9 at tap(1)
        // Halfway between tap(1)=9 and tap(2)=8 → 8.5.
        XCTAssertEqual(line.tapInterpolated(1.5), 8.5, accuracy: 1e-9)
    }

    // MARK: - Stereo & tone shaping (the richness pass)

    func testPanIsEqualPower() {
        for p in stride(from: -1.0, through: 1.0, by: 0.1) {
            let (l, r) = Pan.gains(p)
            XCTAssertEqual(l * l + r * r, 1, accuracy: 1e-9, "constant perceived loudness")
        }
        XCTAssertEqual(Pan.gains(-1).l, 1, accuracy: 1e-9)   // hard left
        XCTAssertEqual(Pan.gains(1).r, 1, accuracy: 1e-9)    // hard right
        XCTAssertEqual(Pan.gains(0).l, Pan.gains(0).r, accuracy: 1e-9)   // centre balanced
    }

    func testSaturateIsSoftMonotonicAndOdd() {
        XCTAssertEqual(AudioShaping.saturate(0, drive: 1.5), 0, accuracy: 1e-12)
        // Odd symmetry.
        XCTAssertEqual(AudioShaping.saturate(0.6, drive: 1.5),
                       -AudioShaping.saturate(-0.6, drive: 1.5), accuracy: 1e-9)
        // Monotonic increasing and bounded.
        var last = -Double.infinity
        for x in stride(from: -3.0, through: 3.0, by: 0.1) {
            let y = AudioShaping.saturate(x, drive: 1.5)
            XCTAssertGreaterThan(y, last - 1e-9, "monotonic")
            XCTAssertLessThan(abs(y), 1.2, "soft-clips")
            last = y
        }
    }

    func testEchoAndReverbControlsMapMonotonically() {
        func params(echo: Double, reverb: Double) -> MusicParams {
            MusicDirector.params(for: MusicContext(
                program: .detente, userIntensity: 0.7, userPulse: 0.5, userComplexity: 0.7,
                sessionProgress: 0, hourOfDay: 14, breathCyclePeriod: 11,
                heartRate: nil, userEcho: echo, userReverb: reverb))
        }
        let dry = params(echo: 0, reverb: 0)
        let wet = params(echo: 1, reverb: 1)
        XCTAssertEqual(dry.echoWet, 0, accuracy: 1e-9, "echo off = no echo")
        XCTAssertEqual(dry.reverbWet, 0, accuracy: 1e-9, "reverb off = no tail")
        XCTAssertGreaterThan(wet.echoWet, dry.echoWet)
        XCTAssertGreaterThan(wet.echoFeedback, dry.echoFeedback, "more repeats")
        XCTAssertGreaterThan(wet.reverbWet, dry.reverbWet)
        XCTAssertGreaterThan(wet.reverbFeedback, dry.reverbFeedback, "longer tail")
        XCTAssertLessThanOrEqual(wet.reverbFeedback, 0.92, "but never runs away")
    }

    func testStereoSpaceControlsChangeTheTail() {
        func tailEnergy(echoWet: Double, reverbWet: Double) -> Double {
            let space = StereoSpace(sampleRate: 44_100)
            space.apply(echoWet: echoWet, echoFeedback: 0.45,
                        reverbWet: reverbWet, reverbFeedback: 0.82)
            var energy = 0.0
            for i in 0..<88_200 {                       // 2 seconds
                let (l, r) = space.process(i == 0 ? 1.0 : 0.0)
                if i > 50 { energy += abs(l) + abs(r) }  // everything after the dry hit
            }
            return energy
        }
        let dry = tailEnergy(echoWet: 0, reverbWet: 0)
        let wet = tailEnergy(echoWet: 0.5, reverbWet: 0.7)
        XCTAssertLessThan(dry, 0.02, "no wet mix → essentially no tail")
        XCTAssertGreaterThan(wet, dry + 0.5, "turning up echo + reverb adds an audible tail")
    }

    // MARK: - Rituals

    func testRitualPlanSoundsStepAlwaysRunsLast() {
        let plan = RitualPlan(name: "x", steps: [
            RitualStep(kind: .sounds, minutes: 30),
            RitualStep(kind: .breath, detail: "478", minutes: 3),
            RitualStep(kind: .shuffle, minutes: 5),
        ])
        XCTAssertEqual(plan.steps.last?.kind, .sounds, "sounds hands off to the night — it must close the plan")
        XCTAssertEqual(plan.steps.first?.kind, .breath)
    }

    func testRitualStepDurations() {
        XCTAssertEqual(RitualStep(kind: .breath, detail: "478", minutes: 3).seconds, 180, accuracy: 0.001)
        XCTAssertEqual(RitualStep(kind: .breath, minutes: 0).seconds, 30, accuracy: 0.001, "floors at 30 s")
        let nidra = RitualStep(kind: .nidra, detail: NidraScript.all[0].id)
        XCTAssertEqual(nidra.seconds, Double(NidraScript.all[0].minutes) * 60, accuracy: 0.001)
        XCTAssertEqual(RitualStep(kind: .sounds, minutes: 45).seconds, 0, accuracy: 0.001, "sounds is untimed")
    }

    func testDorsPlanShape() {
        let plan = RitualPlan.dors(breathPatternID: "coherent", timerMinutes: 45)
        XCTAssertEqual(plan.steps.map(\.kind), [.breath, .sounds])
        XCTAssertEqual(plan.steps[0].detail, "coherent")
        XCTAssertEqual(plan.steps[1].minutes, 45, accuracy: 0.001)
    }

    func testRescueHours() {
        XCTAssertFalse(RitualPlan.isRescueHour(0), "midnight is still bedtime, not a wake-up")
        XCTAssertTrue(RitualPlan.isRescueHour(1))
        XCTAssertTrue(RitualPlan.isRescueHour(3))
        XCTAssertTrue(RitualPlan.isRescueHour(4))
        XCTAssertFalse(RitualPlan.isRescueHour(5))
        XCTAssertFalse(RitualPlan.isRescueHour(22))
    }

    func testRitualStepsRoundTripThroughJSON() {
        let steps = [
            RitualStep(kind: .breath, detail: "sigh", minutes: 2),
            RitualStep(kind: .nidra, detail: "bodyscan10"),
            RitualStep(kind: .sounds, minutes: 60),
        ]
        let data = try! JSONEncoder().encode(steps)
        let back = try! JSONDecoder().decode([RitualStep].self, from: data)
        XCTAssertEqual(back, steps)
    }

    // MARK: - Carnet de nuit

    private func date(_ day: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = day; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func testNightMorningAssignment() {
        let cal = Calendar.current
        // A 10 p.m. ritual belongs to the NEXT morning's night…
        XCTAssertEqual(CarnetMath.nightMorning(for: date(10, hour: 22)),
                       cal.startOfDay(for: date(11, hour: 0)))
        // …a 3 a.m. rescue to the SAME morning.
        XCTAssertEqual(CarnetMath.nightMorning(for: date(11, hour: 3)),
                       cal.startOfDay(for: date(11, hour: 0)))
    }

    func testCarnetRitualGain() {
        let cal = Calendar.current
        // Ritual evenings (day 10 & 12) precede 8 h nights; plain nights get 7 h.
        let nights = [11, 12, 13, 14].map { d in
            NightRecord(morning: cal.startOfDay(for: date(d, hour: 0)),
                        asleepHours: (d == 11 || d == 13) ? 8.0 : 7.0)
        }
        let sessions = [("breath", date(10, hour: 22)), ("nidra", date(12, hour: 23))]
        let ins = CarnetMath.insights(nights: nights, sessions: sessions)
        XCTAssertEqual(ins.nightCount, 4)
        XCTAssertEqual(ins.ritualNightCount, 2)
        XCTAssertEqual(ins.ritualGainMinutes, 60, accuracy: 0.001, "8 h ritual nights vs 7 h plain = +60 min")
        XCTAssertEqual(ins.averageHours, 7.5, accuracy: 0.001)
    }

    func testCarnetStreakAndEmpty() {
        XCTAssertEqual(CarnetMath.insights(nights: [], sessions: []).nightCount, 0)
        let cal = Calendar.current
        let nights = [12, 13, 14].map {
            NightRecord(morning: cal.startOfDay(for: date($0, hour: 0)), asleepHours: 7)
        }
        // Rituals on the evenings before mornings 13 and 14 → streak of 2.
        let sessions = [("ritual", date(12, hour: 22)), ("ritual", date(13, hour: 22))]
        let ins = CarnetMath.insights(nights: nights, sessions: sessions)
        XCTAssertEqual(ins.currentStreak, 2)
        XCTAssertEqual(ins.favouriteKind, "ritual")
        XCTAssertEqual(ins.ritualGainMinutes, 0, accuracy: 0.001, "same hours ⇒ no invented gain")
    }
}

/// A seedable RNG so the generative-music tests are deterministic (the synth
/// uses the same xorshift on the audio thread).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
