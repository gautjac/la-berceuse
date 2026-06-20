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
}
