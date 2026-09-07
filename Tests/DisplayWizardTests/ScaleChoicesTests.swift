import Testing
@testable import DisplayWizard

struct ScaleChoicesTests {
    private func mode(_ id: Int32, _ width: Int, _ height: Int, hidpi: Bool = true, hz: Double = 120) -> DisplayModeInfo {
        DisplayModeInfo(id: id, width: width, height: height, pixelWidth: width * (hidpi ? 2 : 1), pixelHeight: height * (hidpi ? 2 : 1), refreshRate: hz)
    }
    private func display(_ modes: [DisplayModeInfo], width: Int? = 3840, height: Int? = 2160, rotation: Double = 0) -> DisplayInfo {
        DisplayInfo(id: 5, stableID: "test", name: "Test", isBuiltin: false, isMain: false, rotation: rotation, modes: modes, currentModeID: modes[0].id, nativeWidth: width, nativeHeight: height)
    }

    @Test func nativePanelDefinesScaleNotSupersampledRenderBuffer() {
        let m = mode(1, 2560, 1440)
        let d = display([m])
        #expect(ModeChoices.scale(m, for: d) == 1.5)
        #expect(ModeChoices.scaleLabel(m, for: d) == "1.5×")
        #expect(ModeChoices.exactLabel(m, for: d) == "2560 × 1440 (150%) · HiDPI")
    }

    @Test func portraitUsesAlreadyOrientedNativeDimensions() {
        let m = mode(1, 1440, 2560)
        #expect(ModeChoices.scale(m, for: display([m], width: 2160, height: 3840, rotation: 90)) == 1.5)
    }

    @Test func unknownNativeOrMismatchedAspectRatioOmitsScaleClaims() {
        let m = mode(1, 2560, 1440)
        let d = display([m], width: nil, height: nil)
        #expect(ModeChoices.scale(m, for: d) == nil)
        #expect(ModeChoices.scalePresets(d).isEmpty)
        #expect(ModeChoices.exactLabel(m, for: d) == m.label)
        #expect(ModeChoices.scale(mode(2, 1024, 768), for: display([m])) == nil)
    }

    @Test func presetsPreferHiDPIAndKeepCurrentRefresh() {
        let d = display([mode(1, 1920, 1080), mode(2, 2560, 1440, hz: 60), mode(3, 2560, 1440), mode(4, 2560, 1440, hidpi: false), mode(5, 3840, 2160, hidpi: false)])
        #expect(ModeChoices.scalePresets(d).map(\.id) == [5, 3, 1])
    }

    @Test func nearbyPresetsShowActualScaleAndStayWithinTolerance() {
        let m = mode(1, 2624, 1476)
        let d = display([m])
        #expect(ModeChoices.scalePresets(d).map(\.id) == [1])
        #expect(ModeChoices.scaleLabel(m, for: d) == "≈1.46×")
        #expect(ModeChoices.exactLabel(m, for: d).contains("≈146%"))
        let distant = mode(2, 2800, 1575)
        #expect(ModeChoices.scalePresets(display([distant])).isEmpty)
    }
}
