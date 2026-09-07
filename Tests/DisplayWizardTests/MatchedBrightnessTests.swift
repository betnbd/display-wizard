import Foundation
import Testing
@testable import DisplayWizard

struct MatchedBrightnessTests {
    private func profile(_ maximum: Double, minimum: Double = 0, exponent: Double = 1) -> BrightnessProfile {
        BrightnessProfile(minimumNits: minimum, maximumNits: maximum, sourceDescription: "Synthetic test profile", exponent: exponent)
    }

    @Test func differentMaximumsProduceDifferentPercentagesAtEqualLuminance() throws {
        let profiles: [UInt32: BrightnessProfile] = [1: profile(600), 5: profile(450)]
        let targets = MatchedBrightness.targets(profiles: profiles, gains: [:], source: 1, requested: 0.5)
        let builtIn = try #require(targets[1])
        let external = try #require(targets[5])
        #expect(abs(builtIn - 0.5) < 1e-9)
        #expect(abs(external - 2.0 / 3.0) < 1e-9)
        #expect(abs(profiles[1]!.estimatedNits(level: builtIn) - profiles[5]!.estimatedNits(level: external)) < 1e-9)
    }

    @Test func nonlinearCurveIsMonotonicAndInvertible() {
        let nonlinear = profile(600, minimum: 1, exponent: 4.2)
        var previous = -Double.infinity
        for step in 0...100 {
            let level = Double(step) / 100
            let nits = nonlinear.estimatedNits(level: level)
            #expect(nits >= previous)
            #expect(abs(nonlinear.level(forNits: nits) - level) < 1e-6)
            previous = nits
        }
        #expect(nonlinear.estimatedNits(level: -1) == 1)
        #expect(nonlinear.estimatedNits(level: 2) == 600)
        #expect(nonlinear.level(forNits: -100) == 0)
        #expect(nonlinear.level(forNits: 700) == 1)
        #expect(nonlinear.estimatedNits(level: .nan).isFinite)
    }

    @Test func commonCapsPreserveMatchAtBothEnds() throws {
        let profiles: [UInt32: BrightnessProfile] = [1: profile(600, minimum: 1, exponent: 4.2), 5: profile(450, minimum: 30)]
        for requested in [0.0, 1.0] {
            let targets = MatchedBrightness.targets(profiles: profiles, gains: [:], source: 1, requested: requested)
            let left = try #require(targets[1])
            let right = try #require(targets[5])
            let expected = requested == 0 ? 30.0 : 450.0
            #expect(abs(profiles[1]!.estimatedNits(level: left) - expected) < 1e-8)
            #expect(abs(profiles[5]!.estimatedNits(level: right) - expected) < 1e-8)
            #expect((0...1).contains(left) && (0...1).contains(right))
        }
    }

    @Test func gainsAreValidatedAndAppliedToCommonRange() throws {
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, 0.049, 20.01] {
            #expect(MatchedBrightness.validGain(invalid) == 1)
        }
        #expect(MatchedBrightness.validGain(nil) == 1)
        #expect(MatchedBrightness.validGain(0.05) == 0.05)
        #expect(MatchedBrightness.validGain(20) == 20)
        let profiles: [UInt32: BrightnessProfile] = [1: profile(600), 5: profile(450)]
        let targets = MatchedBrightness.targets(profiles: profiles, gains: [5: 0.5], source: 1, requested: 1)
        #expect(abs(try #require(targets[1]) - 225.0 / 600) < 1e-9)
        #expect(try #require(targets[5]) == 1)
    }

    @Test func visualGainReproducesManualMatch() throws {
        let builtIn = profile(600, minimum: 1, exponent: 4.2)
        let dell = profile(450)
        let referenceLevel = 0.73
        let manuallyMatchedDell = 0.47
        let referenceNits = builtIn.estimatedNits(level: referenceLevel)
        let gain = referenceNits / dell.estimatedNits(level: manuallyMatchedDell)
        let targets = MatchedBrightness.targets(profiles: [1: builtIn, 5: dell], gains: [1: 1, 5: gain], source: 1, requested: referenceLevel)
        #expect(abs(try #require(targets[1]) - referenceLevel) < 1e-8)
        #expect(abs(try #require(targets[5]) - manuallyMatchedDell) < 1e-8)
    }

    @Test func persistedRawMatchSurvivesRefittedAppleCurve() throws {
        let levels: [UInt32: Double] = [1: 0.73, 5: 0.47]
        for exponent in [3.1, 4.2, 5.3] {
            let profiles: [UInt32: BrightnessProfile] = [1: profile(600, minimum: 1, exponent: exponent), 5: profile(450)]
            let gains = try #require(MatchedBrightness.calibratedGains(profiles: profiles, levels: levels, reference: 1))
            let targets = MatchedBrightness.targets(profiles: profiles, gains: gains, source: 1, requested: 0.73)
            #expect(abs(try #require(targets[1]) - 0.73) < 1e-8)
            #expect(abs(try #require(targets[5]) - 0.47) < 1e-8)
        }
    }

    @Test func unsupportedOrNonoverlappingProfilesDoNotGenerateWrites() {
        #expect(MatchedBrightness.targets(profiles: [1: profile(600)], gains: [:], source: 1, requested: 0.5).isEmpty)
        let profiles: [UInt32: BrightnessProfile] = [1: profile(600, minimum: 500), 5: profile(450)]
        #expect(MatchedBrightness.targets(profiles: profiles, gains: [:], source: 1, requested: 0.5).isEmpty)
        #expect(MatchedBrightness.targets(profiles: [1: profile(600), 5: profile(450)], gains: [:], source: 99, requested: 0.5).isEmpty)
        #expect(MatchedBrightness.targets(profiles: [1: profile(600), 5: profile(450)], gains: [:], source: 1, requested: .nan).isEmpty)
    }

    @Test func olderPreferencesGetMatchDefaultsAndGainsRoundTrip() throws {
        let legacy = Data("{\"linkedBrightness\":true,\"restoreOnReconnect\":true}".utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        #expect(preferences.linkedBrightness && preferences.restoreOnReconnect)
        #expect(!preferences.matchedBrightness && preferences.brightnessMatchGains.isEmpty)
        #expect(preferences.brightnessMatchLevels.isEmpty && preferences.brightnessMatchReference == nil)
        preferences.matchedBrightness = true
        preferences.brightnessMatchGains = ["builtin-uuid": 1, "dell-uuid": 1.347]
        preferences.brightnessMatchLevels = ["builtin-uuid": 0.73, "dell-uuid": 0.47]
        preferences.brightnessMatchReference = "builtin-uuid"
        let encoded = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(Preferences.self, from: encoded)
        #expect(restored.matchedBrightness && restored.linkedBrightness)
        #expect(restored.brightnessMatchGains == preferences.brightnessMatchGains)
        #expect(restored.brightnessMatchLevels == preferences.brightnessMatchLevels)
        #expect(restored.brightnessMatchReference == "builtin-uuid")
    }
}
