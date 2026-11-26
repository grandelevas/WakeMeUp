import UIKit

enum DemoTenure {
    /// Long enough that a month, half a year, and a year of badges are unlocked, and the later ones stay locked.
    static func firstUse(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -14, to: now) ?? now.addingTimeInterval(-14 * 31 * 24 * 60 * 60)
    }
}

enum DemoMedia {
    /// Writes the demo voice clip and video poster into this app's sandbox. Demo mode only.
    static func install() {
        writeVoice()
        writePoster()
        writeVideoPlaceholder()
    }

    static func wavData(seconds: Int = 12, sampleRate: Int = 8_000) -> Data {
        let frames = max(1, seconds) * sampleRate
        let dataSize = frames * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize), to: &data)
        for index in 0..<frames {
            let angle = 2 * Double.pi * 440 * Double(index) / Double(sampleRate)
            var sample = Int16(sin(angle) * 4_000).littleEndian
            data.append(Data(bytes: &sample, count: 2))
        }
        return data
    }

    private static func writeVoice() {
        guard let directory = try? SoundFiles.librarySoundsDirectory() else { return }
        let url = directory.appendingPathComponent("\(DemoData.voiceSoundID).wav")
        if FileManager.default.fileExists(atPath: url.path) { return }
        try? wavData().write(to: url)
    }

    private static func writePoster() {
        guard let directory = try? VideoFiles.directory() else { return }
        let url = directory.appendingPathComponent("\(DemoData.videoID).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return }
        guard let jpeg = posterJPEG() else { return }
        try? jpeg.write(to: url)
    }

    private static func writeVideoPlaceholder() {
        guard let directory = try? VideoFiles.directory() else { return }
        let url = directory.appendingPathComponent("\(DemoData.videoID).mp4")
        if FileManager.default.fileExists(atPath: url.path) { return }
        try? Data([0]).write(to: url)
    }

    static func posterJPEG() -> Data? {
        let size = CGSize(width: 1200, height: 750)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(red: 1, green: 0.57, blue: 0.24, alpha: 1).cgColor,
                UIColor(red: 0.45, green: 0.18, blue: 0.48, alpha: 1).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            let symbol = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 220, weight: .regular))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let side: CGFloat = 280
            symbol?.draw(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
        }
        return image.jpegData(compressionQuality: 0.86)
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 4))
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 2))
    }
}
