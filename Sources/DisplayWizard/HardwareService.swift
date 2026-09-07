import Foundation

/// Serializes DDC traffic on a dedicated queue. Suspending this actor never blocks
/// the main actor, even when a monitor takes several seconds to answer.
actor HardwareService {
    static let shared = HardwareService()
    private let queue = DispatchQueue(label: "DisplayWizard.hardware", qos: .userInitiated)

    func brightness(displayID: UInt32) async -> BrightnessStatus {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: DisplayBackend.brightness(displayID: displayID))
            }
        }
    }

    func setBrightness(displayID: UInt32, value: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try DisplayBackend.setBrightness(displayID: displayID, value: value)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
