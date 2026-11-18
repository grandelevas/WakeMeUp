import Foundation

enum MusicService: String, Codable, Equatable, Hashable {
    case spotify
    case youTube
    case appleMusic
}

struct SongLink: Codable, Equatable, Hashable {
    var url: URL
    var service: MusicService

    /// Accepts Spotify, YouTube, and Apple Music links, including their URL schemes.
    static func parse(_ raw: String) -> SongLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if trimmed.contains("://") || trimmed.hasPrefix("spotify:") || trimmed.hasPrefix("music:") {
            withScheme = trimmed
        } else {
            withScheme = "https://" + trimmed
        }
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              let url = components.url else {
            return nil
        }
        let host = components.host?.lowercased() ?? ""
        let service: MusicService
        if scheme == "spotify" || host == "spotify.com" || host.hasSuffix(".spotify.com") {
            service = .spotify
        } else if scheme == "youtube"
            || host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "music.youtube.com" {
            service = .youTube
        } else if scheme == "music"
            || host == "music.apple.com"
            || host.hasSuffix(".music.apple.com")
            || host == "itunes.apple.com"
            || host.hasSuffix(".itunes.apple.com") {
            service = .appleMusic
        } else {
            return nil
        }
        return SongLink(url: url, service: service)
    }
}
