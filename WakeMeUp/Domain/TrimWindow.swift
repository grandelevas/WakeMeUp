import Foundation

struct TrimWindow: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    static let maximumDuration: TimeInterval = 30
    static let minimumDuration: TimeInterval = 0.4

    var duration: TimeInterval { end - start }

    /// Clamps the selection to the asset and to the 30-second alarm-sound limit.
    /// Returns nil when the asset itself is too short to be an alarm tone.
    func clamped(to assetDuration: TimeInterval) -> TrimWindow? {
        guard assetDuration.isFinite, assetDuration >= Self.minimumDuration else { return nil }
        var start = min(max(0, self.start), assetDuration)
        var end = min(max(0, self.end), assetDuration)
        if end < start {
            swap(&start, &end)
        }
        if end - start < Self.minimumDuration {
            end = min(assetDuration, start + Self.minimumDuration)
            start = max(0, end - Self.minimumDuration)
        }
        if end - start > Self.maximumDuration {
            end = start + Self.maximumDuration
            if end > assetDuration {
                end = assetDuration
                start = max(0, end - Self.maximumDuration)
            }
        }
        guard end - start >= Self.minimumDuration - 0.001 else { return nil }
        return TrimWindow(start: start, end: end)
    }
}
