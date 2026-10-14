import Foundation
import UniformTypeIdentifiers

enum YouTubeLink {
    /// The 11-character video ID from youtube.com/watch, youtu.be, /shorts, /live or /embed links.
    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed), let host = url.host?.lowercased() else { return nil }
        let candidate: String?
        if host == "youtu.be" {
            candidate = url.pathComponents.dropFirst().first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            let parts = url.pathComponents
            if parts.count >= 3, ["shorts", "live", "embed", "v"].contains(parts[1]) { candidate = parts[2] }
            else { candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value }
        } else { candidate = nil }
        guard let id = candidate, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return id
    }
}

enum MediaDrop {
    /// Files the TV's media renderer can play: video, audio or pictures.
    static func playable(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return [.movie, .audio, .image].contains { type.conforms(to: $0) }
    }
}
