import Foundation
import CoreGraphics
import ObjectiveC
import Darwin

/// An SDR luminance estimate, not a colorimeter measurement. Apple profiles use
/// the active preset's reported range and one read-only linear-brightness anchor.
/// Dell's uncalibrated linear model uses its published 450-nit SDR specification.
struct BrightnessProfile: Sendable {
    let minimumNits: Double
    let maximumNits: Double
    let sourceDescription: String
    let exponent: Double

    init(minimumNits: Double, maximumNits: Double, sourceDescription: String, exponent: Double = 1) {
        self.minimumNits = minimumNits
        self.maximumNits = maximumNits
        self.sourceDescription = sourceDescription
        self.exponent = exponent
    }

    func estimatedNits(level: Double) -> Double {
        guard level.isFinite else { return minimumNits }
        return minimumNits + (maximumNits - minimumNits) * pow(min(1, max(0, level)), exponent)
    }

    func level(forNits nits: Double) -> Double {
        guard nits.isFinite, maximumNits > minimumNits else { return 0 }
        let fraction = min(1, max(0, (nits - minimumNits) / (maximumNits - minimumNits)))
        return pow(fraction, 1 / exponent)
    }

    /// Cache the empirical fit for a session so matching does not keep changing
    /// its curve as sliders move. A changed macOS reference preset gets a new fit.
    @MainActor private static var appleProfiles: [String: BrightnessProfile] = [:]

    @MainActor static func forDisplay(_ display: DisplayInfo) -> BrightnessProfile? {
        if !display.isBuiltin {
            guard display.name.uppercased().contains("U2725QE") else { return nil }
            return BrightnessProfile(minimumNits: 0, maximumNits: 450,
                sourceDescription: "Dell U2725QE: published 450-nit SDR maximum; uncalibrated linear estimate. The zero endpoint is an assumption, not measured black or minimum brightness.")
        }
        guard let preset = AppleLuminanceReader.activePreset(displayID: display.id),
              let maximum = (preset["PresetHostMaxSliderBrightness"] as? NSNumber)?.doubleValue ?? (preset["PresetMaxSDRLuminance"] as? NSNumber)?.doubleValue,
              maximum.isFinite, maximum > 0, maximum <= 2000 else { return nil }
        let minimum = (preset["PresetHostMinSliderBrightness"] as? NSNumber)?.doubleValue ?? 0
        guard minimum.isFinite, minimum >= 0, minimum < maximum else { return nil }
        let key = "\(display.stableID):\(minimum):\(maximum):\(preset["PresetName"] ?? "")"
        if let cached = appleProfiles[key] { return cached }
        guard let user = AppleLuminanceReader.read("DisplayServicesGetBrightness", displayID: display.id),
              let linear = AppleLuminanceReader.read("DisplayServicesGetLinearBrightness", displayID: display.id),
              user > 0.05, user < 0.98, linear > 0, linear < 1 else { return nil }
        // Lunar uses active SDR maximum × DisplayServices linear brightness for
        // its nits reporting. Fit a monotonic power curve through that same
        // live anchor, rather than treating Apple's perceptual slider as linear.
        let anchor = min(1, max(0, (maximum * linear - minimum) / (maximum - minimum)))
        guard anchor > 0, anchor < 1 else { return nil }
        let exponent = log(anchor) / log(user)
        guard exponent.isFinite, exponent >= 0.2, exponent <= 8 else { return nil }
        let profile = BrightnessProfile(minimumNits: minimum, maximumNits: maximum,
            sourceDescription: "macOS active preset reports \(Int(maximum))-nit SDR slider maximum. Estimated curve fitted to a read-only system linear-brightness sample; not a measured panel calibration.", exponent: exponent)
        appleProfiles[key] = profile
        return profile
    }
}

/// Signatures verified against Lunar's public bridging declarations and the
/// Objective-C runtime. This reader never calls any display-setting method.
/// Sources: github.com/alin23/Lunar (DDC/Lunar-Bridging-Header.h,
/// Control/AppleNativeControl.swift, Utils/DisplayController.swift).
private enum AppleLuminanceReader {
    // Keep the singleton-owning framework loaded once for the process lifetime.
    @MainActor private static let monitorPanelAvailable = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY) != nil
    static func read(_ symbolName: String, displayID: UInt32) -> Double? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, symbolName) else { return nil }
        typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        var value: Float = 0
        guard unsafeBitCast(symbol, to: Getter.self)(displayID, &value) == 0, value.isFinite else { return nil }
        return Double(value)
    }

    @MainActor static func activePreset(displayID: UInt32) -> [String: Any]? {
        guard displayID <= UInt32(Int32.max), monitorPanelAvailable else { return nil }
        guard let managerClass = NSClassFromString("MPDisplayMgr"),
              let manager = object(managerClass, selector: "sharedMgr"),
              let lockMethod = method(manager, "tryLockAccess", encoding: "B16@0:8"),
              let unlockMethod = method(manager, "unlockAccess", encoding: "v16@0:8") else { return nil }
        typealias Lock = @convention(c) (AnyObject, Selector) -> Bool
        typealias Unlock = @convention(c) (AnyObject, Selector) -> Void
        guard unsafeBitCast(method_getImplementation(lockMethod), to: Lock.self)(manager, NSSelectorFromString("tryLockAccess")) else { return nil }
        defer { unsafeBitCast(method_getImplementation(unlockMethod), to: Unlock.self)(manager, NSSelectorFromString("unlockAccess")) }
        guard let displayMethod = method(manager, "displayWithID:", encoding: "@20@0:8i16") else { return nil }
        typealias Display = @convention(c) (AnyObject, Selector, Int32) -> Unmanaged<AnyObject>?
        guard let display = unsafeBitCast(method_getImplementation(displayMethod), to: Display.self)(manager, NSSelectorFromString("displayWithID:"), Int32(displayID))?.takeUnretainedValue(),
              let preset = object(display, selector: "activePreset") else { return nil }
        return object(preset, selector: "presetDictionary") as? [String: Any]
    }

    private static func method(_ receiver: AnyObject, _ selector: String, encoding: String) -> Method? {
        guard let cls = object_getClass(receiver), let method = class_getInstanceMethod(cls, NSSelectorFromString(selector)),
              let actual = method_getTypeEncoding(method), String(cString: actual) == encoding else { return nil }
        return method
    }
    private static func object(_ receiver: AnyObject, selector: String) -> AnyObject? {
        guard let method = method(receiver, selector, encoding: "@16@0:8") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(receiver, NSSelectorFromString(selector))?.takeUnretainedValue()
    }
}
