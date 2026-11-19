import SwiftUI

extension View {
    /// Keeps iPhone layout unchanged and stops iPad landscape from stretching
    /// lists and forms across the full window.
    func readableWidth() -> some View {
        frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }
}
