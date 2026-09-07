import Testing
@testable import DisplayWizard

@Suite struct LinkedBrightnessTests {
    @Test func preservesOffsets() {
        let result = LinkedBrightness.targets(current: [1: 0.8, 2: 0.3], source: 2, requested: 0.4, linked: true)
        #expect(abs(result[1]! - 0.9) < 0.00001)
        #expect(abs(result[2]! - 0.4) < 0.00001)
    }
    @Test func clampsGroupAtUpperAndLowerLimits() {
        let upper = LinkedBrightness.targets(current: [1: 0.9, 2: 0.4], source: 2, requested: 0.9, linked: true)
        #expect(upper[1] == 1)
        #expect(abs(upper[2]! - 0.5) < 0.00001)
        let lower = LinkedBrightness.targets(current: upper, source: 1, requested: 0, linked: true)
        #expect(abs(lower[1]! - 0.5) < 0.00001)
        #expect(lower[2] == 0)
    }
    @Test func unlinkedOnlyChangesSource() {
        #expect(LinkedBrightness.targets(current: [1: 0.8, 2: 0.3], source: 2, requested: 0.9, linked: false) == [2: 0.9])
    }
    @Test func invalidInputsAndUnavailableDisplaysAreExcluded() {
        #expect(LinkedBrightness.targets(current: [1: 0.5], source: 1, requested: .nan, linked: true).isEmpty)
        #expect(LinkedBrightness.targets(current: [1: 0.5], source: 2, requested: 0.8, linked: true).isEmpty)
        #expect(LinkedBrightness.targets(current: [1: 0.5, 2: .nan, 3: 2], source: 1, requested: 0.6, linked: true) == [1: 0.6])
    }
    @Test func reversingAnAdjustmentRestoresOffset() {
        let start: [UInt32: Double] = [1: 0.83, 2: 0.32]
        let raised = LinkedBrightness.targets(current: start, source: 1, requested: 0.88, linked: true)
        let restored = LinkedBrightness.targets(current: raised, source: 1, requested: 0.83, linked: true)
        #expect(abs(restored[2]! - start[2]!) < 0.00001)
    }
}
